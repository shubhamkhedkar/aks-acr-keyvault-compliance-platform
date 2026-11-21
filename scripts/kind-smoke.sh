#!/usr/bin/env bash
# Rehearse the AKS rollout on a throwaway local kind cluster using the `local` overlay:
# restricted Pod Security admission, probes, PDB/HPA objects, NetworkPolicy objects,
# and the API key mounted at the CSI path. The cluster is deleted afterwards.
# This never talks to Azure or to any non-local cluster.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-flagpost-smoke}"
IMAGE="${IMAGE:-flagpost:local}"
KUBECONFIG="$(mktemp)"
export KUBECONFIG
cd "$ROOT"

cleanup() { kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; rm -f "$KUBECONFIG"; }
trap cleanup EXIT

kind create cluster --name "$CLUSTER" --wait 120s
ctx="kind-${CLUSTER}"
[[ "$(kubectl config current-context)" == "$ctx" ]] || { echo "refusing: context is not $ctx" >&2; exit 1; }
kind load docker-image "$IMAGE" --name "$CLUSTER"

kubectl create namespace flagpost --dry-run=client -o yaml | kubectl apply -f - >/dev/null
key="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n')"
kubectl -n flagpost create secret generic flagpost-api-key --from-literal=flagpost-api-key="$key" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kustomize build deploy/kustomize/overlays/local | kubectl apply -f -
kubectl -n flagpost rollout status deploy/flagpost --timeout=180s

echo "==> restricted PSS rejects a root pod"
if kubectl -n flagpost run psa-probe --image="$IMAGE" --restart=Never --dry-run=server \
     --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' >/dev/null 2>&1; then
  echo "FAIL: restricted Pod Security admission accepted a root pod" >&2; exit 1
fi
echo "ok  root pod rejected by Pod Security admission"

kubectl -n flagpost port-forward svc/flagpost 18080:80 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true; cleanup' EXIT
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:18080/healthz >/dev/null && break; sleep 1; done

curl -sf http://127.0.0.1:18080/readyz | grep -q '"ready"' || { echo "FAIL readyz" >&2; exit 1; }
code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/api/v1/flags)"
[[ "$code" == 401 ]] || { echo "FAIL: unauthenticated call returned $code" >&2; exit 1; }
curl -sf -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
  -d '{"flag":"dark-mode","tenant":"contoso","subject":"u-1"}' http://127.0.0.1:18080/api/v1/evaluate | grep -q '"on":true'
info="$(curl -sf http://127.0.0.1:18080/api/v1/info)"
echo "ok  $info"
kubectl -n flagpost get deploy,po,svc,pdb,hpa,networkpolicy
echo "kind-smoke: passed"
