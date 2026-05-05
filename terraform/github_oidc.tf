# Entra application that GitHub Actions will impersonate.
resource "azuread_application" "github" {
  display_name = "sp-github-${local.name_prefix}"
  description  = "Federated identity for GitHub Actions (${var.github_repo})"
}

# Service principal backing the application.
resource "azuread_service_principal" "github" {
  client_id = azuread_application.github.client_id
}

# One federated credential per branch we want to allow.
# The 'subject' is the exact claim GitHub Actions presents in its OIDC token.
resource "azuread_application_federated_identity_credential" "github_branch" {
  for_each = toset(var.github_oidc_branches)

  application_id = azuread_application.github.id
  display_name   = "github-${replace(each.value, "/", "-")}"
  description    = "GitHub Actions for ${var.github_repo} on branch ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/${each.value}"
}

# Optional but useful: also allow pull-request workflows. Lets PR jobs run dry-runs
# (terraform plan, image build for scanning) without granting any push permissions —
# we control that at the role-assignment level, not here.
resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.github.id
  display_name   = "github-pull-request"
  description    = "GitHub Actions PR workflows for ${var.github_repo}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

# Role assignments. We grant just what the pipeline needs:
#   - AcrPush on the registry (build & push images)
#   - AKS RBAC Writer on the cluster (deploy via kubectl from CI if needed)
# We do NOT grant Contributor/Owner
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github.object_id
}

resource "azurerm_role_assignment" "github_aks_writer" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = azuread_service_principal.github.object_id
}
