output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.lab.name
}

output "aks_oidc_issuer_url" {
  description = "Needed for federated workload identity setup later."
  value       = azurerm_kubernetes_cluster.lab.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.lab.login_server
}

output "key_vault_uri" {
  value = azurerm_key_vault.lab.vault_uri
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}

output "kubeconfig_command" {
  description = "Run this to get kubectl access to the cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.lab.name} --name ${azurerm_kubernetes_cluster.lab.name}"
}