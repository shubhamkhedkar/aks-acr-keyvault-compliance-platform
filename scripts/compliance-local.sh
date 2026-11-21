#!/usr/bin/env bash
# Run the two InSpec (Cinc Auditor) profiles that need no Azure account:
#   1. k8s-manifests  against the rendered Kustomize output (prod + local overlays)
#   2. container-image against a locally running, hardened Flagpost container
# Also runs `check` on the azure-platform profile (vendored into a temp dir).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
AUDITOR="${AUDITOR_IMAGE:-cincproject/auditor:7.3.4}"
IMAGE="${IMAGE:-flagpost:local}"
NAME="flagpost-inspec-$$"
cd "$ROOT"

run_auditor() { "$DOCKER" run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT/compliance:/share/compliance:ro" -v "$ROOT/build:/share/build:ro" -w /share "$@"; }

./scripts/render-manifests.sh >/dev/null

echo "==> inspec check (all profiles)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; "$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
cp -r compliance/azure-platform "$tmp/"
as_me=(-u "$(id -u):$(id -g)" -e HOME=/tmp)
"$DOCKER" run --rm "${as_me[@]}" -v "$tmp/azure-platform:/p" -w /p "$AUDITOR" vendor . --overwrite --chef-license accept-silent >/dev/null
"$DOCKER" run --rm "${as_me[@]}" -v "$tmp/azure-platform:/p" -w /p "$AUDITOR" check . --chef-license accept-silent
for p in k8s-manifests container-image; do
  run_auditor "$AUDITOR" check "compliance/$p" --chef-license accept-silent
done

echo "==> k8s-manifests: production render"
run_auditor "$AUDITOR" exec compliance/k8s-manifests --chef-license accept-silent --no-distinct-exit \
  --reporter json-min --input manifest_file=/share/build/aks-prod.yaml expect_csi=true | python3 scripts/inspec_summary.py
echo "==> k8s-manifests: local render (CSI/ACR controls skipped)"
run_auditor "$AUDITOR" exec compliance/k8s-manifests --chef-license accept-silent --no-distinct-exit \
  --reporter json-min --input manifest_file=/share/build/local.yaml expect_csi=false | python3 scripts/inspec_summary.py

echo "==> container-image against a running $IMAGE"
./scripts/local-secrets.sh >/dev/null
"$DOCKER" run -d --name "$NAME" --read-only --tmpfs /tmp:rw,size=64m --cap-drop ALL \
  --security-opt no-new-privileges -v "$ROOT/.local/secrets-store:/mnt/secrets-store:ro" "$IMAGE" >/dev/null
for _ in $(seq 1 30); do
  "$DOCKER" exec "$NAME" python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/healthz',timeout=1)" 2>/dev/null && break
  sleep 1
done
"$DOCKER" run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$ROOT/compliance:/share/compliance:ro" -w /share \
  "$AUDITOR" exec compliance/container-image -t "docker://$NAME" --chef-license accept-silent --no-distinct-exit \
  --reporter json-min | python3 scripts/inspec_summary.py
echo "compliance-local: all profiles passed"
