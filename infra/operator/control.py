"""Mutating service control (restart) over allowlisted identifiers. Fixed
argument vectors only — no shell, no caller-supplied command.
"""
from __future__ import annotations

import subprocess
from typing import Protocol


class ServiceController(Protocol):
    def restart_systemd(self, unit: str) -> tuple[bool, str]: ...
    def restart_docker(self, container: str) -> tuple[bool, str]: ...


class RealServiceController:
    """Runs fixed restart commands. Never used in tests.

    Restarting a systemd unit as the non-root service user requires a
    polkit/sudoers grant for that specific unit (an ops prerequisite); docker
    restarts work for a user in the docker group.
    """

    _TIMEOUT_SECONDS = 30

    def restart_systemd(self, unit: str) -> tuple[bool, str]:
        return self._run(["systemctl", "restart", unit])

    def restart_docker(self, container: str) -> tuple[bool, str]:
        return self._run(["docker", "restart", container])

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
