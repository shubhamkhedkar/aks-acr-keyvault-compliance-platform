.PHONY: help tools check test image scan up down smoke compliance kind-smoke smoke-all tf-test render clean

DOCKER ?= docker
export DOCKER
IMAGE ?= flagpost:local

help:            ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

tools:           ## install pinned, checksum-verified CLIs into .local/tools/bin
	./scripts/install-ci-tools.sh .local/tools

check:           ## every offline gate: tests, lint, audit, kubeconform, terraform, tflint, checkov, gitleaks
	./scripts/check-all.sh

test:            ## Python unit + repo policy tests
	pytest

image:           ## build the hardened runtime image
	$(DOCKER) build --build-arg GIT_COMMIT=$$(git rev-parse HEAD 2>/dev/null || echo unknown) -t $(IMAGE) .

scan: image      ## Trivy: fail on fixable HIGH/CRITICAL in the image
	trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE)

up:              ## run Flagpost on 127.0.0.1:8080 with a throwaway API key
	./scripts/local-secrets.sh
	$(DOCKER) compose up -d --build --wait

down:            ## stop the local stack
	$(DOCKER) compose down -v

smoke:           ## compose end-to-end: auth, evaluation, metrics, read-only FS, key rotation
	./scripts/compose-smoke.sh

compliance: image ## InSpec: rendered-manifest baseline + running-container baseline + profile checks
	IMAGE=$(IMAGE) ./scripts/compliance-local.sh

kind-smoke: image ## rehearse the rollout on a throwaway kind cluster (restricted PSS)
	IMAGE=$(IMAGE) ./scripts/kind-smoke.sh

smoke-all: smoke compliance kind-smoke ## every Docker-based rehearsal

tf-test:         ## terraform validate + mocked plan tests (no Azure calls)
	cd terraform/environments/prod && terraform init -backend=false -input=false >/dev/null && terraform validate && terraform test

render:          ## render both Kustomize overlays into build/
	./scripts/render-manifests.sh

clean:           ## remove generated output
	rm -rf build .local .pytest_cache .ruff_cache .coverage
