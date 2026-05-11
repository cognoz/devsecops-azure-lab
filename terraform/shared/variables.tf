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

variable "owner_email" {
  description = "Tag value for ownership."
  type        = string
  default     = ""
}
