"""Read-only inspection of allowlisted host services (systemd units and docker
containers). No mutation, no shell, no caller-supplied command — every command
is a fixed argument vector against an allowlisted identifier.
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class ServiceStatus:
    name: str
    kind: str
    identifier: str
    active: bool
    state: str


class UnknownServiceError(Exception):
    """Raised when a name outside the allowlist is requested."""


class ServiceInspector(Protocol):
    def systemd_active(self, unit: str) -> str: ...
    def docker_state(self, container: str) -> str: ...


class RealServiceInspector:
    """Runs fixed read-only status commands. Never used in tests."""

    _TIMEOUT_SECONDS = 5

    def systemd_active(self, unit: str) -> str:
        return self._run(["systemctl", "is-active", unit])

    def docker_state(self, container: str) -> str:
        return self._run(["docker", "inspect", "-f", "{{.State.Status}}", container])

    def _run(self, argv: list[str]) -> str:
        try:
            proc = subprocess.run(
                argv, capture_output=True, text=True, timeout=self._TIMEOUT_SECONDS, check=False
            )
        except (OSError, subprocess.SubprocessError):
            return "unknown"
        out = (proc.stdout or "").strip()
        return out if out else "unknown"


class StatusService:
    _ACTIVE_STATES = {"active", "running"}

    def __init__(self, services: dict[str, tuple[str, str]], inspector: ServiceInspector) -> None:
        self._services = dict(services)
        self._inspector = inspector

    def status_all(self) -> list[ServiceStatus]:
        return [self.status_one(name) for name in self._services]

    def status_one(self, name: str) -> ServiceStatus:
        if name not in self._services:
            raise UnknownServiceError(name)
        kind, identifier = self._services[name]
        if kind == "systemd":
            state = self._inspector.systemd_active(identifier)
        elif kind == "docker":
            state = self._inspector.docker_state(identifier)
        else:
            state = "unknown"
        return ServiceStatus(
            name=name,
            kind=kind,
            identifier=identifier,
            active=state in self._ACTIVE_STATES,
            state=state,
        )
