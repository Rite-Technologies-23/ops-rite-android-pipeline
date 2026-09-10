###############################################################
# 🧩 Terraform: GitHub Actions Secrets Setup
# This is an EXAMPLE for provisioning repository secrets -- it is not wired
# into any workflow in this repo.
#
# github_actions_secret.plaintext_value means the secret VALUES are written
# into the Terraform state file (GitHub only stores them encrypted on its
# side; Terraform's own record of what it applied is not encrypted by
# default). Before applying this for real:
#   - Configure a `backend` with encryption at rest (e.g. an S3 backend with
#     SSE, or Terraform Cloud/Enterprise) -- do NOT use local state for this.
#   - Never commit terraform.tfstate to source control.
#   - Scope github_token to the minimum needed to manage Action secrets on
#     ONE repo, not full `repo` + `admin:repo_hook` -- a fine-grained PAT
#     limited to "Secrets" (read/write) on the target repository is enough.
#
# Requires: terraform-provider-github
###############################################################

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
}

variable "github_token" {
  description = "GitHub PAT scoped to Actions secrets (read/write) on repo_name only -- not a broad 'repo' + 'admin:repo_hook' token"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "repo_name" {
  description = "Repository name to which secrets are applied"
  type        = string
}

variable "secrets" {
  description = "Map of secret names to values"
  type        = map(string)
  default     = {}
}

# -------------------------------------------------------------
# Create secrets dynamically
# -------------------------------------------------------------
resource "github_actions_secret" "repo_secrets" {
  for_each   = var.secrets
  repository = var.repo_name
  secret_name = each.key
  plaintext_value = each.value
}

# Example usage:
# terraform apply -var 'github_token=ghp_xxx' -var 'github_owner=Rite-Technologies-23' \
#   -var 'repo_name=reusable-repo-android' \
#   -var 'secrets={ SONAR_TOKEN="xxx", CODACY_PROJECT_TOKEN="yyy" }'
