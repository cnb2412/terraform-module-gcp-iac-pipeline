# --- Remote state ----------------------------------------------------------------
# One bucket, one managed folder per environment. Each CI service account can only
# read and write objects inside its own folder.

resource "google_storage_bucket" "tfstate" {
  project                     = var.seed_project_id
  name                        = var.state_bucket_name
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# resource "google_storage_managed_folder" "env" {
#   for_each = var.environments
#   bucket   = google_storage_bucket.tfstate.name
#   name     = "${each.key}/"
# }
#
# resource "google_storage_managed_folder_iam_member" "ci" {
#   for_each       = var.environments
#   bucket         = google_storage_bucket.tfstate.name
#   managed_folder = google_storage_managed_folder.env[each.key].name
#   role           = "roles/storage.objectAdmin"
#   member         = google_service_account.ci[each.key].member
# }
