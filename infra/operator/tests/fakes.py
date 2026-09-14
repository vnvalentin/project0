"""Test doubles for the operator control plane: an in-memory service inspector
so no real systemctl/docker call is ever made in tests."""
from __future__ import annotations


class FakeServiceInspector:
    def __init__(self, systemd: dict[str, str] | None = None, docker: dict[str, str] | None = None) -> None:
        self._systemd = systemd or {}
        self._docker = docker or {}

    def systemd_active(self, unit: str) -> str:
        return self._systemd.get(unit, "unknown")

    def docker_state(self, container: str) -> str:
        return self._docker.get(container, "unknown")
