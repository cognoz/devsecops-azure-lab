variable "github_repo" {
  description = "GitHub repository in 'owner/repo' form. Used to scope the federated credential."
  type        = string
}

variable "github_oidc_branches" {
  description = "Branches that GitHub Actions can federate from. Add more later if needed."
  type        = list(string)
  default     = ["main", "dev"]
}
