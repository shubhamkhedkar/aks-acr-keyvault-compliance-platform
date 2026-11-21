"""Flag model, validation and deterministic evaluation.

A flag is evaluated in this order:
1. disabled flags are always off;
2. a tenant on the deny list is always off;
3. a tenant on the allow list is always on;
4. otherwise the subject is bucketed (0-99) with SHA-256 over "<flag>:<subject>"
   and is on when the bucket is below ``rollout_percent``.

Bucketing is stable, so a user keeps the same answer across replicas and restarts.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import asdict, dataclass, field

KEY_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}$")
TENANT_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
MAX_LIST = 200


class ValidationError(ValueError):
    """Raised when a flag document or an evaluation request is invalid."""


@dataclass(frozen=True)
class Flag:
    key: str
    description: str = ""
    enabled: bool = False
    rollout_percent: int = 0
    allow_tenants: tuple[str, ...] = field(default_factory=tuple)
    deny_tenants: tuple[str, ...] = field(default_factory=tuple)
    owner: str = "platform"

    def to_dict(self) -> dict:
        data = asdict(self)
        data["allow_tenants"] = list(self.allow_tenants)
        data["deny_tenants"] = list(self.deny_tenants)
        return data


def _tenant_list(value: object, name: str) -> tuple[str, ...]:
    if value is None:
        return ()
    if not isinstance(value, list) or len(value) > MAX_LIST:
        raise ValidationError(f"{name} must be a list of at most {MAX_LIST} tenants")
    for item in value:
        if not isinstance(item, str) or not TENANT_PATTERN.match(item):
            raise ValidationError(f"{name} contains an invalid tenant id: {item!r}")
    return tuple(sorted(set(value)))


def parse_flag(key: str, doc: object) -> Flag:
    """Validate an untrusted JSON document and return a Flag."""
    if not KEY_PATTERN.match(key or ""):
        raise ValidationError("flag key must be 2-63 chars of lowercase letters, digits and '-'")
    if not isinstance(doc, dict):
        raise ValidationError("flag body must be a JSON object")
    unknown = set(doc) - {
        "key",
        "description",
        "enabled",
        "rollout_percent",
        "allow_tenants",
        "deny_tenants",
        "owner",
    }
    if unknown:
        raise ValidationError(f"unknown fields: {', '.join(sorted(unknown))}")
    if "key" in doc and doc["key"] != key:
        raise ValidationError("body key does not match the URL key")

    enabled = doc.get("enabled", False)
    if not isinstance(enabled, bool):
        raise ValidationError("enabled must be a boolean")

    rollout = doc.get("rollout_percent", 0)
    if isinstance(rollout, bool) or not isinstance(rollout, int) or not 0 <= rollout <= 100:
        raise ValidationError("rollout_percent must be an integer between 0 and 100")

    description = doc.get("description", "")
    if not isinstance(description, str) or len(description) > 280:
        raise ValidationError("description must be a string of at most 280 chars")

    owner = doc.get("owner", "platform")
    if not isinstance(owner, str) or not TENANT_PATTERN.match(owner):
        raise ValidationError("owner must be a short identifier")

    allow = _tenant_list(doc.get("allow_tenants"), "allow_tenants")
    deny = _tenant_list(doc.get("deny_tenants"), "deny_tenants")
    overlap = set(allow) & set(deny)
    if overlap:
        raise ValidationError(f"tenants cannot be both allowed and denied: {sorted(overlap)}")

    return Flag(
        key=key,
        description=description,
        enabled=enabled,
        rollout_percent=rollout,
        allow_tenants=allow,
        deny_tenants=deny,
        owner=owner,
    )


def bucket(flag_key: str, subject: str) -> int:
    """Stable 0-99 bucket for a subject under a flag."""
    digest = hashlib.sha256(f"{flag_key}:{subject}".encode()).digest()
    return int.from_bytes(digest[:8], "big") % 100


def evaluate(flag: Flag, tenant: str, subject: str) -> tuple[bool, str]:
    """Return (on, reason) for a tenant/subject pair."""
    if not flag.enabled:
        return False, "flag-disabled"
    if tenant in flag.deny_tenants:
        return False, "tenant-denied"
    if tenant in flag.allow_tenants:
        return True, "tenant-allowed"
    if bucket(flag.key, subject) < flag.rollout_percent:
        return True, "rollout"
    return False, "outside-rollout"
