#!/usr/bin/env bash
# Mirror third-party container images into the shared ACR.
#
# Two mirror paths:
#   1. mirror() — uses `az acr import`. ACR's import service pulls the
#      source image directly into the registry. Fast, no local disk used,
#      preserves manifest + referrers. This is the default path.
#   2. mirror_via_docker() — uses local `docker pull` then `docker push`.
#      Used only as a fallback for images where `az acr import` hits 429s
#      from upstream rate limits. ACR's import IPs are shared across
#      tenants and frequently throttled on docker.io/library/* and
#      public.ecr.aws/docker/library/*, which is why both Redis images
#      route through the docker fallback.
#
# When to run:
#   - Once after `terraform apply` of the shared state creates ACR.
#   - Whenever you bump the chart version in gitops/apps/*.yaml.
#
# Usage:
#   ACR_NAME=acrdevsecopsrk964 ./scripts/mirror-images.sh
#
# Prerequisites:
#   - az login + role assignment: 'AcrPush' on the target ACR (Owner also
#     works). Your shared admin role on shared/ covers this.
#   - Local docker daemon running, used only for the docker-fallback path
#     (the script auto-skips that path if docker isn't available, with
#     a clear warning).

set -euo pipefail

ACR_NAME="${ACR_NAME:-acrdevsecopsrk964}"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

# Versions — keep these in sync with the chart versions referenced from
# gitops/apps/*.yaml. Changing them here without updating the Applications
# means the chart will try to pull a tag that doesn't exist in ACR.
#
ARGOCD_VERSION="v3.4.1"                # appVersion for chart 9.5.13
KYVERNO_VERSION="v1.18.0"              # appVersion for chart 3.8.0
ARGOCD_REDIS_VERSION="7.2.4"           # Redis bundled with ArgoCD's repo-server cache

FALCO_VERSION="0.43.1"                  
FALCO_VERSION="0.39.2"                  
FALCOCTL_VERSION="0.13.0"               # init/sidecar container for rule validation
FALCOSIDEKICK_VERSION="2.33.0"          # subchart appVersion
FALCOSIDEKICK_UI_VERSION="2.3.0"        # subchart appVersion
FALCOSIDEKICK_UI_REDIS_VERSION="7.4.2"  # Redis backing Falcosidekick UI

# Tracks failures so we don't bail on the first one — useful for
# diagnostic runs where you want to see all issues.
FAILED=()

# ----------------------------------------------------------------------------
# Default path: ACR import. Fast, no local disk, preserves manifests + refs.
# Fails (TOOMANYREQUESTS / 429) when ACR's shared import IP is rate-limited
# by the source registry. When that happens for a given image, switch it to
# mirror_via_docker below.
# ----------------------------------------------------------------------------
mirror() {
  local source="$1"
  local target="$2"
  echo "→ mirror (import):  $source"
  echo "          to:        $ACR_LOGIN_SERVER/$target"

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

# ----------------------------------------------------------------------------
# Fallback path: docker pull → docker tag → docker push.
#
# We pull to the local docker daemon (laptop IP, fresh rate-limit budget)
# and then push into ACR (no rate limit on push). Slower than az acr import
# because the image transits your laptop, but bypasses every shared-IP
# throttling issue.
# ----------------------------------------------------------------------------
mirror_via_docker() {
  local source="$1"
  local target="$2"
  local target_full="$ACR_LOGIN_SERVER/$target"

  echo "→ mirror (docker):  $source"
  echo "          to:        $target_full"

  if ! command -v docker >/dev/null 2>&1; then
    echo "  ✗ docker CLI not available — skipping (image won't be mirrored)"
    FAILED+=("$source (no docker CLI)")
    echo
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "  ✗ docker daemon not reachable — skipping"
    FAILED+=("$source (docker daemon down)")
    echo
    return
  fi

  # Pull, retag, push, clean up. We delete the local images after push to
  # keep the script idempotent and the docker disk usage bounded.
  if docker pull --quiet "$source" >/dev/null \
      && docker tag "$source" "$target_full" \
      && docker push --quiet "$target_full" >/dev/null; then
    docker rmi "$source" "$target_full" >/dev/null 2>&1 || true
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

# Refresh docker credential helper so the fallback path has a valid token.
# Safe to run repeatedly. Silently a no-op if docker isn't installed.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "Logging local docker into ACR (for docker-fallback path)..."
  az acr login --name "$ACR_NAME" --output none
  echo
fi

# ---- ArgoCD ---------------------------------------------------------------
# All argocd-* components use the same image with different commands.
mirror "quay.io/argoproj/argocd:${ARGOCD_VERSION}" \
       "argoproj/argocd:${ARGOCD_VERSION}"

# Redis used by ArgoCD's repo-server cache. Routed through the docker
# fallback path because public.ecr.aws/docker/library/redis is heavily
# rate-limited from ACR's import IP pool, and docker.io/library/redis
# hits the same throttling (same shared IPs, same upstream).
mirror_via_docker "docker.io/library/redis:${ARGOCD_REDIS_VERSION}-alpine" \
                  "library/redis:${ARGOCD_REDIS_VERSION}-alpine"

# ---- Kyverno --------------------------------------------------------------
# Five distinct images, all in ghcr.io/kyverno/.
for img in kyverno kyvernopre background-controller cleanup-controller reports-controller; do
  mirror "ghcr.io/kyverno/${img}:${KYVERNO_VERSION}" \
         "kyverno/${img}:${KYVERNO_VERSION}"
done

# ---- Falco ----------------------------------------------------------------
# Falco core. We use the -no-driver variant because we run with modern-ebpf,
# which compiles the probe at runtime via the kernel's CO-RE support rather
# than needing a pre-built driver image.
mirror "docker.io/falcosecurity/falco-no-driver:${FALCONODRIVER_VERSION}" \
       "falcosecurity/falco-no-driver:${FALCONODRIVER_VERSION}"

# falcoctl — installed by the chart even with artifact install/follow
# disabled, because the rule-validation init container still uses it.
mirror "docker.io/falcosecurity/falcoctl:${FALCOCTL_VERSION}" \
       "falcosecurity/falcoctl:${FALCOCTL_VERSION}"

# Falcosidekick.
mirror "docker.io/falcosecurity/falcosidekick:${FALCOSIDEKICK_VERSION}" \
       "falcosecurity/falcosidekick:${FALCOSIDEKICK_VERSION}"

# Falcosidekick UI.
mirror "docker.io/falcosecurity/falcosidekick-ui:${FALCOSIDEKICK_UI_VERSION}" \
       "falcosecurity/falcosidekick-ui:${FALCOSIDEKICK_UI_VERSION}"

# Falcosidekick UI's Redis backing store. Same throttling issue as
# ArgoCD's Redis — route through docker fallback.
mirror_via_docker "docker.io/library/redis:${FALCOSIDEKICK_UI_REDIS_VERSION}-alpine" \
                  "library/redis:${FALCOSIDEKICK_UI_REDIS_VERSION}-alpine"

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
  echo
  echo "For 429 (TOOMANYREQUESTS) failures on az acr import: switch the"
  echo "offending image to mirror_via_docker(), which pulls via the local"
  echo "docker daemon and bypasses ACR's shared import IP rate limit."
  exit 1
fi
