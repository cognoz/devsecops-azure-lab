# Read shared/'s outputs from its state file. This is the customer-realistic
# pattern for cross-config references. Errors at plan time if shared/ doesn't
# exist or doesn't export the expected outputs - much better than silent
# wrong-name lookups.
data "terraform_remote_state" "shared" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.shared_state_resource_group_name
    storage_account_name = var.shared_state_storage_account_name
    container_name       = var.shared_state_container_name
    key                  = var.shared_state_key
    use_azuread_auth     = true
  }
}

# Hoist the outputs into locals for convenient referencing throughout cluster/.
locals {
  acr_id           = data.terraform_remote_state.shared.outputs.acr_id
  acr_name         = data.terraform_remote_state.shared.outputs.acr_name
  acr_login_server = data.terraform_remote_state.shared.outputs.acr_login_server
}

# Look up the shared KV by name from the shared state output.
# We use a data source (not the output directly) so we get the full resource
# object — needed for things like vault_uri in the right form, and so role
# assignments reference a "live" resource ID rather than a string from state.
data "azurerm_key_vault" "shared" {
  name                = data.terraform_remote_state.shared.outputs.kv_shared_name
  resource_group_name = data.terraform_remote_state.shared.outputs.shared_resource_group_name
}

# Data source to read the GitHub App secrets from shared KV at apply time.
# Your Administrator role on the shared KV (granted in shared state) covers
# read access. ArgoCD itself does not touch KV — it reads from a k8s Secret
# that Terraform plants in the argocd namespace below.
data "azurerm_key_vault_secret" "argocd_github_app_id" {
  name         = "argocd-github-app-id"
  key_vault_id = data.azurerm_key_vault.shared.id
}

data "azurerm_key_vault_secret" "argocd_github_app_installation_id" {
  name         = "argocd-github-app-installation-id"
  key_vault_id = data.azurerm_key_vault.shared.id
}

data "azurerm_key_vault_secret" "argocd_github_app_private_key" {
  name         = "argocd-github-app-private-key"
  key_vault_id = data.azurerm_key_vault.shared.id
}
