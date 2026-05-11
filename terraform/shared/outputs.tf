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
