resource "azurerm_kubernetes_cluster" "lab" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = "aks-${local.name_prefix}"
  kubernetes_version  = var.aks_kubernetes_version

  # Workload Identity foundation. Both must be true for the federated identity
  # pattern to work later (GitHub Actions OIDC -> Azure, and pod -> Azure).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Azure CNI Overlay: modern, doesn't burn the VNet IP space, supported by Network Policy.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    pod_cidr            = "10.244.0.0/16"
  }

  # System pool. Cannot be spot. Keep it small.
  default_node_pool {
    name                         = "system"
    node_count                   = var.aks_system_node_count
    vm_size                      = "Standard_B2s_v2"
    only_critical_addons_enabled = true
    orchestrator_version         = var.aks_kubernetes_version
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Container Insights -> Log Analytics
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.lab.id
    msi_auth_for_monitoring_enabled = true
  }

  # Local accounts disabled = AAD-only auth.
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  local_account_disabled            = true
  role_based_access_control_enabled = true

  tags = local.common_tags
}

# User (workload) pool: spot, autoscaler, can scale to zero overnight.
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
  spot_max_price  = -1 # -1 = pay up to on-demand price, never get evicted on price

  # Spot pools require this taint, workloads must tolerate it.
  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  tags = local.common_tags
}

# Allow AKS to pull from our ACR. This is the AcrPull role on the kubelet identity.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
}

# Make yourself a cluster admin via Azure RBAC. Otherwise even with kubectl creds
# you'll be 403'd because local accounts are disabled.
resource "azurerm_role_assignment" "aks_rbac_admin_self" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Also grant the cluster-level admin role so `az aks get-credentials` works.
resource "azurerm_role_assignment" "aks_admin_self" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = data.azurerm_client_config.current.object_id
}
