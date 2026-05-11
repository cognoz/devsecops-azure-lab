provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy               = true
      purge_soft_deleted_keys_on_destroy         = true
      purge_soft_deleted_secrets_on_destroy      = true
      purge_soft_deleted_certificates_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  name_prefix = "${var.lab_name}-rk964"

  common_tags = {
    project     = "devsecops-lab"
    managed_by  = "terraform"
    environment = "lab"
    owner       = var.owner_email
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}
