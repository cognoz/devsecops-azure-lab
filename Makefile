.PHONY: help bootstrap \
        shared-init shared-plan shared-apply shared-destroy \
        init plan apply destroy fmt validate \
        kubeconfig outputs outputs-github sync-github-vars \
        argocd-ui argocd-password

TF_DIR := terraform

SHARED_DIR  := $(TF_DIR)/shared
CLUSTER_DIR := $(TF_DIR)/cluster

help:
	@echo "Bootstrap (run once):"
	@echo "  bootstrap          Create the storage account that holds tf state."
	@echo ""
	@echo "Shared lifecycle (long-lived: ACR, shared RG):"
	@echo "  shared-init        terraform init for shared/"
	@echo "  shared-plan        terraform plan for shared/"
	@echo "  shared-apply       terraform apply for shared/"
	@echo "  shared-destroy     terraform destroy for shared/ (rare - nukes ACR)"
	@echo ""
	@echo "Cluster lifecycle (daily destroy/apply):"
	@echo "  init               terraform init for cluster/"
	@echo "  plan               terraform plan for cluster/"
	@echo "  apply              terraform apply for cluster/"
	@echo "  destroy            terraform destroy for cluster/ (preserves ACR)"
	@echo ""
	@echo "Operational helpers:"
	@echo "  fmt                terraform fmt + validate across both configs"
	@echo "  kubeconfig         az aks get-credentials for the current cluster"
	@echo "  outputs            Show cluster terraform outputs"
	@echo "  outputs-github     Print GitHub repo variables, paste-ready"
	@echo "  sync-github-vars   Push all GitHub repo variables via 'gh'"
	@echo "  argocd-ui          Port-forward ArgoCD UI to https://localhost:8080"
	@echo "  argocd-password    Print the initial ArgoCD admin password"

bootstrap:
	./scripts/bootstrap-state.sh

# ---- Shared lifecycle ------------------------------------------------------

shared-init:
	cd $(SHARED_DIR) && terraform init -backend-config=../backend-shared.tfvars

shared-plan:
	cd $(SHARED_DIR) && terraform plan -var-file=../shared.tfvars

shared-apply:
	cd $(SHARED_DIR) && terraform apply -var-file=../shared.tfvars

shared-destroy:
	cd $(SHARED_DIR) && terraform destroy -var-file=../shared.tfvars

# ---- Cluster lifecycle -----------------------------------------------------

init:
	cd $(CLUSTER_DIR) && terraform init -backend-config=../backend-cluster.tfvars

plan:
	cd $(CLUSTER_DIR) && terraform plan -var-file=../cluster.tfvars

apply:
	cd $(CLUSTER_DIR) && terraform apply -var-file=../cluster.tfvars

destroy:
	cd $(CLUSTER_DIR) && terraform destroy -var-file=../cluster.tfvars -parallelism=2

# ---- Helpers ---------------------------------------------------------------

fmt:
	cd $(SHARED_DIR)  && terraform fmt -recursive && terraform validate
	cd $(CLUSTER_DIR) && terraform fmt -recursive && terraform validate

kubeconfig:
	cd $(CLUSTER_DIR) && \
	  RG=$$(terraform output -raw resource_group_name) && \
	  AKS=$$(terraform output -raw aks_cluster_name) && \
	  az aks get-credentials --resource-group $$RG --name $$AKS --overwrite-existing

outputs:
	@cd $(CLUSTER_DIR) && terraform output

outputs-github:
	@echo "=== GitHub repo variables ==="
	@echo "Set these at: Settings -> Secrets and variables -> Actions -> Variables"
	@echo ""
	@cd $(CLUSTER_DIR) && \
	  printf "%-25s %s\n" "AZURE_CLIENT_ID"        "$$(terraform output -raw github_actions_client_id)"        && \
	  printf "%-25s %s\n" "AZURE_TENANT_ID"        "$$(terraform output -raw github_actions_tenant_id)"        && \
	  printf "%-25s %s\n" "AZURE_SUBSCRIPTION_ID"  "$$(terraform output -raw github_actions_subscription_id)"  && \
	  printf "%-25s %s\n" "ACR_NAME"               "$$(terraform output -raw acr_name)"                        && \
	  printf "%-25s %s\n" "ACR_LOGIN_SERVER"       "$$(terraform output -raw acr_login_server)"                && \
	  printf "%-25s %s\n" "AKS_CLUSTER_NAME"       "$$(terraform output -raw aks_cluster_name)"                && \
	  printf "%-25s %s\n" "AZURE_RESOURCE_GROUP"   "$$(terraform output -raw resource_group_name)"

sync-github-vars:
	@command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed."; exit 1; }
	@gh auth status >/dev/null 2>&1 || { echo "Not authenticated. Run: gh auth login"; exit 1; }
	@cd $(CLUSTER_DIR) && \
	  echo "Syncing Terraform outputs to GitHub repo variables..." && \
	  gh variable set AZURE_CLIENT_ID         --body "$$(terraform output -raw github_actions_client_id)"         && \
	  gh variable set AZURE_TENANT_ID         --body "$$(terraform output -raw github_actions_tenant_id)"         && \
	  gh variable set AZURE_SUBSCRIPTION_ID   --body "$$(terraform output -raw github_actions_subscription_id)"   && \
	  gh variable set ACR_NAME                --body "$$(terraform output -raw acr_name)"                         && \
	  gh variable set ACR_LOGIN_SERVER        --body "$$(terraform output -raw acr_login_server)"                 && \
	  gh variable set AKS_CLUSTER_NAME        --body "$$(terraform output -raw aks_cluster_name)"                 && \
	  gh variable set AZURE_RESOURCE_GROUP    --body "$$(terraform output -raw resource_group_name)"              && \
	  echo "Done."

argocd-ui:
	@echo "Opening port-forward to ArgoCD UI on https://localhost:8080"
	@echo "Login: admin / <password from 'make argocd-password'>"
	kubectl port-forward -n argocd svc/argocd-server 8080:443

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d && echo
