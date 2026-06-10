module "aks" {
  source = "github.com/cognoz/terraform-azurerm-aks?ref=v0.2.0"

  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location
  cluster_name        = "aks-${local.name_prefix}"
  kubernetes_version  = var.aks_kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # System pool. only_critical_addons + max_surge 10%
  default_node_pool = {
    name                 = "system"
    vm_size              = "Standard_B2ls_v2"
    node_count           = var.aks_system_node_count
    orchestrator_version = var.aks_kubernetes_version
  }

  # User pool as a spot pool. The module auto-injects the spot taint AND label,
  additional_node_pools = {
    user = {
      vm_size              = var.aks_user_vm_size
      orchestrator_version = var.aks_kubernetes_version
      priority             = "Spot"
      spot_max_price       = -1
      enable_auto_scaling  = true
      min_count            = var.aks_user_node_min
      max_count            = var.aks_user_node_max
    }
  }

  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    pod_cidr            = "10.244.0.0/16"
  }

  # AAD / Azure RBAC.
  azure_rbac_enabled = true
  aad_tenant_id      = data.azurerm_client_config.current.tenant_id

  # Monitoring (oms_agent) + Defender both point at the lab workspace.
  log_analytics_workspace_id                    = azurerm_log_analytics_workspace.lab.id
  oms_msi_auth_enabled                          = true
  microsoft_defender_log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id

  tags = local.common_tags
}

# AcrPull on the cluster's kubelet identity, scoped to the shared ACR.
# ACR ID comes from shared/'s remote state.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = local.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "aks_rbac_admin_self" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "aks_admin_self" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = data.azurerm_client_config.current.object_id
}
