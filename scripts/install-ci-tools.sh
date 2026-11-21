#!/usr/bin/env bash
# Install the pinned CLI toolchain into <prefix>/bin, verifying every download against the
# checksum file published with the release. Used by the Validate stage on hosted agents;
# also works on a workstation (Linux x86_64).
#   scripts/install-ci-tools.sh <prefix>
set -euo pipefail
PREFIX="${1:?usage: $0 <prefix>}"
BIN="$PREFIX/bin"
mkdir -p "$BIN"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

TERRAFORM=1.17.2
TFLINT=0.66.0
KUSTOMIZE=5.4.3
KUBECONFORM=0.8.0
HADOLINT=2.12.0
GITLEAKS=8.30.1
TRIVY=0.76.2

fetch() { curl -sSfL --retry 3 -o "$tmp/$2" "$1"; }
verify() { # verify <file> <checksums-file>
  (cd "$tmp" && grep -E "[ *]$1\$" "$2" | sha256sum -c --status) || { echo "checksum mismatch for $1" >&2; exit 1; }
}
unzip_to_bin() { python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); z.extractall(sys.argv[2], [m for m in z.namelist() if not m.endswith(('.txt', '.md'))])" "$1" "$BIN"; }

f=terraform_${TERRAFORM}_linux_amd64.zip
fetch "https://releases.hashicorp.com/terraform/${TERRAFORM}/$f" "$f"
fetch "https://releases.hashicorp.com/terraform/${TERRAFORM}/terraform_${TERRAFORM}_SHA256SUMS" tf.sums
verify "$f" tf.sums && unzip_to_bin "$tmp/$f"

f=tflint_linux_amd64.zip
fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT}/$f" "$f"
fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT}/checksums.txt" tflint.sums
verify "$f" tflint.sums && unzip_to_bin "$tmp/$f"

f=kustomize_v${KUSTOMIZE}_linux_amd64.tar.gz
fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE}/$f" "$f"
fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE}/checksums.txt" kz.sums
verify "$f" kz.sums && tar -xzf "$tmp/$f" -C "$BIN" kustomize

f=kubeconform-linux-amd64.tar.gz
fetch "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM}/$f" "$f"
fetch "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM}/CHECKSUMS" kc.sums
verify "$f" kc.sums && tar -xzf "$tmp/$f" -C "$BIN" kubeconform

f=hadolint-Linux-x86_64
fetch "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT}/$f" "$f"
fetch "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT}/$f.sha256" hl.sums
verify "$f" hl.sums && install -m 0755 "$tmp/$f" "$BIN/hadolint"

f=gitleaks_${GITLEAKS}_linux_x64.tar.gz
fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS}/$f" "$f"
fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS}/gitleaks_${GITLEAKS}_checksums.txt" gl.sums
verify "$f" gl.sums && tar -xzf "$tmp/$f" -C "$BIN" gitleaks

f=trivy_${TRIVY}_Linux-64bit.tar.gz
fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY}/$f" "$f"
fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY}/trivy_${TRIVY}_checksums.txt" tv.sums
verify "$f" tv.sums && tar -xzf "$tmp/$f" -C "$BIN" trivy

chmod 0755 "$BIN"/*
"$BIN/terraform" version | head -1
echo "installed into $BIN:"; find "$BIN" -maxdepth 1 -type f -printf '  %f\n'
