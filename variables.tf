variable "seed_project_id" {
  description = "Project that hosts the state bucket, KMS keys, Workload Identity pool and CI service accounts."
  type        = string
}

variable "location" {
  description = "Location of the state bucket and the KMS key ring, e.g. \"europe-west1\"."
  type        = string
  default     = "europe-west1"
}

variable "name_prefix" {
  description = "Prefix for resource names (key ring, WIF pool, service accounts), e.g. \"acme-web\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket for remote state. Must be globally unique."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate, as \"owner/name\"."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must have the form \"owner/name\"."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric ID of the GitHub repository (gh api repos/OWNER/NAME --jq .id). Pins trust so a renamed or re-created repository cannot take over."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be numeric."
  }
}

variable "environments" {
  description = <<-EOT
    Deployment environments, keyed by a short lowercase name (used in state prefixes, key and SA names).
      project_id         - GCP project the environment's CI deploys into.
      billing_account_id - Billing account on which CI gets roles/billing.costsManager. null = no billing grant.
      ref                - Git ref allowed to impersonate this environment's SA, e.g. "refs/heads/main".
                           null = any workflow run of the repository.
      project_roles      - Roles granted to the CI SA on project_id (additive, never authoritative).
      self_roles         - Roles granted to the CI SA on itself, e.g. roles/iam.serviceAccountTokenCreator
                           so it can sign its own JWTs and blobs. The member is always the SA itself.
  EOT
  type = map(object({
    project_id         = string
    billing_account_id = optional(string)
    ref                = optional(string)
    project_roles      = optional(list(string), ["roles/owner"])
    self_roles         = optional(list(string), [])
  }))

  validation {
    condition     = length(var.environments) > 0
    error_message = "At least one environment is required."
  }

  validation {
    condition     = alltrue([for k in keys(var.environments) : can(regex("^[a-z][a-z0-9-]*$", k))])
    error_message = "Environment names must be lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for e in values(var.environments) : e.ref == null || can(regex("^refs/", e.ref))])
    error_message = "ref must be a full git ref such as \"refs/heads/main\" or \"refs/tags/v1\", or null."
  }
}
