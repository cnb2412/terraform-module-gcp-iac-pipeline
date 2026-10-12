# output "workload_identity_provider" {
#   description = "Full resource name of the GitHub OIDC provider, for google-github-actions/auth."
#   value       = google_iam_workload_identity_pool_provider.github.name
# }
#
# output "workload_identity_pool" {
#   description = "Full resource name of the Workload Identity pool."
#   value       = google_iam_workload_identity_pool.github.name
# }
#
output "state_bucket" {
  description = "Name of the remote state bucket."
  value       = google_storage_bucket.tfstate.name
}

output "environments" {
  description = "Per-environment hand-over values."
  value = {
    for env, cfg in var.environments : env => {
      project_id            = cfg.project_id
      service_account_email = google_service_account.ci[env].email
      # kms_key_id            = google_kms_crypto_key.tfstate[env].id
      state_prefix          = google_storage_managed_folder.env[env].name
    }
  }
}
#
# output "github_actions_variables" {
#   description = "Flat map ready to be set as GitHub Actions variables (GCP_WIF_PROVIDER, TF_STATE_BUCKET, GCP_PROJECT_ID_<ENV>, GCP_CI_SA_<ENV>, TF_STATE_KMS_KEY_<ENV>)."
#   value = merge(
#     {
#       GCP_WIF_PROVIDER = google_iam_workload_identity_pool_provider.github.name
#       TF_STATE_BUCKET  = google_storage_bucket.tfstate.name
#     },
#     { for env, cfg in var.environments : "GCP_PROJECT_ID_${upper(replace(env, "-", "_"))}" => cfg.project_id },
#     { for env, _ in var.environments : "GCP_CI_SA_${upper(replace(env, "-", "_"))}" => google_service_account.ci[env].email },
#     { for env, _ in var.environments : "TF_STATE_KMS_KEY_${upper(replace(env, "-", "_"))}" => google_kms_crypto_key.tfstate[env].id },
#   )
# }
