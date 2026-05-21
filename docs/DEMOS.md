# Demos

End-to-end exercises that hit each of the four security layers described in the [main README](../README.md#security-controls-by-layer). Replace the ACR hostname placeholder (`<acr>.azurecr.io`) with your shared ACR's login server — check via `terraform -chdir=terraform/shared output acr_login_server`.

## Supply-chain demos

### Reject an unsigned image

Push an unsigned image to ACR (e.g. `docker pull alpine; docker tag alpine <acr>.azurecr.io/sample-api/unsigned:test; docker push ...`). Then:

```bash
kubectl run unsigned-test -n sample-api \
  --image=<acr>.azurecr.io/sample-api/unsigned:test
# Error: admission webhook "...kyverno..." denied the request:
#   ... no matching signatures
```

Kyverno rejects because there's no Cosign signature with the expected workflow identity.

### Reject a vulnerable image (signature passes, attestation fails)

Edit `gitops/sample-api/deployment.yaml` to use `sample-api/vulnerable:main` instead of `sample-api/hardened:main`. Commit. Within ~30 seconds ArgoCD pushes the change; the Deployment's replicaset will create a pod that hits the Kyverno admission hook, which reads the vuln attestation and rejects on `CRITICAL` findings. Revert by going back to the hardened tag.

### Audit-only Pod Security Standards findings

```bash
make kyverno-reports
```

Shows what the baseline Pod Security policies would block if flipped to enforce. The sample-api hardened pod passes; the vulnerable variant violates several baseline checks.

## Defender demos

### Posture finding on a deployed vulnerable image

Deploy the vulnerable image into a namespace *without* the `kyverno-verify-images=enforce` label so Kyverno doesn't block it:

```bash
kubectl create namespace defender-test
kubectl -n defender-test run vuln-test \
  --image=<acr>.azurecr.io/sample-api/vulnerable:main \
  --restart=Never
```

Within a few hours, Defender's agentless K8s discovery picks up the running pod and the recommendation in **Defender for Cloud → Recommendations** flips from "Container images should have vulnerability findings resolved" (image in registry) to "**Running** container images should have vulnerability findings resolved" — same finding, higher priority. Cross-check Defender's per-CVE list against Trivy's output in CI; the disagreements between the two CVE feeds are the interesting part.

### Runtime alert via synthetic test

The canonical end-to-end smoke test for Defender's alert pipeline:

```bash
kubectl get pods --namespace=asc-alerttest-662jfi039n
# Wait 5–15 min. Alert appears in:
#   - Defender for Cloud > Security alerts (portal)
#   - SecurityAlert table in LAW (via continuous export)
```

LAW query — note `StartTime` not `TimeGenerated` (the former matches the portal's "Activity start time"; the latter is just the LAW ingest moment):

```kql
SecurityAlert
| where StartTime > ago(2d)
| project StartTime, AlertName, AlertSeverity, AlertType, Description
| order by StartTime desc
```

### Runtime alert via real syscall pattern

Trigger something Defender's rules catch from inside a pod:

```bash
kubectl -n defender-test exec vuln-test -- \
  wget -qO- "http://169.254.169.254/metadata/instance?api-version=2021-02-01" -H "Metadata: true"
```

Within ~10 min, a Defender alert fires on "Suspicious request to the metadata service detected" or similar.

## Falco demo

### Runtime detection on the same syscall pattern

Falco watches the same syscall stream independently of Defender. With Falco deployed and the Web UI port-forwarded:

```bash
kubectl -n falco port-forward svc/falco-falcosidekick-ui 2802:2802 &
# Browse to http://localhost:2802

# In another terminal, generate something Falco's default rules catch:
kubectl -n sample-api exec deployment/sample-api -- cat /etc/shadow
# Rule "Read sensitive file untrusted" fires immediately.
```

Watching Defender's alert pipeline and Falco's event stream side-by-side on the same triggers is the central demo of layered runtime detection.
