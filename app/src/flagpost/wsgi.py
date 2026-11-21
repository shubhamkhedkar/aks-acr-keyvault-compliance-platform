"""Gunicorn entry point: ``gunicorn flagpost.wsgi:app``."""

from .app import create_app

app = create_app()
