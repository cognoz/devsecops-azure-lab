# ACR names globally unique
locals {
  acr_name = "acr${var.lab_name}rk964"
}

resource "azurerm_container_registry" "lab" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  # standard as we want to sign images and geo-replicated
  sku = "Standard"

  # No admin user: we'll authenticate via Workload Identity from CI and from the cluster.
  admin_enabled = false

  tags = local.common_tags
}