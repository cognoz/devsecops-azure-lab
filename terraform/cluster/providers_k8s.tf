# Kubernetes and Helm providers, configured to authenticate to AAD-enabled AKS
# via kubelogin's "azurecli" mode. This reuses whatever credentials the local
# `az login` session has — same auth path as a human running kubectl locally.

locals {
  # The "server-id" arg kubelogin needs is the well-known AKS AAD server app ID,
  # the same constant for every AKS cluster everywhere. Hardcoding it is correct.
  aks_aad_server_id = "6dae42f8-4368-4678-94ff-3960e28e3630"
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.lab.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.lab.kube_config[0].cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login", "azurecli",
      "--server-id", local.aks_aad_server_id,
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.lab.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.lab.kube_config[0].cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login", "azurecli",
        "--server-id", local.aks_aad_server_id,
      ]
    }
  }
}
