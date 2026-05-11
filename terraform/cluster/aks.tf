resource "azurerm_kubernetes_cluster" "lab" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = "aks-${local.name_prefix}"
  kubernetes_version  = var.aks_kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    pod_cidr            = "10.244.0.0/16"
  }

  default_node_pool {
    name                         = "system"
    node_count                   = var.aks_system_node_count
    vm_size                      = "Standard_B2ls_v2"
    only_critical_addons_enabled = true
    orchestrator_version         = var.aks_kubernetes_version
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.lab.id
    msi_auth_for_monitoring_enabled = true
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  local_account_disabled            = true
  role_based_access_control_enabled = true

  tags = local.common_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.lab.id
  vm_size               = var.aks_user_vm_size
  orchestrator_version  = var.aks_kubernetes_version

  auto_scaling_enabled = true
  min_count            = var.aks_user_node_min
  max_count            = var.aks_user_node_max

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1

  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

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
