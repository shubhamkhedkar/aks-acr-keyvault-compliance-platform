"""HTTP API for Flagpost.

Configuration (environment variables):
  FLAGPOST_SEED_FILE        Git-managed JSON flag file (ConfigMap mount on AKS), hot-reloaded
  FLAGPOST_SECRETS_DIR      directory where the Key Vault CSI driver mounts secrets
  FLAGPOST_API_KEY_SECRET   file name of the client API key inside FLAGPOST_SECRETS_DIR
  FLAGPOST_ENVIRONMENT      label echoed by /api/v1/info (local, aks-prod, ...)

Flags are read-only over HTTP: changes go through Git and the pipeline, so every
replica serves the same answer. Callers authenticate with a bearer API key that
lives in Key Vault and reaches the pod through the Secrets Store CSI driver.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
import uuid

from flask import Flask, Response, g, jsonify, request

from . import __version__
from .metrics import Metrics
from .rules import TENANT_PATTERN, evaluate
from .secrets import MountedSecret
from .store import FlagStore

MAX_BODY_BYTES = 16 * 1024
SUBJECT_MAX = 128


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + "Z",
            "level": record.levelname.lower(),
            "msg": record.getMessage(),
            "logger": record.name,
        }
        for key in ("request_id", "method", "route", "status", "duration_ms"):
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        return json.dumps(payload, separators=(",", ":"))


def _logger() -> logging.Logger:
    log = logging.getLogger("flagpost")
    if not log.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        log.addHandler(handler)
        log.setLevel(os.environ.get("FLAGPOST_LOG_LEVEL", "INFO").upper())
        log.propagate = False
    return log


def _error(status: int, message: str) -> tuple[Response, int]:
    return jsonify({"error": message, "request_id": g.get("request_id")}), status


def create_app(
    store: FlagStore | None = None,
    api_key: MountedSecret | None = None,
    environment: str | None = None,
) -> Flask:
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = MAX_BODY_BYTES
    log = _logger()

    if store is None:
        store = FlagStore.from_file(os.environ.get("FLAGPOST_SEED_FILE"))
    if api_key is None:
        api_key = MountedSecret(
            os.environ.get("FLAGPOST_SECRETS_DIR", "/mnt/secrets-store"),
            os.environ.get("FLAGPOST_API_KEY_SECRET", "flagpost-api-key"),
        )
    environment = environment or os.environ.get("FLAGPOST_ENVIRONMENT", "local")
    metrics = Metrics()
    app.extensions["flagpost"] = {"store": store, "metrics": metrics, "secret": api_key}

    @app.before_request
    def _start() -> None:
        g.start = time.perf_counter()
        store.reload_if_changed()
        incoming = request.headers.get("X-Request-ID", "")
        g.request_id = incoming if 0 < len(incoming) <= 64 and incoming.isprintable() else uuid.uuid4().hex

    @app.after_request
    def _finish(response: Response) -> Response:
        route = request.url_rule.rule if request.url_rule else "unmatched"
        elapsed = time.perf_counter() - g.get("start", time.perf_counter())
        metrics.observe_request(request.method, route, response.status_code, elapsed)
        response.headers["X-Request-ID"] = g.get("request_id", "")
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
        response.headers["Cache-Control"] = "no-store"
        if route not in ("/healthz", "/readyz", "/metrics"):
            log.info(
                "request",
                extra={
                    "request_id": g.get("request_id"),
                    "method": request.method,
                    "route": route,
                    "status": response.status_code,
                    "duration_ms": round(elapsed * 1000, 2),
                },
            )
        return response

    def _require_client() -> tuple[Response, int] | None:
        header = request.headers.get("Authorization", "")
        token = header[7:] if header.startswith("Bearer ") else None
        if not api_key.available():
            return _error(503, "API key is not mounted; refusing to serve unauthenticated")
        if not api_key.matches(token):
            return _error(401, "missing or invalid bearer token")
        return None

    @app.errorhandler(404)
    def _not_found(_e):  # type: ignore[no-untyped-def]
        return _error(404, "not found")

    @app.errorhandler(405)
    def _method(_e):  # type: ignore[no-untyped-def]
        return _error(405, "method not allowed")

    @app.errorhandler(413)
    def _too_large(_e):  # type: ignore[no-untyped-def]
        return _error(413, f"body larger than {MAX_BODY_BYTES} bytes")

    @app.get("/healthz")
    def healthz():  # type: ignore[no-untyped-def]
        return jsonify({"status": "ok"})

    @app.get("/readyz")
    def readyz():  # type: ignore[no-untyped-def]
        checks = {"store": store.loaded, "api_key": api_key.available()}
        ready = all(checks.values())
        return jsonify({"status": "ready" if ready else "not-ready", "checks": checks}), (200 if ready else 503)

    @app.get("/metrics")
    def prometheus():  # type: ignore[no-untyped-def]
        body = metrics.render(len(store), store.reloads, store.reload_errors)
        return Response(body, mimetype="text/plain; version=0.0.4")

    @app.get("/api/v1/info")
    def info():  # type: ignore[no-untyped-def]
        return jsonify({"service": "flagpost", "version": __version__, "environment": environment})

    @app.get("/api/v1/flags")
    def list_flags():  # type: ignore[no-untyped-def]
        denied = _require_client()
        if denied:
            return denied
        return jsonify({"flags": [f.to_dict() for f in store.list()]})

    @app.get("/api/v1/flags/<key>")
    def get_flag(key: str):  # type: ignore[no-untyped-def]
        denied = _require_client()
        if denied:
            return denied
        flag = store.get(key)
        if flag is None:
            return _error(404, f"flag {key!r} not found")
        return jsonify(flag.to_dict())

    @app.post("/api/v1/evaluate")
    def evaluate_flag():  # type: ignore[no-untyped-def]
        denied = _require_client()
        if denied:
            return denied
        doc = request.get_json(silent=True)
        if not isinstance(doc, dict):
            return _error(400, "body must be a JSON object")
        key, tenant, subject = doc.get("flag"), doc.get("tenant"), doc.get("subject")
        if not isinstance(key, str) or not isinstance(tenant, str) or not isinstance(subject, str):
            return _error(400, "flag, tenant and subject are required strings")
        if not TENANT_PATTERN.match(tenant) or not 0 < len(subject) <= SUBJECT_MAX:
            return _error(400, "tenant or subject is malformed")
        flag = store.get(key)
        if flag is None:
            return _error(404, f"flag {key!r} not found")
        on, reason = evaluate(flag, tenant, subject)
        metrics.observe_evaluation(flag.key, on)
        return jsonify({"flag": flag.key, "on": on, "reason": reason})

    return app
