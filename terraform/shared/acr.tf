locals {
  acr_name = "acr${var.lab_name}rk964"
}

resource "azurerm_container_registry" "lab" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "Standard"

  # No admin user - authentication via Workload Identity from CI and AKS kubelet.
  admin_enabled = false

  tags = local.common_tags
}
