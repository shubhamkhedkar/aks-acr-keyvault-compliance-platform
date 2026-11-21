"""Read secrets that the Azure Key Vault CSI driver mounts as files.

The Secrets Store CSI driver writes each Key Vault secret to
``<mount>/<objectAlias>``. With rotation enabled on the AKS add-on the file
content changes in place, so the value is re-read whenever the file's mtime
changes instead of being cached for the life of the process.
"""

from __future__ import annotations

import hmac
import os
import threading
from pathlib import Path


class MountedSecret:
    def __init__(self, directory: str | Path, name: str) -> None:
        self.path = Path(directory) / name
        self._lock = threading.Lock()
        self._mtime: float | None = None
        self._value: str | None = None

    def value(self) -> str | None:
        try:
            mtime = os.stat(self.path).st_mtime
        except FileNotFoundError:
            with self._lock:
                self._mtime, self._value = None, None
            return None
        with self._lock:
            if mtime != self._mtime:
                text = self.path.read_text(encoding="utf-8").strip()
                self._value = text or None
                self._mtime = mtime
            return self._value

    def available(self) -> bool:
        value = self.value()
        return value is not None and len(value) >= 32

    def matches(self, presented: str | None) -> bool:
        expected = self.value()
        if not expected or not presented or len(expected) < 32:
            return False
        return hmac.compare_digest(expected.encode(), presented.encode())
