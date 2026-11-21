#!/usr/bin/env bash
# Generate the Flagpost client API key and store it in Key Vault, so the value never
# appears in Terraform state, pipeline logs or Git. Run from a machine with private
# line of sight to the vault (the vault has no public endpoint).
# DRY RUN by default; --execute performs the write with your existing az login.
#
#   scripts/seed-keyvault-secret.sh [--execute] <key-vault-name>
set -euo pipefail

EXECUTE=false
if [[ "${1:-}" == "--execute" ]]; then EXECUTE=true; shift; fi
VAULT="${1:?usage: $0 [--execute] <key-vault-name>}"
NAME="flagpost-api-key"
EXPIRES="$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ)"

if ! $EXECUTE; then
  echo "# dry run - would run:"
  echo "+ az keyvault secret set --vault-name $VAULT --name $NAME --value <48 random chars> --expires $EXPIRES --content-type text/plain"
  exit 0
fi
value="$(head -c 36 /dev/urandom | base64 | tr -d '/+=\n')"
az keyvault secret set --vault-name "$VAULT" --name "$NAME" --file /dev/stdin --expires "$EXPIRES" \
  --content-type text/plain --output none <<<"$value"
unset value
echo "stored $NAME in $VAULT (expires $EXPIRES); pods pick it up within the 2m CSI rotation interval"
