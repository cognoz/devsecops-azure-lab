output "acr_id" {
  description = "ACR resource ID. Used by cluster/ for AcrPull role assignment."
  value       = azurerm_container_registry.lab.id
}

output "acr_name" {
  description = "ACR name. Used for GitHub repo variable: ACR_NAME."
  value       = azurerm_container_registry.lab.name
}

output "acr_login_server" {
  description = "ACR login server. Used for GitHub repo variable: ACR_LOGIN_SERVER."
  value       = azurerm_container_registry.lab.login_server
}

output "shared_resource_group_name" {
  description = "Name of the long-lived shared RG."
  value       = azurerm_resource_group.shared.name
}

output "kv_shared_id" {
  description = "Resource ID of the shared key vault"
  value       = azurerm_key_vault.shared.id
}

output "kv_shared_name" {
  description = "Name of the shared key vault"
  value       = azurerm_key_vault.shared.name
}

output "kv_shared_uri" {
  description = "DNS name of the shared key vault (https://...vault.azure.net/)"
  value       = azurerm_key_vault.shared.vault_uri
}

output "defender_for_containers_enabled" {
  description = "Whether the Defender for Containers subscription plan is on. Cluster/ uses this to decide whether to attach the per-cluster Defender sensor."
  value       = var.defender_for_containers_enabled
}

output "defender_export_resource_id" {
  description = "Resource ID of the Defender continuous export automation."
  value       = try(azurerm_security_center_automation.export_to_workspace[0].id, null)
}
