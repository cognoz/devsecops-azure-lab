.PHONY: help bootstrap init plan apply destroy fmt validate kubeconfig outputs

TF_DIR := terraform
BACKEND_CONFIG := backend.tfvars
TFVARS := terraform.tfvars

help:
	@echo "Targets:"
	@echo "  bootstrap   Create the storage account that will hold Terraform state. Run once."
	@echo "  init        terraform init with backend config"
	@echo "  plan        terraform plan"
	@echo "  apply       terraform apply"
	@echo "  destroy     terraform destroy (also runs at end of day to save money)"
	@echo "  fmt         terraform fmt + validate"
	@echo "  kubeconfig  Run az aks get-credentials for the lab cluster"
	@echo "  outputs     Show terraform outputs"

bootstrap:
	./scripts/bootstrap-state.sh

init:
	cd $(TF_DIR) && terraform init -backend-config=$(BACKEND_CONFIG)

plan:
	cd $(TF_DIR) && terraform plan -var-file=$(TFVARS)

apply:
	cd $(TF_DIR) && terraform apply -var-file=$(TFVARS)

destroy:
	cd $(TF_DIR) && terraform destroy -var-file=$(TFVARS)

fmt:
	cd $(TF_DIR) && terraform fmt -recursive && terraform validate

kubeconfig:
	cd $(TF_DIR) && \
	  RG=$$(terraform output -raw resource_group_name) && \
	  AKS=$$(terraform output -raw aks_cluster_name) && \
	  az aks get-credentials --resource-group $$RG --name $$AKS --overwrite-existing

outputs:
	@cd $(TF_DIR) && terraform output

outputs-github:
	@echo "=== GitHub repo variables ==="
	@echo "Set these at: Settings -> Secrets and variables -> Actions -> Variables"
	@echo ""
	@cd $(TF_DIR) && \
	  printf "%-25s %s\n" "AZURE_CLIENT_ID"        "$$(terraform output -raw github_actions_client_id)"        && \
	  printf "%-25s %s\n" "AZURE_TENANT_ID"        "$$(terraform output -raw github_actions_tenant_id)"        && \
	  printf "%-25s %s\n" "AZURE_SUBSCRIPTION_ID"  "$$(terraform output -raw github_actions_subscription_id)"  && \
	  printf "%-25s %s\n" "ACR_NAME"               "$$(terraform output -raw acr_name)"                        && \
	  printf "%-25s %s\n" "ACR_LOGIN_SERVER"       "$$(terraform output -raw acr_login_server)"                && \
	  printf "%-25s %s\n" "AKS_CLUSTER_NAME"       "$$(terraform output -raw aks_cluster_name)"                && \
	  printf "%-25s %s\n" "AZURE_RESOURCE_GROUP"   "$$(terraform output -raw resource_group_name)"
