"""Gunicorn settings tuned for a read-only, non-root container on AKS."""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"
# One process per pod keeps /metrics and hot-reload state coherent; scale out with replicas (HPA).
workers = int(os.environ.get("GUNICORN_WORKERS", "1"))
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
worker_class = "gthread"
# Private in-memory emptyDir (or tmpfs under compose); the root filesystem stays read-only.
worker_tmp_dir = "/tmp"  # noqa: S108
timeout = 30
graceful_timeout = 25  # below terminationGracePeriodSeconds so in-flight requests drain
keepalive = 5
accesslog = None  # the app writes structured JSON request logs itself
errorlog = "-"
loglevel = "info"
forwarded_allow_ips = "*"
limit_request_line = 4094
limit_request_fields = 50
