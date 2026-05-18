# hardened/Dockerfile
# Counterpart to vulnerable/Dockerfile - identical app behavior, security tightened.
# Improvements:
#   - Multi-stage: build tools live in builder, final image only has runtime.
#   - Slim base image, current Python.
#   - Non-root user with explicit UID/GID (Kyverno-friendly).
#   - HEALTHCHECK so liveness/readiness can be observed at the container level.
#   - Current pinned deps.

# ----- stage 1: build -----------------------------------------------------
FROM python:3.14-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc && \
        apt-get upgrade -y --no-install-recommends \
           libcap2 \
           libsystemd0 \
           libudev1 \
           && rm -rf /var/lib/apt/lists/*

COPY requirements.hardened.txt requirements.txt

# Install into a virtual env we copy into the runtime image.
RUN python -m venv /venv && \
    /venv/bin/pip install --no-cache-dir --upgrade pip && \
    /venv/bin/pip install --no-cache-dir -r requirements.txt


# ----- stage 2: runtime ---------------------------------------------------
FROM python:3.14-slim AS runtime

# Non-root user. Explicit UID is what Kyverno's "no UID 0" policy looks at.
RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid app --no-create-home --shell /sbin/nologin app

WORKDIR /app

# Copy only the venv from the builder - no compilers in final image.
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH"

COPY --chown=app:app app ./app

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; \
        sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
