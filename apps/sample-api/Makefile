.PHONY: help build run stop logs info shell scan clean push

# Default variant. Override with: make build VARIANT=hardened
VARIANT ?= vulnerable

# Image name and full tag
APP        := sample-api
IMAGE      := $(APP):$(VARIANT)
CONTAINER  := $(APP)-$(VARIANT)
PORT       ?= 8000
DOCKERFILE := $(VARIANT)/Dockerfile

# ACR push target (overridden via env or root Makefile when ready)
ACR_LOGIN_SERVER ?=

help:
	@echo "Sample-API targets (override variant with VARIANT=hardened|vulnerable)"
	@echo ""
	@echo "  build        Build the $(VARIANT) image"
	@echo "  run          Run $(VARIANT) container in background on port $(PORT)"
	@echo "  stop         Stop and remove the $(VARIANT) container"
	@echo "  logs         Tail logs from the running container"
	@echo "  info         Curl /info on the running container"
	@echo "  shell        Open a shell in the running container (debug)"
	@echo "  scan         Run Trivy against the $(VARIANT) image"
	@echo "  push         Push the image to ACR (requires ACR_LOGIN_SERVER)"
	@echo "  clean        Remove built images and stopped containers"
	@echo ""
	@echo "  build-all    Build both variants"
	@echo "  scan-all     Scan both variants and save reports to ../../docs/"
	@echo "  compare      Show /info from both variants side by side"
	@echo ""
	@echo "Current settings:"
	@echo "  VARIANT=$(VARIANT)  IMAGE=$(IMAGE)  PORT=$(PORT)"

# ---- Single-variant targets ------------------------------------------------

build:
	docker build -f $(DOCKERFILE) -t $(IMAGE) .

run: stop
	docker run --rm -d -p $(PORT):8000 --name $(CONTAINER) $(IMAGE)
	@echo "Waiting for container to be ready..."
	@for i in 1 2 3 4 5; do \
	  if curl -fs http://localhost:$(PORT)/healthz >/dev/null 2>&1; then \
	    echo "Ready."; break; \
	  fi; sleep 1; \
	done

stop:
	@docker rm -f $(CONTAINER) 2>/dev/null || true

logs:
	docker logs -f $(CONTAINER)

info:
	@curl -fs http://localhost:$(PORT)/info | (jq . 2>/dev/null || cat)

shell:
	docker exec -it $(CONTAINER) sh

scan:
	@command -v trivy >/dev/null 2>&1 || { \
	  echo "Trivy not installed. brew install trivy / winget install AquaSecurity.Trivy"; exit 1; }
	trivy image --severity HIGH,CRITICAL $(IMAGE)

push:
	@if [ -z "$(ACR_LOGIN_SERVER)" ]; then \
	  echo "ACR_LOGIN_SERVER not set. Pass it: make push ACR_LOGIN_SERVER=acrxxxx.azurecr.io"; \
	  exit 1; fi
	docker tag $(IMAGE) $(ACR_LOGIN_SERVER)/$(IMAGE)
	docker push $(ACR_LOGIN_SERVER)/$(IMAGE)

clean: stop
	@docker rmi $(APP):vulnerable 2>/dev/null || true
	@docker rmi $(APP):hardened   2>/dev/null || true

# ---- Both-variant convenience targets --------------------------------------

build-all:
	$(MAKE) build VARIANT=vulnerable
	$(MAKE) build VARIANT=hardened

scan-all:
	@mkdir -p ../../docs
	@command -v trivy >/dev/null 2>&1 || { echo "Trivy not installed."; exit 1; }
	@command -v jq    >/dev/null 2>&1 || { echo "jq not installed."; exit 1; }

	# Human-readable reports for the docs folder
	trivy image $(APP):vulnerable > ../../docs/day-02-trivy-vulnerable.txt 2>&1 || true
	trivy image $(APP):hardened   > ../../docs/day-02-trivy-hardened.txt   2>&1 || true

	# Accurate counts via JSON output
	@echo ""
	@echo "=== HIGH/CRITICAL counts (all) ==="
	@printf "vulnerable: "; \
	  trivy image --severity HIGH,CRITICAL --format json $(APP):vulnerable 2>/dev/null | \
	  jq '[.Results[]?.Vulnerabilities[]?] | length'
	@printf "hardened:   "; \
	  trivy image --severity HIGH,CRITICAL --format json $(APP):hardened   2>/dev/null | \
	  jq '[.Results[]?.Vulnerabilities[]?] | length'

	# What real production policies actually gate on
	@echo ""
	@echo "=== HIGH/CRITICAL counts (fixable only — what production gates on) ==="
	@printf "vulnerable: "; \
	  trivy image --severity HIGH,CRITICAL --ignore-unfixed --format json $(APP):vulnerable 2>/dev/null | \
	  jq '[.Results[]?.Vulnerabilities[]?] | length'
	@printf "hardened:   "; \
	  trivy image --severity HIGH,CRITICAL --ignore-unfixed --format json $(APP):hardened   2>/dev/null | \
	  jq '[.Results[]?.Vulnerabilities[]?] | length'

compare:
	@echo "=== Vulnerable variant ==="
	@$(MAKE) -s stop VARIANT=vulnerable
	@$(MAKE) -s run  VARIANT=vulnerable PORT=8001 >/dev/null
	@curl -fs http://localhost:8001/info | (jq . 2>/dev/null || cat)
	@$(MAKE) -s stop VARIANT=vulnerable
	@echo ""
	@echo "=== Hardened variant ==="
	@$(MAKE) -s stop VARIANT=hardened
	@$(MAKE) -s run  VARIANT=hardened  PORT=8002 >/dev/null
	@curl -fs http://localhost:8002/info | (jq . 2>/dev/null || cat)
	@$(MAKE) -s stop VARIANT=hardened
