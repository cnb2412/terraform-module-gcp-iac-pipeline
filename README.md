# gcp-ci-bootstrap

This module creates the seed infrastructure that lets a GitHub Actions pipeline run
OpenTofu/Terraform against one or more Google Cloud projects without any long-lived keys.

For every environment you declare (for example `staging` and `production`) you get:

- a **CI service account**, which GitHub Actions can impersonate through Workload Identity Federation,
- its own **state prefix** (a GCS managed folder) that only that service account can read and write,
- its own **KMS key** for OpenTofu client-side state encryption,
- **additive** IAM grants on the target project and, optionally, the billing account.

```
seed project
├── GCS bucket <state_bucket_name>          versioned, public access prevented
│   ├── staging/      ← objectAdmin: SA staging
│   └── production/   ← objectAdmin: SA production
├── KMS key ring <prefix>-tfstate
│   ├── tfstate-staging      ← encrypt/decrypt: SA staging
│   └── tfstate-production   ← encrypt/decrypt: SA production
├── WIF pool <prefix>-github / provider github-oidc
│       condition: repository_id == <id> && repository == <owner/name>
└── service accounts <prefix>-ci-<env>
        workloadIdentityUser ← principalSet (whole repo, or a single ref)
        <env>.self_roles     ← SA <env> itself

target projects:     <env>.project_roles               → SA <env>
billing accounts:    roles/billing.costsManager        → SA <env>
```

## Trust model

- **Who may authenticate at all**: the provider's `attribute_condition` checks both the
  repository's **immutable numeric ID** and its **name**. A deleted repository that someone
  re-creates under the same name has a new ID, so it is rejected. A renamed repository fails
  the name check until you update `github_repository`.
- **Who may become which service account**: this is set per environment with `ref`.
  - `ref = null`: any workflow run of the repository, including any branch and pull requests from
    branches in the same repository. This fits staging.
  - `ref = "refs/heads/main"`: only runs whose `GITHUB_REF` is exactly that ref. This fits production.
    Combine it with branch protection on `main`.
