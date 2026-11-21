import json
import shutil

import pytest

from scripts import render_aks_overlay as r

DIGEST = "sha256:" + "a" * 64
OUTPUTS = {
    "workload_identity_client_id": {"value": "12345678-90ab-cdef-1234-567890abcdef"},
    "tenant_id": {"value": "abcdef01-2345-6789-abcd-ef0123456789"},
    "key_vault_name": {"value": "kv-flagpost-prod-ab12"},
    "acr_login_server": {"value": "acrflagpostprodab12.azurecr.io"},
}
IMAGE = f"acrflagpostprodab12.azurecr.io/flagpost@{DIGEST}"


def test_resolve_accepts_real_values():
    v = r.resolve(OUTPUTS, IMAGE)
    assert v["vault"] == "kv-flagpost-prod-ab12" and v["image"] == IMAGE


@pytest.mark.parametrize(
    ("mutate", "image", "message"),
    [
        (lambda o: o.pop("tenant_id"), IMAGE, "missing"),
        (lambda o: o.update(tenant_id={"value": ""}), IMAGE, "non-empty"),
        (lambda o: o.update(tenant_id={"value": r.PLACEHOLDER_GUID}), IMAGE, "real GUID"),
        (lambda o: None, "acrflagpostprodab12.azurecr.io/flagpost:latest", "pinned by digest"),
        (lambda o: None, f"evil.azurecr.io/flagpost@{DIGEST}", "not the platform ACR"),
    ],
)
def test_resolve_rejects(mutate, image, message):
    outputs = json.loads(json.dumps(OUTPUTS))
    mutate(outputs)
    with pytest.raises(r.RenderError, match=message):
        r.resolve(outputs, image)


@pytest.mark.skipif(shutil.which("kustomize") is None, reason="kustomize not on PATH")
def test_render_fills_every_placeholder():
    out = r.render(r.resolve(OUTPUTS, IMAGE))
    assert r.PLACEHOLDER_GUID not in out
    assert "clientID: 12345678-90ab-cdef-1234-567890abcdef" in out
    assert "keyvaultName: kv-flagpost-prod-ab12" in out
    assert "tenantId: abcdef01-2345-6789-abcd-ef0123456789" in out
    assert f"image: {IMAGE}" in out
    assert "azure.workload.identity/client-id: 12345678-90ab-cdef-1234-567890abcdef" in out


def test_main_usage_and_errors(tmp_path, capsys):
    assert r.main(["x"]) == 2
    bad = tmp_path / "out.json"
    bad.write_text(json.dumps({}))
    assert r.main(["x", str(bad), IMAGE]) == 1
    assert "missing" in capsys.readouterr().err
