terraform {
  # optional() object attributes with defaults need Terraform >= 1.3 / OpenTofu >= 1.6.
  required_version = ">= 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.41"
    }
  }
}
