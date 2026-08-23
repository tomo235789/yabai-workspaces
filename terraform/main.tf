# Non-secret GitHub repository configuration as code.
#
# Scope: branch protection (CI must pass, PR required) and Actions permissions.
# The signing / notarization secrets are intentionally NOT managed here — set
# those with `gh secret set` (see terraform/README.md) so their plaintext never
# lands in Terraform state.

provider "github" {
  owner = var.github_owner
  # Authenticate with a Personal Access Token (repo admin scope) via the
  # GITHUB_TOKEN environment variable — never hard-code it here.
}

# Require the CI check to pass, and require changes to go through a PR, before
# landing on main. Mirrors the "no direct push to main" convention.
resource "github_branch_protection" "main" {
  repository_id  = var.repository
  pattern        = "main"
  enforce_admins = false

  required_status_checks {
    strict   = true
    contexts = [var.ci_check_name]
  }

  required_pull_request_reviews {
    required_approving_review_count = 0 # PR required, but self-merge is allowed
  }
}

# Be explicit about Actions being enabled and which actions are allowed.
resource "github_actions_repository_permissions" "this" {
  repository      = var.repository
  enabled         = true
  allowed_actions = "all"
}
