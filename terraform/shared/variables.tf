variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "lab_name" {
  description = "Short stable name used in shared resource naming."
  type        = string
  default     = "devsecops"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.lab_name))
    error_message = "lab_name must be 3-12 lowercase alphanumeric characters."
  }
}

variable "budget_amount_usd" {
  description = "Subscription-scoped monthly budget cap in USD."
  type        = number
  default     = 150
}

variable "budget_contact_email" {
  description = "Email recipient for budget alerts."
  type        = string
  default     = ""
}

variable "owner_email" {
  description = "Tag value for ownership."
  type        = string
  default     = ""
}

# Defender for Cloud — subscription-scoped plan + extensions.
variable "defender_for_containers_enabled" {
  description = "Enable Microsoft Defender for Containers plan on the subscription."
  type        = bool
  default     = true
}

variable "defender_export_enabled" {
  description = "Whether to wire Defender for Cloud continuous export into the cluster's Log Analytics workspace. Requires the cluster (and its LAW) to exist."
  type        = bool
  default     = true
}

# Not using cluster state to keep shared one independent
variable "defender_export_law_resource_group" {
  description = "Resource group of the Log Analytics workspace that Defender should export into. Defaults to the cluster RG."
  type        = string
  default     = "rg-devsecops-rk964"
}

variable "defender_export_law_name" {
  description = "Name of the Log Analytics workspace that Defender should export into."
  type        = string
  default     = "log-devsecops-rk964"
}
