#!/usr/bin/env bash
# Render the Kustomize overlays into build/ without touching a cluster.
# Usage: scripts/render-manifests.sh [image-ref]
#   image-ref defaults to a placeholder ACR reference pinned by a dummy digest so the
#   production render has the same shape the pipeline produces after `docker push`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/build}"
DUMMY_DIGEST="sha256:$(printf 'flagpost-render' | sha256sum | cut -d' ' -f1)"
IMAGE_REF="${1:-acrflagpostprodsk07.azurecr.io/flagpost@${DUMMY_DIGEST}}"

mkdir -p "$OUT"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$ROOT/deploy/kustomize" "$work/"

(cd "$work/kustomize/overlays/aks-prod" && kustomize edit set image "flagpost=${IMAGE_REF}")
kustomize build "$work/kustomize/overlays/aks-prod" >"$OUT/aks-prod.yaml"
kustomize build "$work/kustomize/overlays/local" >"$OUT/local.yaml"
echo "rendered: $OUT/aks-prod.yaml (image ${IMAGE_REF}), $OUT/local.yaml"
