#!/usr/bin/env bash
# Every offline quality gate. Nothing here talks to Azure, pushes images or deploys.
# Docker-based rehearsals (compose, InSpec against a container, kind) are in `make smoke-all`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p build/reports
step() { printf '\n==> %s\n' "$1"; }

step "Python unit tests + coverage gate (pytest)"
pytest --junitxml=build/reports/pytest.xml

step "Python lint/format (ruff)"
ruff check app scripts tests
ruff format --check app scripts tests

step "Dependency audit (pip-audit, runtime requirements)"
pip-audit --strict --progress-spinner off -r app/requirements.txt

step "ShellCheck"
shellcheck scripts/*.sh

step "Dockerfile lint (hadolint)"
hadolint Dockerfile

step "YAML lint"
yamllint -s .

step "Kustomize render + kubeconform (incl. SecretProviderClass CRD schema)"
./scripts/render-manifests.sh
kubeconform -strict -summary -kubernetes-version 1.34.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  build/aks-prod.yaml build/local.yaml

step "Terraform fmt / validate / tflint / mocked tests"
terraform fmt -recursive -check terraform
(
  cd terraform/environments/prod
  terraform init -backend=false -input=false >/dev/null
  terraform validate
  tflint --config "$ROOT/.tflint.hcl" --init >/dev/null
  tflint --config "$ROOT/.tflint.hcl" --format compact
  for m in ../../modules/*/; do (cd "$m" && tflint --config "$ROOT/.tflint.hcl" --format compact); done
  terraform test
)

step "Checkov (Terraform, Dockerfile, rendered Kubernetes)"
checkov -d terraform --framework terraform --quiet --compact
checkov -f Dockerfile --framework dockerfile --quiet --compact
checkov -f build/aks-prod.yaml --framework kubernetes --quiet --compact

step "Secret scan (gitleaks: git history + working tree)"
if git rev-parse --verify HEAD >/dev/null 2>&1; then gitleaks git --no-banner --redact .; fi
gitleaks dir --no-banner --redact .

echo
echo "All offline checks passed."
