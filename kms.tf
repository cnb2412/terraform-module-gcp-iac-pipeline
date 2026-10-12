# --- KMS (OpenTofu client-side state encryption) ---------------------------------
# One key per environment, so a compromised staging pipeline cannot decrypt
# production state.

# resource "google_kms_key_ring" "tfstate" {
#   project  = var.seed_project_id
#   name     = "${var.name_prefix}-tfstate"
#   location = var.location
# }

# resource "google_kms_crypto_key" "tfstate" {
#   for_each = var.environments
#   name     = "tfstate-${each.key}"
#   key_ring = google_kms_key_ring.tfstate.id
#
#   lifecycle {
#     prevent_destroy = false
#   }
# }

# resource "google_kms_crypto_key_iam_member" "ci" {
#   for_each      = var.environments
#   crypto_key_id = google_kms_crypto_key.tfstate[each.key].id
#   role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
#   member        = google_service_account.ci[each.key].member
# }
