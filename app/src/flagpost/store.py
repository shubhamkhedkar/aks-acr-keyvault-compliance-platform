"""Flag store backed by a JSON file that is managed in Git.

On AKS the file is a ConfigMap mount, so flag changes go through a pull request and
the delivery pipeline. The store re-reads the file when its mtime changes; a broken
file is rejected and the last good set of flags keeps serving.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from pathlib import Path

from .rules import Flag, ValidationError, parse_flag

log = logging.getLogger("flagpost")


def load_flags(path: str | Path) -> dict[str, Flag]:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValidationError("seed file must be an object keyed by flag key")
    return {key: parse_flag(key, doc) for key, doc in raw.items()}


class FlagStore:
    def __init__(self, path: str | Path | None = None) -> None:
        self._lock = threading.RLock()
        self._path = Path(path) if path else None
        self._mtime: float | None = None
        self._flags: dict[str, Flag] = {}
        self.loaded = False
        self.reloads = 0
        self.reload_errors = 0

    @classmethod
    def from_file(cls, path: str | Path | None) -> FlagStore:
        store = cls(path)
        if store._path is not None:
            store._flags = load_flags(store._path)  # fail fast at start-up
            store._mtime = os.stat(store._path).st_mtime
        store.loaded = True
        return store

    def reload_if_changed(self) -> bool:
        """Re-read the seed file if it changed. Returns True when new flags were loaded."""
        if self._path is None:
            return False
        try:
            mtime = os.stat(self._path).st_mtime
        except FileNotFoundError:
            return False
        if mtime == self._mtime:
            return False
        with self._lock:
            if mtime == self._mtime:
                return False
            try:
                flags = load_flags(self._path)
            except (ValueError, OSError) as exc:  # json.JSONDecodeError and ValidationError are ValueErrors
                self._mtime = mtime
                self.reload_errors += 1
                log.error("seed-reload-rejected: %s", exc)
                return False
            self._flags, self._mtime = flags, mtime
            self.reloads += 1
            log.info("seed-reloaded: %d flags", len(flags))
            return True

    def list(self) -> list[Flag]:
        with self._lock:
            return [self._flags[k] for k in sorted(self._flags)]

    def get(self, key: str) -> Flag | None:
        with self._lock:
            return self._flags.get(key)

    def __len__(self) -> int:
        with self._lock:
            return len(self._flags)
