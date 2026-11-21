import json
import logging
import os
import shutil

from flagpost.app import JsonFormatter, create_app
from flagpost.secrets import MountedSecret
from flagpost.store import FlagStore


def test_health_ready_info_need_no_auth(client):
    assert client.get("/healthz").json == {"status": "ok"}
    ready = client.get("/readyz")
    assert ready.status_code == 200 and ready.json["checks"] == {"store": True, "api_key": True}
    assert client.get("/api/v1/info").json == {"service": "flagpost", "version": "1.0.0", "environment": "test"}


def test_not_ready_and_fail_closed_without_secret(app, secrets_dir, auth):
    (secrets_dir / "flagpost-api-key").unlink()
    c = app.test_client()
    assert c.get("/readyz").status_code == 503
    assert c.get("/api/v1/flags", headers=auth).status_code == 503


def test_security_headers_and_request_id(client, auth):
    resp = client.get("/api/v1/flags", headers={"X-Request-ID": "abc-123", **auth})
    assert resp.headers["X-Request-ID"] == "abc-123"
    assert resp.headers["X-Content-Type-Options"] == "nosniff"
    assert resp.headers["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in resp.headers["Content-Security-Policy"]
    assert resp.headers["Cache-Control"] == "no-store"
    generated = client.get("/healthz", headers={"X-Request-ID": "x" * 100}).headers["X-Request-ID"]
    assert len(generated) == 32


def test_api_requires_bearer_key(client):
    assert client.get("/api/v1/flags").status_code == 401
    assert client.get("/api/v1/flags", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/api/v1/flags/dark-mode", headers={"Authorization": "Basic abc"}).status_code == 401
    body = {"flag": "dark-mode", "tenant": "t", "subject": "u"}
    assert client.post("/api/v1/evaluate", json=body).status_code == 401


def test_list_and_get(client, auth):
    keys = [f["key"] for f in client.get("/api/v1/flags", headers=auth).json["flags"]]
    assert keys == ["bulk-export", "checkout-v2", "dark-mode"]
    assert client.get("/api/v1/flags/dark-mode", headers=auth).json["rollout_percent"] == 100
    missing = client.get("/api/v1/flags/nope", headers=auth)
    assert missing.status_code == 404 and "request_id" in missing.json


def test_flags_are_read_only_over_http(client, auth):
    assert client.put("/api/v1/flags/dark-mode", json={}, headers=auth).status_code == 405
    assert client.delete("/api/v1/flags/dark-mode", headers=auth).status_code == 405


def test_evaluate(client, auth):
    def ev(flag, tenant):
        return client.post("/api/v1/evaluate", json={"flag": flag, "tenant": tenant, "subject": "u1"}, headers=auth)

    assert ev("checkout-v2", "contoso").json == {"flag": "checkout-v2", "on": True, "reason": "tenant-allowed"}
    assert ev("checkout-v2", "fabrikam").json["reason"] == "tenant-denied"
    assert ev("bulk-export", "contoso").json["on"] is False


def test_evaluate_bad_requests(client, auth):
    post = client.post
    assert post("/api/v1/evaluate", data="nope", content_type="text/plain", headers=auth).status_code == 400
    assert post("/api/v1/evaluate", json={"flag": "dark-mode"}, headers=auth).status_code == 400
    bad = post("/api/v1/evaluate", json={"flag": "dark-mode", "tenant": "bad tenant", "subject": "u"}, headers=auth)
    assert bad.status_code == 400
    missing = post("/api/v1/evaluate", json={"flag": "nope", "tenant": "t", "subject": "u"}, headers=auth)
    assert missing.status_code == 404


def test_errors_are_json(client, auth):
    assert client.post("/healthz").status_code == 405
    big = client.post("/api/v1/evaluate", data="x" * 20000, content_type="application/json", headers=auth)
    assert big.status_code == 413 and "error" in big.json


def test_metrics_exposition(client, auth):
    client.post("/api/v1/evaluate", json={"flag": "dark-mode", "tenant": "t", "subject": "u"}, headers=auth)
    text = client.get("/metrics").get_data(as_text=True)
    assert 'flagpost_evaluations_total{flag="dark-mode",result="true"} 1' in text
    assert "flagpost_flags 3" in text
    assert "flagpost_seed_reload_errors_total 0" in text
    assert 'flagpost_http_request_duration_seconds_bucket{le="+Inf"}' in text
    assert 'route="/api/v1/evaluate",status="200"' in text


def test_flag_file_change_is_served_without_restart(tmp_path, secrets_dir, auth):
    seed = tmp_path / "flags.json"
    shutil.copy("app/seed/flags.json", seed)
    app = create_app(FlagStore.from_file(seed), MountedSecret(secrets_dir, "flagpost-api-key"), "test")
    c = app.test_client()
    data = json.loads(seed.read_text())
    data["bulk-export"]["enabled"] = True
    data["bulk-export"]["rollout_percent"] = 100
    seed.write_text(json.dumps(data))
    st = os.stat(seed)
    os.utime(seed, (st.st_atime, st.st_mtime + 5))
    resp = c.post("/api/v1/evaluate", json={"flag": "bulk-export", "tenant": "t", "subject": "u"}, headers=auth)
    assert resp.json["on"] is True
    assert "flagpost_seed_reloads_total 1" in c.get("/metrics").get_data(as_text=True)


def test_create_app_from_environment(monkeypatch, tmp_path):
    (tmp_path / "key").write_text("z" * 40)
    monkeypatch.setenv("FLAGPOST_SEED_FILE", "app/seed/flags.json")
    monkeypatch.setenv("FLAGPOST_SECRETS_DIR", str(tmp_path))
    monkeypatch.setenv("FLAGPOST_API_KEY_SECRET", "key")
    monkeypatch.setenv("FLAGPOST_ENVIRONMENT", "aks-prod")
    client = create_app().test_client()
    assert client.get("/api/v1/info").json["environment"] == "aks-prod"
    assert client.get("/readyz").status_code == 200
    assert client.get("/api/v1/flags", headers={"Authorization": "Bearer " + "z" * 40}).status_code == 200


def test_json_formatter_includes_extras():
    record = logging.LogRecord("flagpost", logging.INFO, __file__, 1, "request", None, None)
    record.request_id = "r1"
    record.status = 200
    out = json.loads(JsonFormatter().format(record))
    assert out["msg"] == "request" and out["request_id"] == "r1" and out["status"] == 200
