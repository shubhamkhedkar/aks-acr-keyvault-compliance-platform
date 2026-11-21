#!/usr/bin/env python3
"""Summarise Cinc Auditor / InSpec `--reporter json-min` output read from stdin.

Prints one line per control and exits non-zero if any control failed.
"""

import json
import sys
from collections import Counter


def main() -> int:
    raw = sys.stdin.read()
    start = raw.find("{")
    if start < 0:
        print(raw, file=sys.stderr)
        return 2
    report = json.loads(raw[start:])
    statuses: dict[str, set[str]] = {}
    for c in report.get("controls", []):
        statuses.setdefault(c["id"], set()).add(c["status"])
    worst: Counter[str] = Counter()
    for cid in sorted(statuses):
        s = statuses[cid]
        status = "failed" if "failed" in s else ("skipped" if s == {"skipped"} else "passed")
        worst[status] += 1
        print(f"  {status:<7} {cid}")
    for c in report.get("controls", []):
        if c["status"] == "failed":
            message = " ".join(str(c.get("message", "")).split())[:160]
            print(f"    - {c['id']}: {str(c.get('code_desc', ''))[:120]} :: {message}".rstrip())
    tests = Counter(c["status"] for c in report.get("controls", []))
    print(
        f"  controls: {worst['passed']} passed, {worst['failed']} failed, {worst['skipped']} skipped"
        f" | tests: {tests['passed']} passed, {tests['failed']} failed, {tests['skipped']} skipped"
    )
    return 1 if worst["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
