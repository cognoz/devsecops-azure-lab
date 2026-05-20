variable "location" {
  description = "Azure region for cluster resources."
  type        = string
  default     = "westeurope"
}

variable "lab_name" {
  description = "Short stable name. Must match shared/'s lab_name for ACR reference."
  type        = string
  default     = "devsecops"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.lab_name))
    error_message = "lab_name must be 3-12 lowercase alphanumeric characters."
  }
}

variable "owner_email" {
  description = "Owner tag."
  type        = string
  default     = ""
}

variable "aks_kubernetes_version" {
  description = "AKS Kubernetes version. null = region default."
  type        = string
  default     = null
}

variable "aks_system_node_count" {
  description = "Node count for the (non-spot) system pool."
  type        = number
  default     = 1
}

variable "aks_user_node_min" {
  description = "Minimum nodes in the spot user pool."
  type        = number
  default     = 0
}

variable "aks_user_node_max" {
  description = "Maximum nodes in the spot user pool."
  type        = number
  default     = 3
}

variable "aks_user_vm_size" {
  description = "VM size for user node pool."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "log_analytics_retention_days" {
  description = "Log retention in days."
  type        = number
  default     = 30
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version."
  type        = string
  default     = "9.5.13"
}

variable "argocd_apps_chart_version" {
  description = "ArgoCD-apps Helm chart version (used to bootstrap the root app-of-apps)."
  type        = string
  default     = "2.0.4"
}

variable "gitops_branch" {
  description = "Git branch ArgoCD tracks for the gitops/ directory."
  type        = string
  default     = "main"
}

# GitHub OIDC inputs (used by github_oidc.tf which moves over unchanged)
variable "github_repo" {
  description = "GitHub repository in 'owner/repo' form."
  type        = string
}

variable "github_oidc_branches" {
  description = "Branches GitHub Actions can federate from."
  type        = list(string)
  default     = ["main", "dev"]
}

# Remote state backend config for reading shared/ outputs.
# Populated at apply time from the same backend storage account.
variable "shared_state_resource_group_name" {
  description = "RG of the Terraform state storage account."
  type        = string
}

variable "shared_state_storage_account_name" {
  description = "Storage account holding both shared.tfstate and cluster.tfstate."
  type        = string
}

variable "shared_state_container_name" {
  description = "Blob container holding both state files."
  type        = string
  default     = "tfstate"
}

variable "shared_state_key" {
  description = "Blob key for shared.tfstate."
  type        = string
  default     = "shared.tfstate"
}
