#!/usr/bin/env bash
# One-time creation of the Terraform remote-state backend (storage account + container).
# DRY RUN by default: prints the az commands. Pass --execute to run them against the
# subscription you are already logged in to (az login is up to you; this script never logs in).
#
#   scripts/bootstrap-tfstate.sh [--execute] [location] [suffix]
set -euo pipefail

EXECUTE=false
if [[ "${1:-}" == "--execute" ]]; then EXECUTE=true; shift; fi
LOCATION="${1:-centralindia}"
SUFFIX="${2:-sk07}"
RG="rg-flagpost-tfstate"
SA="stflagposttfstate${SUFFIX}"
CONTAINER="tfstate"

[[ "$SA" =~ ^[a-z0-9]{3,24}$ ]] || { echo "storage account name '$SA' is invalid (3-24 lowercase alphanumerics)" >&2; exit 1; }

run() {
  printf '+ %s\n' "$*"
  if $EXECUTE; then "$@"; fi
}

$EXECUTE || echo "# dry run - nothing is created. Re-run with --execute to apply."
run az group create --name "$RG" --location "$LOCATION" --tags workload=flagpost purpose=terraform-state
run az storage account create --name "$SA" --resource-group "$RG" --location "$LOCATION" \
  --sku Standard_ZRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false \
  --https-only true --default-action Allow
run az storage account blob-service-properties update --account-name "$SA" --resource-group "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30
run az storage container create --name "$CONTAINER" --account-name "$SA" --auth-mode login
run az lock create --name lock-tfstate --resource-group "$RG" --lock-type CanNotDelete \
  --notes "Terraform state for the flagpost platform"
cat <<MSG

# Next: grant the pipeline's service-connection identity "Storage Blob Data Contributor" on $SA,
# then copy terraform/environments/prod/backend.hcl.example to backend.hcl with:
#   storage_account_name = "$SA"
MSG
