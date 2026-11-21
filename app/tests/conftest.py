import pytest

from flagpost.app import create_app
from flagpost.secrets import MountedSecret
from flagpost.store import FlagStore

TOKEN = "t" * 40


@pytest.fixture
def secrets_dir(tmp_path):
    d = tmp_path / "secrets-store"
    d.mkdir()
    (d / "flagpost-api-key").write_text(TOKEN + "\n")
    return d


@pytest.fixture
def app(secrets_dir):
    store = FlagStore.from_file("app/seed/flags.json")
    application = create_app(store, MountedSecret(secrets_dir, "flagpost-api-key"), "test")
    application.config["TESTING"] = True
    return application


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def auth():
    return {"Authorization": f"Bearer {TOKEN}"}
