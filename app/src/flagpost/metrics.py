"""Minimal Prometheus text exposition, no client library needed."""

from __future__ import annotations

import threading
from collections import Counter

BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0)


class Metrics:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.requests: Counter[tuple[str, str, int]] = Counter()
        self.evaluations: Counter[tuple[str, bool]] = Counter()
        self.latency_buckets: Counter[float] = Counter()
        self.latency_sum = 0.0
        self.latency_count = 0

    def observe_request(self, method: str, route: str, status: int, seconds: float) -> None:
        with self._lock:
            self.requests[(method, route, status)] += 1
            self.latency_sum += seconds
            self.latency_count += 1
            for upper in BUCKETS:
                if seconds <= upper:
                    self.latency_buckets[upper] += 1

    def observe_evaluation(self, flag: str, on: bool) -> None:
        with self._lock:
            self.evaluations[(flag, on)] += 1

    def render(self, flag_count: int, reloads: int = 0, reload_errors: int = 0) -> str:
        with self._lock:
            lines = [
                "# HELP flagpost_http_requests_total HTTP requests by method, route and status.",
                "# TYPE flagpost_http_requests_total counter",
            ]
            for (method, route, status), n in sorted(self.requests.items()):
                lines.append(f'flagpost_http_requests_total{{method="{method}",route="{route}",status="{status}"}} {n}')
            lines += [
                "# HELP flagpost_http_request_duration_seconds Request latency.",
                "# TYPE flagpost_http_request_duration_seconds histogram",
            ]
            for upper in BUCKETS:
                lines.append(
                    f'flagpost_http_request_duration_seconds_bucket{{le="{upper}"}} {self.latency_buckets[upper]}'
                )
            lines.append(f'flagpost_http_request_duration_seconds_bucket{{le="+Inf"}} {self.latency_count}')
            lines.append(f"flagpost_http_request_duration_seconds_sum {self.latency_sum:.6f}")
            lines.append(f"flagpost_http_request_duration_seconds_count {self.latency_count}")
            lines += [
                "# HELP flagpost_evaluations_total Flag evaluations by flag and result.",
                "# TYPE flagpost_evaluations_total counter",
            ]
            for (flag, on), n in sorted(self.evaluations.items()):
                lines.append(f'flagpost_evaluations_total{{flag="{flag}",result="{str(on).lower()}"}} {n}')
            lines += [
                "# HELP flagpost_flags Number of flags currently loaded.",
                "# TYPE flagpost_flags gauge",
                f"flagpost_flags {flag_count}",
                "# HELP flagpost_seed_reloads_total Successful hot reloads of the flag file.",
                "# TYPE flagpost_seed_reloads_total counter",
                f"flagpost_seed_reloads_total {reloads}",
                "# HELP flagpost_seed_reload_errors_total Rejected flag file changes (last good set kept).",
                "# TYPE flagpost_seed_reload_errors_total counter",
                f"flagpost_seed_reload_errors_total {reload_errors}",
            ]
            return "\n".join(lines) + "\n"
