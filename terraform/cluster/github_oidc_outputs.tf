output "github_actions_client_id" {
  description = "Set as a GitHub repo variable: AZURE_CLIENT_ID"
  value       = azuread_application.github.client_id
}

output "github_actions_tenant_id" {
  description = "Set as a GitHub repo variable: AZURE_TENANT_ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "github_actions_subscription_id" {
  description = "Set as a GitHub repo variable: AZURE_SUBSCRIPTION_ID"
  value       = data.azurerm_subscription.current.subscription_id
}
