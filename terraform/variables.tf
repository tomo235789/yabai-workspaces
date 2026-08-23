variable "github_owner" {
  description = "GitHub user or org that owns the repository."
  type        = string
  default     = "tomo235789"
}

variable "repository" {
  description = "Repository name (without the owner)."
  type        = string
  default     = "yabai-workspaces"
}

variable "ci_check_name" {
  description = "Name of the CI status check that must pass before merging to main. Must match the job name in .github/workflows/ci.yml."
  type        = string
  default     = "Build, test & lint"
}
