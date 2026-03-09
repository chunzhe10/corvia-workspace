"""Pydantic models for corvia-dev."""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel


class ServiceState(str, Enum):
    """Possible states for a managed service."""

    STARTING = "starting"
    HEALTHY = "healthy"
    UNHEALTHY = "unhealthy"
    STOPPED = "stopped"
    CRASHED = "crashed"


class ServiceDefinition(BaseModel):
    """Static definition of a service in the registry."""

    name: str
    tier: int  # 0=core, 1=provider, 2=additive
    port: int | None = None
    health_path: str = "/health"
    start_cmd: list[str] = []
    stop_signal: str = "SIGTERM"
    depends_on: list[str] = []
    exclusive_group: str | None = None


class ServiceStatus(BaseModel):
    """Runtime status of a single service."""

    name: str
    state: ServiceState
    port: int | None = None
    pid: int | None = None
    uptime_s: float | None = None
    reason: str | None = None


class ManagerStatus(BaseModel):
    """Status of the process manager itself."""

    pid: int
    uptime_s: float
    state: str


class ConfigSummary(BaseModel):
    """Summary of current corvia.toml config."""

    embedding_provider: str
    merge_provider: str
    storage: str
    workspace: str


class StatusResponse(BaseModel):
    """Full status response -- the JSON contract for the VS Code extension."""

    manager: ManagerStatus | None = None
    services: list[ServiceStatus] = []
    config: ConfigSummary
    enabled_services: list[str] = []
    logs: list[str] = []
