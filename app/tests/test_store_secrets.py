import json
import os
import shutil

import pytest

from flagpost.rules import ValidationError
from flagpost.secrets import MountedSecret
from flagpost.store import FlagStore


def _bump(path, seconds=5):
    st = os.stat(path)
    os.utime(path, (st.st_atime, st.st_mtime + seconds))


def test_store_seed_and_lookup():
    store = FlagStore.from_file("app/seed/flags.json")
    assert store.loaded and len(store) == 3
    assert [f.key for f in store.list()] == ["bulk-export", "checkout-v2", "dark-mode"]
    assert store.get("dark-mode").rollout_percent == 100
    assert store.get("missing") is None
    assert store.reload_if_changed() is False  # unchanged file


def test_store_without_seed_is_empty_but_loaded():
    store = FlagStore.from_file(None)
    assert store.loaded and len(store) == 0
    assert store.reload_if_changed() is False


def test_store_rejects_non_object_seed_at_startup(tmp_path):
    seed = tmp_path / "seed.json"
    seed.write_text(json.dumps(["not", "a", "map"]))
    with pytest.raises(ValidationError):
        FlagStore.from_file(seed)


def test_hot_reload_picks_up_git_change(tmp_path):
    seed = tmp_path / "flags.json"
    shutil.copy("app/seed/flags.json", seed)
    store = FlagStore.from_file(seed)
    data = json.loads(seed.read_text())
    data["new-flag"] = {"enabled": True, "rollout_percent": 50}
    seed.write_text(json.dumps(data))
    _bump(seed)
    assert store.reload_if_changed() is True
    assert store.get("new-flag").rollout_percent == 50
    assert store.reloads == 1


def test_bad_reload_keeps_last_good_flags(tmp_path):
    seed = tmp_path / "flags.json"
    shutil.copy("app/seed/flags.json", seed)
    store = FlagStore.from_file(seed)
    seed.write_text('{"Broken Key": {}}')
    _bump(seed)
    assert store.reload_if_changed() is False
    assert len(store) == 3 and store.reload_errors == 1
    seed.write_text("{not json")
    _bump(seed, 10)
    assert store.reload_if_changed() is False
    assert store.reload_errors == 2
    assert store.reload_if_changed() is False  # same bad mtime is not retried


def test_reload_tolerates_missing_file(tmp_path):
    seed = tmp_path / "flags.json"
    shutil.copy("app/seed/flags.json", seed)
    store = FlagStore.from_file(seed)
    seed.unlink()
    assert store.reload_if_changed() is False
    assert len(store) == 3


def test_mounted_secret_missing(tmp_path):
    secret = MountedSecret(tmp_path, "absent")
    assert secret.value() is None
    assert not secret.available()
    assert not secret.matches("x" * 40)


def test_mounted_secret_rotation_is_picked_up(tmp_path):
    path = tmp_path / "token"
    path.write_text("a" * 40)
    secret = MountedSecret(tmp_path, "token")
    assert secret.matches("a" * 40)
    path.write_text("b" * 40)
    _bump(path)  # the CSI driver rewrites the file on rotation
    assert not secret.matches("a" * 40)
    assert secret.matches("b" * 40)
    path.unlink()
    assert secret.value() is None


def test_short_or_empty_secret_is_not_usable(tmp_path):
    (tmp_path / "token").write_text("short")
    assert not MountedSecret(tmp_path, "token").available()
    assert not MountedSecret(tmp_path, "token").matches("short")
    (tmp_path / "empty").write_text("  \n")
    assert MountedSecret(tmp_path, "empty").value() is None
