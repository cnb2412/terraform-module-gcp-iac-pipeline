locals {
  repo_name = split("/", var.github_repository)[1]
  pool_id   = "${var.name_prefix}-github"

  # Which workflow runs may impersonate each environment's SA.
  principal_attr = {
    for env, cfg in var.environments : env => (
      cfg.ref == null
      ? "attribute.repository/${var.github_repository}"
      : "attribute.repo_ref/${var.github_repository}@${cfg.ref}"
    )
  }

  project_grants = {
    for g in flatten([
      for env, cfg in var.environments : [
        for role in cfg.project_roles : { env = env, project = cfg.project_id, role = role }
      ]
    ]) : "${g.env}/${g.role}" => g
  }

  billing_grants = {
    for env, cfg in var.environments : env => cfg.billing_account_id
    if cfg.billing_account_id != null
  }
}

# --- CI service accounts ------------------------------------------------------------

resource "google_service_account" "ci" {
  for_each     = var.environments
  project      = var.seed_project_id
  account_id   = "${var.name_prefix}-ci-${each.key}"
  display_name = "${local.repo_name} CI (${each.key})"

  lifecycle {
    precondition {
      condition     = length("${var.name_prefix}-ci-${each.key}") <= 30
      error_message = "Service account id \"${var.name_prefix}-ci-${each.key}\" exceeds 30 characters; shorten name_prefix or the environment name."
    }
  }
}

# resource "google_service_account_iam_member" "wif" {
#   for_each           = var.environments
#   service_account_id = google_service_account.ci[each.key].name
#   role               = "roles/iam.workloadIdentityUser"
#   member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/${local.principal_attr[each.key]}"
# }
#
# --- Grants in the environment (additive only, never _policy/_binding) --------------

resource "google_project_iam_member" "ci" {
  for_each = local.project_grants
  project  = each.value.project
  role     = each.value.role
  member   = google_service_account.ci[each.value.env].member
}

resource "google_billing_account_iam_member" "ci_costs" {
  for_each           = local.billing_grants
  billing_account_id = each.value
  role               = "roles/billing.costsManager"
  member             = google_service_account.ci[each.key].member
}
