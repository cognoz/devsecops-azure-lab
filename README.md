# DevSecOps Azure Lab

End-to-end supply-chain security lab on Azure Kubernetes Service. Demonstrates a complete container delivery loop where every step has an enforced security control: build → scan → sign → attest → push → GitOps deploy → admission-verify.

## Architecture

```
┌───────────────────┐        ┌──────────────────────┐        ┌───────────────────────┐
│ GitHub Actions    │        │ Azure Container      │        │ Azure Kubernetes      │
│  (federated OIDC) │        │ Registry             │        │ Service (AAD-only)    │
│                   │        │                      │        │                       │
│  - Buildx         │ push   │  sample-api/         │ pull   │  - ArgoCD             │
│  - Trivy gate     ├───────►│   vulnerable:<sha>   ├───────►│  - Kyverno            │
│  - SBOM (Syft)    │  cosign│   hardened:<sha>     │ kubelet│  - kyverno-policies   │
│  - Cosign sign    │        │   .sig / .att refs   │   IDs  │  - sample-api         │
│  - Cosign attest  │        │                      │        │                       │
│    (sbom + vuln)  │        │  argoproj/argocd:v3  │        │                       │
└────────┬──────────┘        │  kyverno/*:v1.18     │        └──────────┬────────────┘
         │                   └──────────┬───────────┘                   │
         │                              │                               │
         │ public Sigstore              │                               │ ArgoCD pulls
         │ (Fulcio + Rekor)             │                               │ from GitHub
         ▼                              ▼                               ▼
   tlog.sigstore.dev          (signatures stored as           github.com/cognoz/
                              OCI artifact referrers)         devsecops-azure-lab
                                                              gitops/
```

## Key components

| Component | Role |
|---|---|
| **Terraform (shared)** | Long-lived: ACR, Key Vault for persistent secrets, shared RG. Survives cluster destroy/rebuild. |
| **Terraform (cluster)** | Daily-cycle: AKS, log analytics, OIDC federated identity for GitHub Actions, ArgoCD install (Helm). |
| **GitHub Actions** | CI: build, Trivy gate, SBOM + vuln attestation, keyless Cosign sign, ACR push. |
| **ArgoCD** | GitOps controller. App-of-apps pattern syncs everything else from `gitops/` in this repo. |
| **Kyverno** | Admission controller. Verifies image signatures and vuln attestations at pod admission. |
| **kyverno-policies** | Upstream Pod Security Standards (baseline profile, audit mode). |
| **Trivy** | CI gate on fixable HIGH/CRITICAL CVEs. Also emits vuln attestations consumed by Kyverno. |
| **Cosign + Sigstore** | Keyless signing via GitHub OIDC. Fulcio issues short-lived certs; Rekor stores transparency entries. |

## Repo layout

```
.
├── .github/
│   ├── workflows/
│   │   ├── main-workflow.yml       Build/scan/sign/attest/push pipeline
│   │   └── smoke-test-oidc.yml     OIDC federation sanity check
│   └── dependabot.yml              Auto-PRs for actions/terraform/pip/docker
├── apps/sample-api/                Two-variant FastAPI demo app
│   ├── vulnerable/Dockerfile       Intentionally bad (python:3.9, root, old deps)
│   └── hardened/Dockerfile         Multi-stage, slim, non-root, healthchecked
├── terraform/
│   ├── shared/                     Long-lived (ACR, KV-shared, RG)
│   └── cluster/                    Daily-cycle (AKS, KV-lab, ArgoCD bootstrap)
├── gitops/                         Everything ArgoCD syncs (NOT bootstrapped by Terraform)
│   ├── apps/                       ArgoCD Applications (one per workload)
│   │   ├── kyverno.yaml
│   │   ├── kyverno-policies.yaml
│   │   ├── lab-policies.yaml
│   │   └── sample-api.yaml
│   ├── policies/                   Custom Kyverno ClusterPolicy CRs
│   │   ├── verify-image-signatures.yaml
│   │   └── disallow-high-cve-images.yaml
│   └── sample-api/                 K8s manifests for the demo workload
├── scripts/
│   ├── bootstrap-state.sh          One-shot: create the tfstate storage account
│   └── mirror-images.sh            az acr import for third-party charts
└── Makefile                        Everyday operations
```

