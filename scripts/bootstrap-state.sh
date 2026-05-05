#!/usr/bin/env bash
# Bootstrap the Azure resources needed to host Terraform remote state.
# Run this ONCE per subscription. After this, all other infra is managed by Terraform.
set -euo pipefail

LOCATION="westeurope"
RG_NAME="rg-tfstate-devsecops-lab"
# Storage account names must be globally unique, 3-24 chars, lowercase + digits only.
# We append a short hash of the subscription id for stability.
SUB_ID="$(az account show --query id -o tsv)"
SA_NAME="tfstatedevsecopslabrk"
CONTAINER_NAME="tfstate"
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

#az group create --name "${RG_NAME}" --location "${LOCATION}" -o none
#az storage account create \
#    --name "${SA_NAME}" \
#    --resource-group "${RG_NAME}" \
#    --location "${LOCATION}" \
#    --sku Standard_LRS \
#    --kind StorageV2 \
#    --min-tls-version TLS1_2 \
#    --allow-blob-public-access false \
#    -o none
#
#az storage container create \
#  --name "${CONTAINER_NAME}" \
#  --account-name "${SA_NAME}" \
#  --auth-mode login \
#  -o none || true

az role assignment create \
  --assignee "${USER_OBJECT_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/${SUB_ID}/resourceGroups/rg-tfstate-devsecops-lab/providers/Microsoft.Storage/storageAccounts/${SA_NAME}"
