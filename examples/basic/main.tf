# Minimal example: one repository, a staging and a production environment.
# All values are placeholders; replace them before running.
#
# Staging shows both ways to grant roles on a CI service account:
#   - self_roles: the SA gets the role on itself (module-managed),
#   - a caller-side grant to another principal, using the module's outputs.

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.41"
    }
  }
}

provider "google" {
  region = "europe-west1"
}

module "ci_bootstrap" {
  source = "../.."

  seed_project_id      = "acme-iac-seed"
  location             = "europe-west1"
  name_prefix          = "acme-web"
  state_bucket_name    = "acme-web-tfstate-1234"
  github_repository    = "acme/web"
  github_repository_id = "123456789" # gh api repos/acme/web --jq .id

  environments = {
    staging = {
      project_id         = "acme-web-staging"
      billing_account_id = "000000-000000-000000"
      # any workflow run of the repository
      # The SA lives in the seed project, so project_roles can't grant this.
      # Lets the pipeline call signBlob/signJwt as itself, e.g.
      # `gcloud storage sign-url --impersonate-service-account=...` or V4 signed
      # URLs from client libraries, without a key file.
      self_roles = ["roles/iam.serviceAccountTokenCreator"]
    }
    production = {
      project_id         = "acme-web-prod"
      billing_account_id = "000000-000000-000000"
      # runs on main only
      ref           = "refs/heads/main"
      project_roles = ["roles/editor", "roles/resourcemanager.projectIamAdmin"]
    }
  }
}

# Caller-side grant on the staging SA, e.g. so platform admins can run
# `tofu plan --impersonate-service-account` locally. Unlike self_roles this widens
# who can act as the SA, so keep it off production.
resource "google_service_account_iam_member" "staging_admins_impersonate" {
  service_account_id = module.ci_bootstrap.environments["staging"].service_account_name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "group:platform-admins@acme.example"
}

output "github_actions_variables" {
  description = "Values to set as GitHub Actions variables in acme/web."
  value       = module.ci_bootstrap.github_actions_variables
}
