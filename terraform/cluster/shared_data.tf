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
