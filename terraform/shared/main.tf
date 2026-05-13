provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  # No suffix on the RG name - we want stable, predictable naming for the
  # long-lived RG. Suffix only goes into globally-unique resources.
  rg_name = "rg-shared-${var.lab_name}"

  common_tags = {
    project    = "devsecops-lab"
    managed_by = "terraform"
    lifecycle  = "persistent"
    owner      = var.owner_email
  }
}

resource "azurerm_resource_group" "shared" {
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags
}

