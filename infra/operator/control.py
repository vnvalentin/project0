"""Mutating service control (start/stop/restart) over allowlisted identifiers.
Fixed argument vectors only — no shell, no caller-supplied command.
"""
from __future__ import annotations

import subprocess
from typing import Protocol

_LIFECYCLE_ACTIONS = ("start", "stop", "restart")


class ServiceController(Protocol):
    def run(self, kind: str, action: str, identifier: str) -> tuple[bool, str]: ...


class RealServiceController:
    """Runs fixed lifecycle commands. Never used in tests.

    Managing a systemd unit as the non-root service user requires a
    polkit/sudoers grant for that specific unit (an ops prerequisite); docker
    lifecycle commands work for a user in the docker group.
    """

    _TIMEOUT_SECONDS = 30

    def run(self, kind: str, action: str, identifier: str) -> tuple[bool, str]:
        if action not in _LIFECYCLE_ACTIONS:
            return False, "unknown action"
        if kind == "systemd":
            return self._run(["systemctl", action, identifier])
        if kind == "docker":
            return self._run(["docker", action, identifier])
        return False, "unknown service kind"

    def _run(self, argv: list[str]) -> tuple[bool, str]:
        try:
            proc = subprocess.run(
                argv, capture_output=True, text=True, timeout=self._TIMEOUT_SECONDS, check=False
            )
        except (OSError, subprocess.SubprocessError) as exc:
            return False, f"exec error: {type(exc).__name__}"
        if proc.returncode == 0:
            return True, "ok"
        detail = (proc.stderr or proc.stdout or "").strip()
        return False, (detail[:200] if detail else f"exit {proc.returncode}")
