locals {
  name_prefix    = "${var.lab_name}-rk964"
  kv_shared_name = "kv-shr-${local.name_prefix}"
}

resource "azurerm_key_vault" "shared" {
  name                       = local.kv_shared_name
  location                   = azurerm_resource_group.shared.location
  resource_group_name        = azurerm_resource_group.shared.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true

  # Shared KV holds long-lived secrets — give it real protection.
  # Note: purge_protection cannot be disabled once enabled. Acceptable here
  # because this vault is explicitly meant to survive lab destroy/rebuild cycles.
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # Only allow access via RBAC role assignments below. No public network rules
  # locked down yet — add network_acls block later if you want to restrict to
  # your IP / AKS subnet.

  tags = merge(local.common_tags, {
    lifecycle_scope = "shared"
    purpose         = "persistent-secrets"
  })
}

# You as Key Vault Administrator (manage secrets/keys/certs and RBAC on the vault).
resource "azurerm_role_assignment" "kv_shared_admin_self" {
  scope                = azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
