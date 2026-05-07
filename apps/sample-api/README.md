# sample-api

Tiny FastAPI service used as the demo target for the DevSecOps lab.

The application code is identical between two image variants. Only the
`Dockerfile` and the pinned `requirements.txt` differ. The point of the lab
is to show the supply-chain pipeline rejects one and accepts the other.

## Variants

### `vulnerable/Dockerfile`

Deliberately bad. Used to demonstrate the pipeline's rejection paths.

| Issue | What catches it |
|---|---|
| Outdated `python:3.9-slim` base (OS CVEs) | Trivy image scan |
| Old pinned deps with known CVEs | Trivy image scan |
| Runs as UID 0 (root) | Kyverno admission policy |
| No `HEALTHCHECK` | `dockerfile-lint` / Trivy config scan |
| Build tools left in final image | Trivy image scan (larger CVE surface) |

### `hardened/Dockerfile`

Same app, security-hardened. Used to demonstrate the "good" path.

- Multi-stage build, runtime image has no compilers.
- `python:3.12-slim` base, current pinned dependencies.
- Non-root user (`app`, UID 10001) with no shell.
- `HEALTHCHECK` defined.
- Read-only-root-filesystem-friendly (no writes to `/app` at runtime).

## Local build & run

```bash
# vulnerable
docker build -f vulnerable/Dockerfile -t sample-api:vulnerable .
docker run --rm -p 8000:8000 sample-api:vulnerable

# hardened
docker build -f hardened/Dockerfile -t sample-api:hardened .
docker run --rm -p 8000:8000 sample-api:hardened

# Endpoints
curl http://localhost:8000/         # service info
curl http://localhost:8000/healthz  # liveness
curl http://localhost:8000/info     # shows runtime versions and UID
```

The `/info` endpoint is the easy way to confirm which image is actually
running - the hardened one will return `"user_uid": 10001`, the vulnerable
one will return `"user_uid": 0`.

## Local Trivy preview (optional, before CI exists)

```bash
trivy image sample-api:vulnerable
trivy image sample-api:hardened
```

You should see a *much* shorter report on the hardened image. That diff
is the story the Day-4 pipeline will tell automatically.