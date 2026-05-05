locals {
  kv_name = "kv-${local.name_prefix}"
}

resource "azurerm_key_vault" "lab" {
  name                = local.kv_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  # Just for lab, so we can destroy anytime
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = local.common_tags
}

# Current user as Admin
resource "azurerm_role_assignment" "kv_admin_self" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