## Two state files, on purpose

- **shared.tfstate** — ACR, shared Key Vault (persistent secrets, GitHub App for ArgoCD), shared RG. `terraform destroy` here is destructive and rare.
- **lab.tfstate** — AKS, cluster KV (ephemeral), monitoring, OIDC federated identity, ArgoCD install. Designed to be destroyed and recreated daily.

This split exists because AKS is expensive to leave running but ACR's image history and KV's secrets must persist. `make destroy` only touches lab state.

## Identity & auth

- **GitHub Actions → Azure**: federated OIDC. No client secrets stored anywhere. SP gets `AcrPush` on ACR + AKS RBAC Writer on the cluster.
- **AKS cluster auth**: AAD-only (`local_account_disabled = true`). Local admin kubeconfig disabled by design. All kubectl access goes through `kubelogin` and AAD tokens.
- **ArgoCD → GitHub repo**: GitHub App (App ID + installation ID + PEM), credentials stored in shared KV, read by Terraform at apply time and planted as an ArgoCD repo Secret in the cluster. ArgoCD itself never reaches into Azure.
- **AKS → ACR**: Managed Identity. The kubelet identity has `AcrPull` on shared ACR; no imagePullSecrets needed.

## What gets verified at admission

`gitops/policies/verify-image-signatures.yaml` — Kyverno reaches out to public Sigstore and checks that every image from `acrdevsecopsrk964.azurecr.io/*` has a Cosign signature whose certificate's subject matches `https://github.com/cognoz/devsecops-azure-lab/.github/workflows/main-workflow.yml@refs/heads/*` issued by GitHub Actions OIDC. Signatures that don't match the expected workflow identity = rejection.

`gitops/policies/disallow-high-cve-images.yaml` — Same admission check, but evaluates the **Trivy vulnerability attestation** attached to the image. If the attestation reports any `CRITICAL` vulnerability with a fix available, the pod is rejected.

