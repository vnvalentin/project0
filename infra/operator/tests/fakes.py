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
        self.calls: list[tuple[str, str, str]] = []
        self._systemd_ok = systemd_ok
        self._docker_ok = docker_ok

    def run(self, kind: str, action: str, identifier: str) -> tuple[bool, str]:
        self.calls.append((kind, action, identifier))
        ok = self._systemd_ok if kind == "systemd" else self._docker_ok
        return (ok, "ok" if ok else f"{kind} boom")


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


class FakePeerAdmin:
    def __init__(self, outcome: str = "REVOKED", reject_reason: str | None = None) -> None:
        self.calls: list[str] = []
        self._outcome = outcome
        self._reject_reason = reject_reason

    def revoke_peer(self, public_key: str) -> str:
        self.calls.append(public_key)
        if self._reject_reason is not None:
            from infra.operator.peers import PeerRevocationError

            raise PeerRevocationError(self._reject_reason)
        return self._outcome
