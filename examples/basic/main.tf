# Minimal example: one repository, a staging and a production environment.
# All values are placeholders; replace them before running.

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

output "github_actions_variables" {
  description = "Values to set as GitHub Actions variables in acme/web."
  value       = module.ci_bootstrap.github_actions_variables
}
