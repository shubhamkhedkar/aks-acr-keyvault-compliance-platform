#!/usr/bin/env bash
# End-to-end smoke test of the compose stack on 127.0.0.1:8080. Cleans up after itself.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
BASE="http://127.0.0.1:8080"
cd "$ROOT"

./scripts/local-secrets.sh >/dev/null
TOKEN="$(cat .local/secrets-store/flagpost-api-key)"
trap '"$DOCKER" compose down -v >/dev/null 2>&1 || true' EXIT
"$DOCKER" compose up -d --build --wait >/dev/null

fail() { echo "FAIL: $*" >&2; exit 1; }
expect() { # expect <status> <method> <path> [body] [auth]
  local want="$1" method="$2" path="$3" body="${4:-}" auth="${5:-}"
  local args=(-s -o /tmp/flagpost-body -w '%{http_code}' -X "$method" "$BASE$path")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  [[ -n "$auth" ]] && args+=(-H "Authorization: Bearer $auth")
  local got
  got="$(curl "${args[@]}")"
  [[ "$got" == "$want" ]] || fail "$method $path -> $got (want $want): $(cat /tmp/flagpost-body)"
  echo "ok  $method $path -> $got"
}

expect 200 GET /healthz
expect 200 GET /readyz
expect 401 GET /api/v1/flags
expect 200 GET /api/v1/flags "" "$TOKEN"
expect 405 PUT /api/v1/flags/dark-mode '{"enabled":false}' "$TOKEN"
expect 200 POST /api/v1/evaluate '{"flag":"checkout-v2","tenant":"contoso","subject":"u-1"}' "$TOKEN"
grep -q '"reason":"tenant-allowed"' /tmp/flagpost-body || fail "contoso should be on the allow list"
expect 200 POST /api/v1/evaluate '{"flag":"checkout-v2","tenant":"fabrikam","subject":"u-1"}' "$TOKEN"
grep -q '"reason":"tenant-denied"' /tmp/flagpost-body || fail "fabrikam should be denied"
curl -s "$BASE/metrics" | grep -q 'flagpost_evaluations_total{flag="checkout-v2",result="true"} 1' || fail "metrics missing evaluation"
echo "ok  /metrics exposes evaluation counter"

# Runtime hardening as seen by Docker
cid="$("$DOCKER" compose ps -q flagpost)"
[[ "$("$DOCKER" inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$cid")" == "true" ]] || fail "root fs not read-only"
[[ "$("$DOCKER" inspect -f '{{.Config.User}}' "$cid")" == "10001:10001" ]] || fail "not running as 10001"
if "$DOCKER" exec "$cid" sh -c 'touch /opt/app/x' 2>/dev/null; then fail "app dir writable"; fi
echo "ok  read-only rootfs, uid 10001, code not writable"

# Secret rotation: rewrite the mounted key (what the CSI driver does) and the old one stops working.
NEW="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n')"
printf '%s' "$NEW" >.local/secrets-store/flagpost-api-key
sleep 1
expect 401 GET /api/v1/flags "" "$TOKEN"
expect 200 GET /api/v1/flags "" "$NEW"
echo "ok  rotated key is picked up without a restart"
echo "compose-smoke: passed"
