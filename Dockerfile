# syntax=docker/dockerfile:1
# Flagpost runtime image: multi-stage, pinned by digest, non-root, read-only friendly.
# Base image pinned by digest (python:3.13-slim, Debian). Bump tag + digest together.
FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-compile -r requirements.txt \
    && /opt/venv/bin/pip uninstall -y pip
COPY app/src/ /opt/app/
RUN /opt/venv/bin/python -m compileall -q /opt/app

FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS runtime
ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.title="flagpost" \
      org.opencontainers.image.description="Feature-flag service for the AKS + ACR + Key Vault platform" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.source="https://github.com/shubhamkhedkar/aks-acr-keyvault-compliance-platform" \
      org.opencontainers.image.licenses="MIT"
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/app \
    PORT=8080 \
    FLAGPOST_SEED_FILE=/etc/flagpost/flags.json \
    FLAGPOST_SECRETS_DIR=/mnt/secrets-store
# Pick up Debian security fixes newer than the base digest, then strip all package tooling:
# the runtime needs neither apt caches nor pip (whose vendored urllib3/msgpack scanners flag).
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 flagpost \
    && useradd --system --uid 10001 --gid flagpost --no-create-home --shell /usr/sbin/nologin flagpost \
    && rm -rf /usr/local/lib/python3.13/ensurepip /usr/local/lib/python3.13/site-packages/pip \
              /usr/local/lib/python3.13/site-packages/pip-*.dist-info /usr/local/bin/pip* /root/.cache
COPY --from=build /opt/venv /opt/venv
COPY --from=build /opt/app /opt/app
COPY app/seed/flags.json /etc/flagpost/flags.json
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]
ENTRYPOINT ["gunicorn", "--config", "python:flagpost.gunicorn_conf", "flagpost.wsgi:app"]
