#!/usr/bin/env bash
# Mirror third-party container images into the shared ACR.
#
# Why: ArgoCD and Kyverno both pull from upstream registries (quay.io,
# ghcr.io). Each pull is a runtime dependency on an external registry —
# if that registry is down, scaling/restarts fail. Mirroring into ACR
# means the cluster only depends on ACR at runtime.
#
# A nice secondary benefit: az acr import preserves the OCI manifest and
# any signatures attached as referrers. So when we upgrade Kyverno later,
# we can (optionally) extend Kyverno's verify-image-signatures policy to
# also verify the *Kyverno team's* signatures on their own images.
#
# When to run:
#   - Once after `terraform apply` of the shared state creates ACR.
#   - Whenever you bump the chart version in gitops/apps/{argocd,kyverno}.yaml.
#
# Usage:
#   ACR_NAME=acrdevsecopsrk964 ./scripts/mirror-images.sh
#
# Prerequisites:
#   - az login + role assignment: 'AcrPush' on the target ACR (Owner also
#     works). Your shared admin role on shared/ covers this.

set -euo pipefail

ACR_NAME="${ACR_NAME:-acrdevsecopsrk964}"

# Versions — keep these in sync with the chart versions referenced from
# gitops/apps/*.yaml. Changing them here without updating the Applications
# means the chart will try to pull a tag that doesn't exist in ACR.
#
# These are the *application* versions inside the charts, not the chart
# versions themselves. Look them up with:
#   helm show chart argo/argo-cd --version <chart-version> | grep appVersion
#   helm show chart kyverno/kyverno --version <chart-version> | grep appVersion
ARGOCD_VERSION="v3.4.1"           # appVersion for chart 9.5.13
KYVERNO_VERSION="v1.18.0"         # appVersion for chart 3.8.0
REDIS_VERSION="7.2.4"             # ArgoCD's bundled Redis (single, not HA)

# Tracks failures so we don't bail on the first one — useful for
# diagnostic runs where you want to see all issues.
FAILED=()

mirror() {
  local source="$1"
  local target="$2"
  echo "→ mirror: $source"
  echo "       to: $ACR_NAME.azurecr.io/$target"

  if az acr import \
      --name "$ACR_NAME" \
      --source "$source" \
      --image "$target" \
      --force \
      --output none 2>&1; then
    echo "  ✓ ok"
  else
    echo "  ✗ FAILED"
    FAILED+=("$source")
  fi
  echo
}

echo "============================================================"
echo "Mirroring third-party images into $ACR_NAME"
echo "============================================================"
echo

# ---- ArgoCD ---------------------------------------------------------------
# All argocd-* components use the same image with different commands.
mirror "quay.io/argoproj/argocd:${ARGOCD_VERSION}" \
       "argoproj/argocd:${ARGOCD_VERSION}"

# Redis used by ArgoCD's repo-server cache.
mirror "public.ecr.aws/docker/library/redis:${REDIS_VERSION}-alpine" \
       "library/redis:${REDIS_VERSION}-alpine"

# ---- Kyverno --------------------------------------------------------------
# Five distinct images, all in ghcr.io/kyverno/.
for img in kyverno kyvernopre background-controller cleanup-controller reports-controller; do
  mirror "ghcr.io/kyverno/${img}:${KYVERNO_VERSION}" \
         "kyverno/${img}:${KYVERNO_VERSION}"
done

# ---- Summary --------------------------------------------------------------
echo "============================================================"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "All images mirrored successfully."
  echo
  echo "Verify with:"
  echo "  az acr repository list --name $ACR_NAME --output table"
else
  echo "Failed to mirror ${#FAILED[@]} image(s):"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
