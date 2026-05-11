resource "azuread_application" "github" {
  display_name = "sp-github-${local.name_prefix}"
  description  = "Federated identity for GitHub Actions (${var.github_repo})"
}

resource "azuread_service_principal" "github" {
  client_id = azuread_application.github.client_id
}

resource "azuread_application_federated_identity_credential" "github_branch" {
  for_each = toset(var.github_oidc_branches)

  application_id = azuread_application.github.id
  display_name   = "github-${replace(each.value, "/", "-")}"
  description    = "GitHub Actions for ${var.github_repo} on branch ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/${each.value}"
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.github.id
  display_name   = "github-pull-request"
  description    = "GitHub Actions PR workflows for ${var.github_repo}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

# AcrPush on the shared ACR (ID from remote state).
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = local.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github.object_id
}

resource "azurerm_role_assignment" "github_aks_writer" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = azuread_service_principal.github.object_id
}

resource "azurerm_role_assignment" "github_aks_user" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.github.object_id
}
