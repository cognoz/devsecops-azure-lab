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
	cd $(TF_DIR) && terraform output
