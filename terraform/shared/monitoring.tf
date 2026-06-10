resource "azurerm_log_analytics_workspace" "lab" {
  name                = "log-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.shared.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

resource "azurerm_log_analytics_solution" "security" {
  solution_name         = "Security"
  location              = azurerm_resource_group.shared.location
  resource_group_name   = azurerm_resource_group.shared.name
  workspace_resource_id = azurerm_log_analytics_workspace.lab.id
  workspace_name        = azurerm_log_analytics_workspace.lab.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Security"
  }

  tags = local.common_tags
}