Both policies are **enforce-only in namespaces labelled `kyverno-verify-images=enforce`**; they audit everywhere else. This keeps system pods (which won't carry signatures) running while the lab workload is held to the strict rule.

`gitops/apps/kyverno-policies.yaml` — Upstream Pod Security Standards at the `baseline` profile, all in audit mode. Provides PolicyReport telemetry without yet enforcing.

## Setup

### One-time

1. **State backend.** `./scripts/bootstrap-state.sh` creates the Storage Account that holds `shared.tfstate` and `lab.tfstate`. Edit the script first to make the storage account name unique.
2. **Apply shared.** `make shared-init && make shared-apply`. Creates ACR, the persistent KV, and the shared RG.
3. **GitHub App for ArgoCD.** Create one at https://github.com/settings/apps/new with:
   - Permissions: Contents: Read-only, Metadata: Read-only.
   - Where can this be installed: Only on this account.
   - Webhook: disabled.
   - Install on this repo only after creation, then download the private key (.pem).
   - Capture App ID, Installation ID, PEM contents.
4. **Stash the GitHub App creds in shared KV** (replace placeholders, then run):
   ```bash
   KV=kv-shared-devsecops-rk964
   az keyvault secret set --vault-name "$KV" --name argocd-github-app-id              --value "<APP_ID>"
   az keyvault secret set --vault-name "$KV" --name argocd-github-app-installation-id --value "<INSTALL_ID>"
   az keyvault secret set --vault-name "$KV" --name argocd-github-app-private-key     --file  "<path-to.pem>"
   ```
5. **Mirror third-party images into ACR.** `make mirror-images`. Run again whenever you bump ArgoCD or Kyverno versions.
6. **Install kubelogin locally** (Terraform talks to AKS via kubelogin):
   ```bash
   az aks install-cli
   # or: brew install Azure/kubelogin/kubelogin
   ```

### Daily cycle

```bash
make init                # terraform init for cluster/
make apply               # build everything: AKS, ArgoCD, OIDC federation, etc.
make sync-github-vars    # push fresh AZURE_*/ACR_*/AKS_* into the GitHub repo
make kubeconfig          # az aks get-credentials with kubelogin-aware kubeconfig

# At this point ArgoCD is running and self-syncing from gitops/.
# Within ~2 minutes, Kyverno, kyverno-policies, lab-policies, and sample-api
# are all installed and healthy.

make argocd-apps         # confirm everything is Synced + Healthy
make kyverno-policies    # see the active ClusterPolicy resources
make argocd-ui &         # port-forward UI; password via `make argocd-password`
```

When done for the day:

```bash
make destroy             # tears down AKS + cluster KV + ArgoCD; ACR + shared KV intact
```

## Demos

**Reject an unsigned image.** Push an unsigned image to ACR (e.g. `docker pull alpine; docker tag alpine acrdevsecopsrk964.azurecr.io/sample-api/unsigned:test; docker push ...`). Then:

```bash
kubectl run unsigned-test -n sample-api \
  --image=acrdevsecopsrk964.azurecr.io/sample-api/unsigned:test
# Error: admission webhook "...kyverno..." denied the request:
#   ... no matching signatures
```

**Reject a vulnerable image (passes signature, fails attestation).** Edit `gitops/sample-api/deployment.yaml` to use `sample-api/vulnerable:main` instead of `sample-api/hardened:main`. Commit. Within 30 seconds ArgoCD pushes the change; the Deployment's replicaset will create a pod that hits the Kyverno admission hook, which reads the vuln attestation and rejects on `CRITICAL` findings. Replace by reverting to the hardened tag.

**Audit-only PSS findings.** `make kyverno-reports` shows what the baseline Pod Security policies would block if flipped to enforce.

## Operational notes

- **`local_account_disabled = true`** — there is no `kube-admin` config. All access is AAD. `kubelogin` is required for kubectl/Terraform; use `kubelogin convert-kubeconfig -l azurecli` after `get-credentials`. The `smoke-test-oidc.yml` workflow installs kubelogin in CI; do the same on your laptop.
- **Spot user node pool.** All workloads tolerate `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` and run on cheap evictable nodes. The system pool is single-node non-spot for ArgoCD/Kyverno reliability.
- **purge_protection on shared KV is `true`** — irreversible. The vault and its secrets cannot be permanently deleted for 7 days even after `terraform destroy`. That's by design; the GitHub App key is meant to outlive lab cycles.

## Known limitations

- **Hardcoded `acrdevsecopsrk964.azurecr.io`** in `gitops/apps/kyverno.yaml` and the two custom Kyverno policies. Pure GitOps trades templating for determinism; if the shared `lab_name` or naming suffix changes, update these three places.
- **Dependabot does not track Helm chart versions** referenced from ArgoCD Application manifests. Bump `gitops/apps/*.yaml` chart versions manually (and `scripts/mirror-images.sh` versions to match).
- **Single ArgoCD admin** — no SSO. Dex is disabled. Acceptable for a lab; production would wire Azure AD via OIDC at the ArgoCD server.
- **Public Rekor latency / availability is a runtime dependency** of every Kyverno admission decision. Sigstore is generally reliable but it's a third-party SPOF for cluster operations.

## Lab variants

- `vulnerable/Dockerfile` — python:3.9-slim, root, old deps. Trivy CI gate rejects.
- `hardened/Dockerfile` — python:3.12-slim multi-stage, UID 10001, pinned current deps. Trivy CI gate passes; gets signed + attested.

The CI pipeline runs both variants in matrix. The hardened image makes it to ACR; the vulnerable image fails at the Trivy gate and never gets pushed (so even if you forget the Kyverno policy, the supply chain has two independent gates).
