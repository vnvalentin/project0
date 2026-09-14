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


class FakeServiceController:
    def __init__(self, systemd_ok: bool = True, docker_ok: bool = True) -> None:
        self.calls: list[tuple[str, str]] = []
        self._systemd_ok = systemd_ok
        self._docker_ok = docker_ok

    def restart_systemd(self, unit: str) -> tuple[bool, str]:
        self.calls.append(("systemd", unit))
        return (self._systemd_ok, "ok" if self._systemd_ok else "systemd boom")

    def restart_docker(self, container: str) -> tuple[bool, str]:
        self.calls.append(("docker", container))
        return (self._docker_ok, "ok" if self._docker_ok else "docker boom")


class FakeInviteAdmin:
    def __init__(self, code: str = "invite-abc123", fail: bool = False) -> None:
        self.calls: list[int | None] = []
        self._code = code
        self._fail = fail

    def mint_invite(self, expires_in_seconds: int | None) -> str:
        self.calls.append(expires_in_seconds)
        if self._fail:
            raise RuntimeError("mint boom")
        return self._code
