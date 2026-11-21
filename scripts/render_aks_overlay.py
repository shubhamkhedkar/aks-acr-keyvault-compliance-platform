#!/usr/bin/env python3
"""Render deploy/kustomize/overlays/aks-prod with real values and print the YAML.

Inputs come from `terraform output -json` (workload identity client ID, Key Vault
name, tenant ID, ACR login server) and the image reference the pipeline pushed,
which must be pinned by digest. The overlay in Git keeps placeholder values; this
script fills them in a temporary copy, so the repository never changes.

Usage: render_aks_overlay.py <terraform-outputs.json> <acr>/flagpost@sha256:<digest>
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLACEHOLDER_GUID = "00000000-0000-0000-0000-000000000000"
PLACEHOLDER_VAULT = "kv-flagpost-prod-sk07"
GUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
IMAGE = re.compile(r"^(?P<server>[a-z0-9]+\.azurecr\.io)/flagpost@sha256:[0-9a-f]{64}$")


class RenderError(ValueError):
    pass


def _value(outputs: dict, name: str) -> str:
    try:
        value = outputs[name]["value"]
    except (KeyError, TypeError) as exc:
        raise RenderError(f"terraform output {name!r} is missing") from exc
    if not isinstance(value, str) or not value:
        raise RenderError(f"terraform output {name!r} must be a non-empty string")
    return value


def resolve(outputs: dict, image_ref: str) -> dict[str, str]:
    client_id = _value(outputs, "workload_identity_client_id")
    tenant_id = _value(outputs, "tenant_id")
    vault = _value(outputs, "key_vault_name")
    acr = _value(outputs, "acr_login_server")
    for label, guid in (("workload_identity_client_id", client_id), ("tenant_id", tenant_id)):
        if not GUID.match(guid) or guid == PLACEHOLDER_GUID:
            raise RenderError(f"{label} must be a real GUID")
    match = IMAGE.match(image_ref)
    if not match:
        raise RenderError("image must be <acr>.azurecr.io/flagpost@sha256:<64 hex> (pinned by digest)")
    if match.group("server") != acr:
        raise RenderError(f"image registry {match.group('server')} is not the platform ACR {acr}")
    return {"client_id": client_id, "tenant_id": tenant_id, "vault": vault, "image": image_ref}


def render(values: dict[str, str], kustomize: str = "kustomize") -> str:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "kustomize"
        shutil.copytree(ROOT / "deploy" / "kustomize", work)
        overlay = work / "overlays" / "aks-prod"
        spc = overlay / "secretproviderclass.yaml"
        text = spc.read_text()
        text = text.replace(f'clientID: "{PLACEHOLDER_GUID}"', f'clientID: "{values["client_id"]}"')
        text = text.replace(f'tenantId: "{PLACEHOLDER_GUID}"', f'tenantId: "{values["tenant_id"]}"')
        text = text.replace(f'keyvaultName: "{PLACEHOLDER_VAULT}"', f'keyvaultName: "{values["vault"]}"')
        spc.write_text(text)
        sa = overlay / "serviceaccount-patch.yaml"
        sa.write_text(sa.read_text().replace(PLACEHOLDER_GUID, values["client_id"]))
        subprocess.run([kustomize, "edit", "set", "image", f"flagpost={values['image']}"], cwd=overlay, check=True)
        out = subprocess.run([kustomize, "build", str(overlay)], check=True, capture_output=True, text=True).stdout
    if PLACEHOLDER_GUID in out:
        raise RenderError("a placeholder GUID survived rendering")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        outputs = json.loads(Path(argv[1]).read_text())
        sys.stdout.write(render(resolve(outputs, argv[2])))
    except RenderError as exc:
        print(f"render_aks_overlay: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
