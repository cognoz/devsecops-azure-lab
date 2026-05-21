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
│  - Cosign attest  │        │                      │        │  - Falco (eBPF DS)    │
│    (sbom + vuln)  │        │  argoproj/argocd:v3  │        │  - Defender sensor    │
└────────┬──────────┘        │  kyverno/*:v1.18     │        │                       │
         │                   │  falcosecurity/*     │        └──────────┬────────────┘
         │                   └──────────┬───────────┘                   │
         │ public Sigstore              │                               │
         │ (Fulcio + Rekor)             │                               │
         ▼                              ▼                               │
   tlog.sigstore.dev          (signatures stored as                     │
                              OCI artifact referrers)                   │
                                                                        │
   Runtime + posture lane (Microsoft Defender for Cloud)                │
   ┌─────────────────────────────────────────────────┐                  │
   │ Defender for Containers (subscription plan)     │◄─────────────────┤
   │   - Agentless ACR vuln scan (parallel to Trivy) │                  │
   │   - Agentless K8s discovery                     │                  │
   │   - Per-node sensor → runtime alerts            │                  │
   │   - ContinuousExport "ExportToWorkspace"        │──┐               │
   └─────────────────────────────────────────────────┘  │               │
                                                        │               │
   Self-owned runtime detection lane                    │               │
   ┌─────────────────────────────────────────────────┐  │               │
   │ Falco + Falcosidekick                           │  │ alerts        │
   │   - modern-eBPF syscall watching                │  │ assessments   │
   │   - Custom rules in Git                         │  │ subassess     │
   │   - Falcosidekick fan-out (UI for the lab)      │  │               │
   └────────────┬────────────────────────────────────┘  │               │
                │ (LAW pipe via Logic App / OTel — WIP) │               │
                ▼                                       ▼               │
                       Azure Log Analytics workspace ◄──────────────────┘
                       (SecurityAlert, SecurityRecommendation,
                        SecurityNestedRecommendation tables)
```

## Key components

| Component | Role |
|---|---|
| **Terraform (shared)** | Long-lived: ACR, Key Vault for persistent secrets, shared RG, subscription budget, Defender for Containers plan + continuous export. Survives cluster destroy/rebuild. |
| **Terraform (cluster)** | Daily-cycle: AKS, log analytics + Security solution, OIDC federated identity for GitHub Actions, ArgoCD install (Helm), cluster-side Defender sensor opt-in. |
| **GitHub Actions** | CI: build, Trivy gate, SBOM + vuln attestation, keyless Cosign sign, ACR push. |
| **ArgoCD** | GitOps controller. App-of-apps pattern syncs everything else from `gitops/` in this repo. |
| **Kyverno** | Admission controller. Verifies image signatures and vuln attestations at pod admission. |
| **kyverno-policies** | Upstream Pod Security Standards (baseline profile, audit mode). |
| **Trivy** | CI gate on fixable HIGH/CRITICAL CVEs. Also emits vuln attestations consumed by Kyverno. |
| **Cosign + Sigstore** | Keyless signing via GitHub OIDC. Fulcio issues short-lived certs; Rekor stores transparency entries. |
| **Microsoft Defender for Containers** | Agentless ACR vuln scanning (parallel signal to Trivy), agentless K8s posture discovery, per-node sensor for runtime threat detection. Findings exported to LAW via continuous export. |
| **Falco + Falcosidekick** | Self-owned runtime detection via modern-eBPF. Rules versioned in Git. Falcosidekick fans events out to the Web UI (lab) and onward sinks (LAW pipe in progress). |

## Repo layout

```
.
├── .github/workflows/        Build/scan/sign/attest/push pipeline + OIDC smoke test
├── apps/sample-api/          Two-variant FastAPI demo (vulnerable + hardened)
├── terraform/
│   ├── shared/               Long-lived: ACR, KV-shared, RG, budget, Defender plan
│   └── cluster/              Daily-cycle: AKS, KV-lab, LAW, ArgoCD bootstrap
├── gitops/                   Everything ArgoCD syncs (NOT bootstrapped by Terraform)
│   ├── apps/                 ArgoCD Application per workload (Kyverno, Falco, sample-api, ...)
│   ├── policies/             Custom Kyverno ClusterPolicy CRs
│   └── sample-api/           K8s manifests for the demo workload
├── scripts/                  bootstrap-state.sh, mirror-images.sh
└── Makefile                  Everyday operations
```

## Two state files, on purpose

- **shared.tfstate** — ACR, shared Key Vault (persistent secrets, GitHub App for ArgoCD), shared RG, subscription budget, Defender for Containers plan + continuous export. `terraform destroy` here is destructive and rare.
- **lab.tfstate** — AKS, cluster KV (ephemeral), monitoring (LAW + Security solution), OIDC federated identity, ArgoCD install, cluster-side Defender sensor opt-in. Designed to be destroyed and recreated daily.

This split exists because AKS is expensive to leave running but ACR's image history, KV's secrets, and Defender's alert/recommendation history must persist. `make destroy` only touches lab state.

## Identity & auth

- **GitHub Actions → Azure**: federated OIDC. No client secrets stored anywhere. SP gets `AcrPush` on ACR + AKS RBAC Writer on the cluster.
- **AKS cluster auth**: AAD-only (`local_account_disabled = true`). Local admin kubeconfig disabled by design. All kubectl access goes through `kubelogin` and AAD tokens.
- **ArgoCD → GitHub repo**: GitHub App (App ID + installation ID + PEM), credentials stored in shared KV, read by Terraform at apply time and planted as an ArgoCD repo Secret in the cluster. ArgoCD itself never reaches into Azure.
- **AKS → ACR**: Managed Identity. The kubelet identity has `AcrPull` on shared ACR; no imagePullSecrets needed.

## Security controls, by layer

The lab demonstrates four independent layers of supply-chain and runtime control. Each has a different response window.

### 1. Build-time gate — Trivy in CI

CI fails the build if Trivy finds fixable HIGH/CRITICAL CVEs. The vulnerable image variant never reaches ACR. Trivy also produces a vuln attestation (in-toto/SPDX) attached to the hardened image as an OCI referrer, which Kyverno reads at admission.

### 2. Admission gate — Kyverno

`gitops/policies/verify-image-signatures.yaml` — Kyverno reaches out to public Sigstore and checks that every image from the lab ACR has a Cosign signature whose certificate's subject matches `https://github.com/cognoz/devsecops-azure-lab/.github/workflows/main-workflow.yml@refs/heads/*` issued by GitHub Actions OIDC. Signatures that don't match the expected workflow identity = rejection.

`gitops/policies/disallow-high-cve-images.yaml` — Same admission check, but evaluates the **Trivy vulnerability attestation** attached to the image. If the attestation reports any `CRITICAL` vulnerability with a fix available, the pod is rejected.

Both policies are **enforce-only in namespaces labelled `kyverno-verify-images=enforce`**; they audit everywhere else. This keeps system pods (which won't carry signatures) running while the lab workload is held to the strict rule.

`gitops/apps/kyverno-policies.yaml` — Upstream Pod Security Standards at the `baseline` profile, all in audit mode. Provides PolicyReport telemetry without yet enforcing.

### 3. Posture monitoring — Microsoft Defender for Containers

Subscription plan in `terraform/shared/defender.tf` with four extensions:

- `ContainerRegistriesVulnerabilityAssessments` — agentless scan of every image pushed to ACR, using Microsoft's curated CVE feed. **Independent of Trivy** — when the two disagree, that's the useful signal (different vuln databases, different rules about what "fixable" means).
- `AgentlessDiscoveryForKubernetes` — API-based discovery of cluster posture. Powers queries like "running pods with critical CVEs" with no agent.
- `AgentlessVmScanning` — node OS disk vuln + secret scanning.
- `ContainerSensor` — the per-node Defender DaemonSet for runtime threat detection (eBPF, similar territory to Falco).

Continuous export resource named `ExportToWorkspace` ships alerts, assessments, and sub-assessments into the cluster LAW. The `OMSGallery/Security` solution on the LAW creates the `SecurityAlert` / `SecurityRecommendation` / `SecurityNestedRecommendation` tables — without it, exported events would silently land nowhere.

### 4. Runtime detection — Falco + Falcosidekick

`gitops/apps/falco.yaml` installs Falco as a per-node DaemonSet with the modern-eBPF driver (no kernel module, no driver-loader pod). Rules ship via the chart's `customRules` map and are versioned in Git — `falcoctl` artifact-install and follow are disabled so rule changes flow only through commits.

Falcosidekick is enabled as a subchart and forwards events to its Web UI (lab-only) and ultimately to LAW (Logic App / OTel wiring is the next milestone).

Defender's `ContainerSensor` and Falco overlap considerably — both eBPF, both per-node, both syscall-based. Running both is intentional: comparing detection coverage between an opaque Microsoft ruleset and an open ruleset you own is the central pedagogical demo. In production you'd typically pick one.

### Why all four

Trivy is build-time, deterministic, blocks the artifact. Kyverno is admission-time, deterministic, blocks the pod. Defender is continuous, probabilistic, raises alerts. Falco is continuous, deterministic by rule, raises events. Different windows, different signals — the whole point of the lab is making the distinctions concrete and queryable side-by-side.

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
# Within ~2 minutes, Kyverno, kyverno-policies, lab-policies, Falco, and
# sample-api are all installed and healthy. The Defender sensor DaemonSet
# (microsoft-defender-* in kube-system) comes up automatically because the
# AKS cluster has the microsoft_defender block enabled.

make argocd-apps         # confirm everything is Synced + Healthy
make kyverno-policies    # see the active ClusterPolicy resources
make argocd-ui &         # port-forward UI; password via `make argocd-password`
```

When done for the day:

```bash
make destroy             # tears down AKS + cluster KV + ArgoCD; ACR + shared KV intact
```

## Demos

End-to-end exercises hitting each of the four layers — supply chain (Kyverno rejects unsigned + vulnerable images), posture (Defender flags running vulnerable image), Defender runtime alerts (synthetic + real syscall), and Falco runtime detection. See [`docs/DEMOS.md`](docs/DEMOS.md).

## Operational notes

- **`local_account_disabled = true`** — there is no `kube-admin` config. All access is AAD. `kubelogin` is required for kubectl/Terraform; use `kubelogin convert-kubeconfig -l azurecli` after `get-credentials`. The `smoke-test-oidc.yml` workflow installs kubelogin in CI; do the same on your laptop.
- **Spot user node pool.** All workloads tolerate `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` and run on cheap evictable nodes. The system pool is single-node non-spot for ArgoCD/Kyverno reliability.
- **purge_protection on shared KV is `true`** — irreversible. The vault and its secrets cannot be permanently deleted for 7 days even after `terraform destroy`. That's by design; the GitHub App key is meant to outlive lab cycles.
- **Defender continuous export does not backfill.** Alerts that fire before the `OMSGallery/Security` solution exists on the LAW are lost to KQL forever. Apply the solution before relying on `SecurityAlert` queries. If the table is missing entirely, you're querying before any alert has populated it yet — it's created lazily on first ingest.
- **`SecurityAlert.TimeGenerated` ≠ alert time.** `TimeGenerated` is the LAW ingest timestamp; `StartTime` is when Defender raised the alert. Use `StartTime` to align with the portal's "Activity start time."
- **Defender sensor and Falco coexist.** Both run as per-node eBPF DaemonSets and watch syscalls independently. They don't interfere at the kernel level. Resource cost on the spot pool is small (~100-200m CPU per node combined). In production you'd typically pick one.
- **Falco's default rules are noisy on AKS.** `ama-logs`, `azure-policy`, `microsoft-defender-*`, CSI drivers, and ArgoCD's repo-server all trip the upstream ruleset on startup or routinely. Add suppression macros to the `customRules` map in `gitops/apps/falco.yaml` rather than disabling rules wholesale.

## Known limitations

- **Hardcoded ACR name** in `gitops/apps/kyverno.yaml`, `gitops/apps/falco.yaml`, and the two custom Kyverno policies. Pure GitOps trades templating for determinism; if the shared `lab_name` or naming suffix changes, update these four places.
- **Dependabot does not track Helm chart versions** referenced from ArgoCD Application manifests. Bump `gitops/apps/*.yaml` chart versions manually (and `scripts/mirror-images.sh` versions to match).
- **Single ArgoCD admin** — no SSO. Dex is disabled. Acceptable for a lab; production would wire Azure AD via OIDC at the ArgoCD server.
- **Public Rekor latency / availability is a runtime dependency** of every Kyverno admission decision. Sigstore is generally reliable but it's a third-party SPOF for cluster operations.
- **Falco → LAW pipe is incomplete.** Falcosidekick has no native Log Analytics output. Events currently land in the Falcosidekick Web UI only. The intended path is Falcosidekick HTTP webhook → Logic App → LAW Data Collector API (or a small Azure Function in Terraform), so Falco events can be queried alongside `SecurityAlert` in KQL. Tracked separately.
- **Defender continuous export uses the legacy OMS solution model** (`azurerm_log_analytics_solution` for `OMSGallery/Security`). Microsoft has been signalling a slow migration toward Data Collection Rules and Sentinel onboarding. Still supported and current for non-Sentinel workspaces; if Sentinel is enabled on the LAW later, it takes over and this solution can be removed.

## Lab variants

- `vulnerable/Dockerfile` — python:3.9-slim, root, old deps. Trivy CI gate rejects.
- `hardened/Dockerfile` — python:3.12-slim multi-stage, UID 10001, pinned current deps. Trivy CI gate passes; gets signed + attested.

The CI pipeline runs both variants in matrix. The hardened image makes it to ACR; the vulnerable image fails at the Trivy gate and never gets pushed (so even if you forget the Kyverno policy, the supply chain has two independent gates).
