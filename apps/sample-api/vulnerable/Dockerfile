# vulnerable/Dockerfile
# DELIBERATELY INSECURE
# This image is the "before" half of the lab story:
#   - Outdated base image (CVEs in OS packages and Python runtime)
#   - Runs as root (Kyverno will reject)
#   - No multi-stage (build tools end up in final image, larger attack surface)
#   - No HEALTHCHECK
#   - Old pinned dependencies (CVEs in Python packages, Trivy will flag)
FROM python:3.9-slim

WORKDIR /app

# Build deps left in the final image (anti-pattern, expanded attack surface)
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.vulnerable.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000

# Runs as root (UID 0) - default in python:3.9-slim, no USER directive added.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]