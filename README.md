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
- **Isolation between environments**: each service account can only reach its own state folder and its own KMS key.
  A compromised staging run can neither read nor decrypt production state.
- **Grants are always `_iam_member`** and never `_iam_binding` or `_iam_policy`. The module adds
  bindings and never removes bindings that something else manages.

## Usage

```hcl
module "ci_bootstrap" {
  source = "git::https://github.com/OWNER/REPO.git?ref=v1.0.0"

  seed_project_id      = "acme-iac-seed"
  location             = "europe-west1"
  name_prefix          = "acme-web"
  state_bucket_name    = "acme-web-tfstate-1234"
  github_repository    = "acme/web"
  github_repository_id = "123456789" # gh api repos/acme/web --jq .id

  environments = {
    staging = {
      project_id = "acme-web-staging"
    }
    production = {
      project_id = "acme-web-prod"
      ref        = "refs/heads/main"
    }
  }
}
```

[`examples/basic`](examples/basic/main.tf) has a complete runnable configuration that sets
billing accounts and narrower project roles.

The module does not configure a provider. The caller passes in a `google` provider. Whoever runs
the apply needs, in the seed project, permission to create buckets, KMS resources, WIF pools and
service accounts. They also need `resourcemanager.projects.setIamPolicy` on every target project
and `billing.accounts.setIamPolicy` on every billing account they reference.

The seed project must have these APIs enabled: `storage.googleapis.com`, `cloudkms.googleapis.com`,
`iam.googleapis.com`, `iamcredentials.googleapis.com`, `sts.googleapis.com`,
`cloudresourcemanager.googleapis.com` and `cloudbilling.googleapis.com`.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `seed_project_id` | `string` | yes | Project that hosts bucket, KMS, WIF pool and service accounts. |
| `location` | `string` | yes | Location of the bucket and key ring. |
| `name_prefix` | `string` | yes | Prefix for the key ring (`<p>-tfstate`), pool (`<p>-github`) and SAs (`<p>-ci-<env>`). |
| `state_bucket_name` | `string` | yes | Globally unique bucket name. |
| `github_repository` | `string` | yes | `owner/name`. |
| `github_repository_id` | `string` | yes | Numeric repository ID. |
| `environments` | `map(object)` | yes | See below. |

Each entry in `environments` has these fields:

| Field | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | – | Project the environment deploys into. |
| `billing_account_id` | `string` | `null` | Grants `roles/billing.costsManager` (for budgets) when set. |
| `ref` | `string` | `null` | Full git ref allowed to impersonate the SA; `null` = whole repository. |
| `project_roles` | `list(string)` | `["roles/owner"]` | Roles granted to the SA on `project_id`. |

These limits are checked at plan time:

- The SA id `<name_prefix>-ci-<env>` can be at most 30 characters.
- The pool id `<name_prefix>-github` must be 4–32 characters.
- Environment names may contain only lowercase letters, digits and hyphens.

## Outputs

| Name | Description |
|---|---|
| `workload_identity_provider` | Full provider resource name, used as `workload_identity_provider` in `google-github-actions/auth`. |
| `workload_identity_pool` | Full pool resource name. |
| `state_bucket` | Bucket name. |
| `environments` | `map(env => { project_id, service_account_email, kms_key_id, state_prefix })`. |
| `github_actions_variables` | Flat map: `GCP_WIF_PROVIDER`, `TF_STATE_BUCKET`, plus `GCP_PROJECT_ID_<ENV>`, `GCP_CI_SA_<ENV>` and `TF_STATE_KMS_KEY_<ENV>` for each environment. The env name is uppercased with `-` → `_`. |

To push the outputs into the application repository as GitHub Actions variables:

```sh
tofu output -json github_actions_variables \
  | jq -r 'to_entries[] | "\(.key) \(.value)"' \
  | while read -r k v; do gh variable set "$k" --body "$v" --repo OWNER/NAME; done
```

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

The state bucket and the KMS keys have `lifecycle { prevent_destroy = true }`. Terraform does not
allow this setting to come from a variable, so it is hardcoded. To tear the module down you have
to remove those lines in a local copy. Even then, GCP never deletes KMS keys. It only destroys
their key versions, and a key ring name can't be reused in the same project and location.

Removing an environment from `environments` deletes that environment's service account, its grants and
its managed folder. Its KMS key is protected by `prevent_destroy`, so the plan fails until you
deal with that key on purpose.

## Layout

| File | Contents |
|---|---|
| `state.tf` | State bucket, one managed folder per environment, folder IAM |
| `kms.tf` | Key ring, one key per environment, key IAM |
| `wif.tf` | Workload Identity pool and GitHub OIDC provider |
| `iam.tf` | CI service accounts, `workloadIdentityUser`, project and billing grants |
| `variables.tf`, `outputs.tf`, `versions.tf` | Interface and version constraints |
| `examples/basic/` | Example caller |

## Requirements

| Name | Version |
|---|---|
| OpenTofu / Terraform | ≥ 1.6 / ≥ 1.3 |
| `hashicorp/google` | ≥ 5.41 |

## Known gaps

These were noted on 2026-10-11 and are not yet resolved:

- **No KMS key rotation.** `rotation_period` is not set and there is no input for it.
- **`roles/owner` is the default `project_roles`.** It is broad. Set narrower roles for each
  environment where you can, as `examples/basic` does for production.
