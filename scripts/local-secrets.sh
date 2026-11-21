#!/usr/bin/env bash
# Create a throwaway API key where the Key Vault CSI driver would mount it.
# The directory is git-ignored; nothing here is a real credential.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$ROOT/.local/secrets-store"
mkdir -p "$dir"
chmod 0755 "$ROOT/.local" "$dir"
if [[ ! -s "$dir/flagpost-api-key" ]]; then
  umask 022
  head -c 32 /dev/urandom | base64 | tr -d '/+=\n' >"$dir/flagpost-api-key"
  echo "generated $dir/flagpost-api-key"
else
  echo "reusing $dir/flagpost-api-key"
fi
