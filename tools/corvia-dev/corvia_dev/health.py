"""Health checking for services."""

from __future__ import annotations

import time
import urllib.request
import urllib.error
from dataclasses import dataclass

from corvia_dev.models import ServiceDefinition


@dataclass
class HealthResult:
    """Result of a health check."""

    healthy: bool | None  # None = indeterminate (no port)
    latency_ms: float  # -1 if unhealthy/indeterminate


def check_http(host: str, port: int, path: str, timeout: float = 3.0) -> HealthResult:
    """Check health via HTTP GET. Returns HealthResult, never raises."""
    url = f"http://{host}:{port}{path}"
    start = time.monotonic()
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout):
            elapsed = (time.monotonic() - start) * 1000
            return HealthResult(healthy=True, latency_ms=round(elapsed, 1))
    except (urllib.error.URLError, OSError, TimeoutError):
        return HealthResult(healthy=False, latency_ms=-1)


def check_service(svc: ServiceDefinition, timeout: float = 3.0) -> HealthResult:
    """Check health of a service. Dispatches to appropriate check method."""
    if svc.port is None:
        return HealthResult(healthy=None, latency_ms=-1)
    return check_http("127.0.0.1", svc.port, svc.health_path, timeout=timeout)