- **Grants on the service account itself**: `self_roles` only ever names the SA itself as member,
  so it can't add a new way to become the SA. Grants you add in your own code using the
  `service_account_name` output can, so they need the same care as `ref`
  (see [Roles on the CI service account](#roles-on-the-ci-service-account)).
- **Isolation between environments**: each service account can only reach its own state folder and its own KMS key.
  A compromised staging run can neither read nor decrypt production state.
- **Grants are always `_iam_member`** and never `_iam_binding` or `_iam_policy`. The module adds
  bindings and never removes bindings that something else manages.

## Usage

```hcl
module "ci_bootstrap" {
  source = "git::https://github.com/OWNER/REPO.git?ref=v0.1.0"

  seed_project_id      = "acme-iac-seed"
  location             = "europe-west1"
  name_prefix          = "acme-web"
  state_bucket_name    = "acme-web-tfstate-1234"
  github_repository    = "acme/web"
  github_repository_id = "123456789" # gh api repos/acme/web --jq .id

  environments = {
    staging = {
      project_id = "acme-web-staging"
      self_roles = ["roles/iam.serviceAccountTokenCreator"] # signed URLs / JWTs as itself
    }
    production = {
      project_id = "acme-web-prod"
      ref        = "refs/heads/main"
    }
  }
}
```

[`examples/basic`](examples/basic/main.tf) has a complete runnable configuration that sets
billing accounts, narrower project roles, `self_roles` and a caller-side grant on the staging SA.

The module does not configure a provider. The caller passes in a `google` provider. Whoever runs
the apply needs, in the seed project, permission to create buckets, KMS resources, WIF pools and
service accounts. They also need `resourcemanager.projects.setIamPolicy` on every target project
and `billing.accounts.setIamPolicy` on every billing account they reference.

The seed project must have these APIs enabled: `storage.googleapis.com`, `cloudkms.googleapis.com`,
`iam.googleapis.com`, `iamcredentials.googleapis.com`, `sts.googleapis.com`,
`cloudresourcemanager.googleapis.com` and `cloudbilling.googleapis.com`.

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environments | Deployment environments, keyed by a short lowercase name (used in state prefixes, key and SA names).<br/>  project\_id         - GCP project the environment's CI deploys into.<br/>  billing\_account\_id - Billing account on which CI gets roles/billing.costsManager. null = no billing grant.<br/>  ref                - Git ref allowed to impersonate this environment's SA, e.g. "refs/heads/main".<br/>                       null = any workflow run of the repository.<br/>  project\_roles      - Roles granted to the CI SA on project\_id (additive, never authoritative).<br/>  self\_roles         - Roles granted to the CI SA on itself, e.g. roles/iam.serviceAccountTokenCreator<br/>                       so it can sign its own JWTs and blobs. The member is always the SA itself. | <pre>map(object({<br/>    project_id         = string<br/>    billing_account_id = optional(string)<br/>    ref                = optional(string)<br/>    project_roles      = optional(list(string), ["roles/owner"])<br/>    self_roles         = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| github\_repository | GitHub repository allowed to authenticate, as "owner/name". | `string` | n/a | yes |
| github\_repository\_id | Immutable numeric ID of the GitHub repository (gh api repos/OWNER/NAME --jq .id). Pins trust so a renamed or re-created repository cannot take over. | `string` | n/a | yes |
| location | Location of the state bucket and the KMS key ring, e.g. "europe-west1". | `string` | `"europe-west1"` | no |
| name\_prefix | Prefix for resource names (key ring, WIF pool, service accounts), e.g. "acme-web". | `string` | n/a | yes |
| seed\_project\_id | Project that hosts the state bucket, KMS keys, Workload Identity pool and CI service accounts. | `string` | n/a | yes |
| state\_bucket\_name | Name of the GCS bucket for remote state. Must be globally unique. | `string` | n/a | yes |

### Outputs

| Name | Description |
| ---- | ----------- |
| environments | Per-environment hand-over values: map(env => { project\_id, service\_account\_email, service\_account\_name, service\_account\_member, kms\_key\_id, state\_prefix }). |
| github\_actions\_variables | Flat map ready to be set as GitHub Actions variables (GCP\_WIF\_PROVIDER, TF\_STATE\_BUCKET, GCP\_PROJECT\_ID\_{ENV}, GCP\_CI\_SA\_{ENV}, TF\_STATE\_KMS\_KEY\_{ENV}). {ENV} is the environment name uppercased with - replaced by \_. |
| state\_bucket | Name of the remote state bucket. |
| workload\_identity\_pool | Full resource name of the Workload Identity pool. |
| workload\_identity\_provider | Full resource name of the GitHub OIDC provider, for google-github-actions/auth. |
<!-- END_TF_DOCS -->

### `environments` entries

Each entry in `environments` has these fields:

| Field | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | – | Project the environment deploys into. |
| `billing_account_id` | `string` | `null` | Grants `roles/billing.costsManager` (for budgets) when set. |
| `ref` | `string` | `null` | Full git ref allowed to impersonate the SA; `null` = whole repository. |
| `project_roles` | `list(string)` | `["roles/owner"]` | Roles granted to the SA on `project_id`. |
| `self_roles` | `list(string)` | `[]` | Roles granted to the SA on itself, e.g. `roles/iam.serviceAccountTokenCreator` for `signJwt`/`signBlob`. `project_roles` can't do this because the SA lives in the seed project. |

These limits are checked at plan time:

- The SA id `<name_prefix>-ci-<env>` can be at most 30 characters.
- The pool id `<name_prefix>-github` must be 4–32 characters.
- Environment names may contain only lowercase letters, digits and hyphens.

### Pushing outputs to GitHub

To push the outputs into the application repository as GitHub Actions variables:

```sh
tofu output -json github_actions_variables \
  | jq -r 'to_entries[] | "\(.key) \(.value)"' \
  | while read -r k v; do gh variable set "$k" --body "$v" --repo OWNER/NAME; done
```

## Roles on the CI service account

The CI service accounts live in the **seed project**, not in the target project. `project_roles`
therefore can't grant anything on the SA itself, not even with `roles/owner`. There are two ways
to grant roles on the SA.

**`self_roles`: the SA on itself.** The usual case is `roles/iam.serviceAccountTokenCreator`, which
lets the pipeline call `signBlob`/`signJwt` as its own identity. Without a key file, that is how
it creates signed URLs or self-signed JWTs:

```hcl
environments = {
  staging = {
    project_id = "acme-web-staging"
    self_roles = ["roles/iam.serviceAccountTokenCreator"]
  }
}
```

```yaml
  - run: |
      gcloud storage sign-url gs://acme-web-assets/report.pdf --duration=1h \
        --impersonate-service-account=${{ vars.GCP_CI_SA_STAGING }}
```

**Your own grants to other principals.** The `environments` output has `service_account_name` and
`service_account_member` for each environment, so you can add grants in your own code:

```hcl
resource "google_service_account_iam_member" "staging_admins_impersonate" {
  service_account_id = module.ci_bootstrap.environments["staging"].service_account_name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "group:platform-admins@acme.example"
}
```

A grant like this gives the group a second way to act as the SA, alongside GitHub Actions.
Keep such grants off production.

## Consuming it from the pipeline

GitHub Actions job:

```yaml
permissions:
  contents: read
  id-token: write   # required for OIDC

steps:
  - uses: actions/checkout@v4
  - uses: google-github-actions/auth@v2
    with:
      workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
      service_account: ${{ vars.GCP_CI_SA_STAGING }}
  - uses: opentofu/setup-opentofu@v1
  - run: tofu init && tofu plan
    env:
      TF_VAR_project_id: ${{ vars.GCP_PROJECT_ID_STAGING }}
```

Backend and encryption in the application's IaC (OpenTofu ≥ 1.7). Each environment uses
its own prefix and its own key:

```hcl
terraform {
  backend "gcs" {
    bucket = "<TF_STATE_BUCKET>"
    prefix = "staging" # must match the managed folder; the SA has no access elsewhere
  }

  encryption {
    key_provider "gcp_kms" "env" {
      kms_encryption_key = "<TF_STATE_KMS_KEY_STAGING>"
      key_length         = 32
    }
    method "aes_gcm" "env" {
      keys = key_provider.gcp_kms.env
    }
    state {
      method   = method.aes_gcm.env
      enforced = true
    }
    plan {
      method   = method.aes_gcm.env
      enforced = true
    }
  }
}
```

## Destroying

The state bucket and the KMS keys have `lifecycle { prevent_destroy = false }`, so nothing in the
module blocks a destroy. Terraform does not allow this setting to come from a variable. If you want
the protection, set it to `true` in a local copy. Even without it, GCP never deletes KMS keys. It
only destroys their key versions, and a key ring name can't be reused in the same project and
location. The bucket does not set `force_destroy`, so deleting it fails while it still holds
state objects.

Removing an environment from `environments` deletes that environment's service account, its grants
and its managed folder, and destroys the key versions of its KMS key. State encrypted with that key
can no longer be decrypted once the versions are gone. Move or decrypt that environment's state
first if you still need it.

## Layout

| File | Contents |
|---|---|
| `state.tf` | State bucket, one managed folder per environment, folder IAM |
| `kms.tf` | Key ring, one key per environment, key IAM |
| `wif.tf` | Workload Identity pool and GitHub OIDC provider |
| `iam.tf` | CI service accounts, `workloadIdentityUser`, self grants, project and billing grants |
| `variables.tf`, `outputs.tf`, `provider.tf` | Interface and version constraints |
| `examples/basic/` | Example caller, including `self_roles` and a caller-side SA grant |

## Requirements

| Name | Version |
|---|---|
| OpenTofu / Terraform | ≥ 1.6 / ≥ 1.3 |
| `hashicorp/google` | ≥ 5.41 |

## Development

Run the same checks as CI locally with `pre-commit run --all-files`. It needs `tofu`, `tflint`,
`trivy`, `terraform-docs` and `pre-commit`. The hooks run fmt, validate, tflint, trivy (HIGH and
CRITICAL) and terraform-docs, which regenerates the input and output tables above.

CI (`.github/workflows/ci.yml`) runs these hooks on every push to `main` and on every pull request. It also:

- validates the module with the minimum and the latest versions of OpenTofu, Terraform and the
  `google` provider from the table above,
- uploads trivy findings of every severity to the repository's Security tab, without failing the build.

## Known gaps

These were noted on 2026-10-11 and are not yet resolved:

- **No KMS key rotation.** `rotation_period` is not set and there is no input for it.
- **`roles/owner` is the default `project_roles`.** It is broad. Set narrower roles for each
  environment where you can, as `examples/basic` does for production.

Noted on 2026-10-13:

- **Tool versions are not updated automatically.** Dependabot bumps the GitHub Actions only. The
  hook revisions in `.pre-commit-config.yaml`, the tflint plugin and the tool versions in
  `ci.yml` need `pre-commit autoupdate` and manual bumps, or Renovate.
