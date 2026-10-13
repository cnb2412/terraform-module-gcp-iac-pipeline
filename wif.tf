# --- Workload Identity Federation (GitHub Actions OIDC) ---------------------------

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.seed_project_id
  workload_identity_pool_id = local.pool_id
  display_name              = substr("${local.repo_name} GitHub Actions", 0, 32)

  lifecycle {
    precondition {
      condition     = length(local.pool_id) >= 4 && length(local.pool_id) <= 32
      error_message = "Workload identity pool id \"${local.pool_id}\" must be 4-32 characters; shorten name_prefix."
    }
  }
}
#
# resource "google_iam_workload_identity_pool_provider" "github" {
#   project                            = var.seed_project_id
#   workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
#   workload_identity_pool_provider_id = "github-oidc"
#   display_name                       = "GitHub OIDC"
#
#   oidc {
#     issuer_uri = "https://token.actions.githubusercontent.com"
#   }
#
#   attribute_mapping = {
#     "google.subject"          = "assertion.sub"
#     "attribute.repository"    = "assertion.repository"
#     "attribute.repository_id" = "assertion.repository_id"
#     "attribute.repo_ref"      = "assertion.repository + '@' + assertion.ref"
#   }
#
#   # Pinned by immutable ID and by name: a renamed or re-created repo cannot take over.
#   attribute_condition = "assertion.repository_id == '${var.github_repository_id}' && assertion.repository == '${var.github_repository}'"
# }
