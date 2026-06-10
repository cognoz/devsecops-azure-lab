output "resource_group_name" {
  description = "Set as a GitHub repo variable: AZURE_RESOURCE_GROUP"
  value       = azurerm_resource_group.lab.name
}

output "aks_cluster_name" {
  description = "Set as a GitHub repo variable: AKS_CLUSTER_NAME"
  value       = module.aks.cluster_name
}

output "aks_oidc_issuer_url" {
  description = "Needed for federated workload identity setup."
  value       = module.aks.oidc_issuer_url
}

output "key_vault_uri" {
  value = azurerm_key_vault.lab.vault_uri
}

output "kubeconfig_command" {
  description = "Run this to get kubectl access to the cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.lab.name} --name ${module.aks.cluster_name}"
}

# Pass-through outputs from shared/ so 'make sync-github-vars' can read
# everything from a single 'terraform output' call against cluster/.
output "acr_name" {
  description = "Set as a GitHub repo variable: ACR_NAME (sourced from shared/)"
  value       = local.acr_name
}

output "acr_login_server" {
  description = "Set as a GitHub repo variable: ACR_LOGIN_SERVER (sourced from shared/)"
  value       = local.acr_login_server
}
