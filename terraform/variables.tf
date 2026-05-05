variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "lab_name" {
  description = "Short name used to derive resource names."
  type        = string
  default     = "devsecops"

}

variable "owner_email" {
  description = "Owner tag."
  type        = string
  default     = ""
}

variable "aks_kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to take the default for the region."
  type        = string
  default     = null
}

variable "aks_system_node_count" {
  description = "Node count for the system pool (not spotted)."
  type        = number
  default     = 1
}

variable "aks_user_node_min" {
  description = "Minimum nodes in the user (workload) pool. Spot pool with autoscaler."
  type        = number
  default     = 0
}

variable "aks_user_node_max" {
  description = "Maximum nodes in the user (workload) pool."
  type        = number
  default     = 3
}

variable "aks_user_vm_size" {
  description = "VM size for user node pool."
  type        = string
  default     = "Standard_B2s"
}

variable "log_analytics_retention_days" {
  description = "Log retention. 30 days default."
  type        = number
  default     = 30
}

variable "budget_amount_usd" {
  description = "Monthly budget cap in USD. Alerts fire at 50% and 90%."
  type        = number
  default     = 150
}

variable "budget_contact_email" {
  description = "Email to alert when budget thresholds are hit."
  type        = string
  default     = ""
}
