"""Allowlisted, independently authenticated host lifecycle helper."""

from __future__ import annotations

import json
import subprocess
import sys
from collections.abc import Callable

from .operator_auth import verify_operator_token

_ALLOWED_UNITS = {
    "game-server": "project0-server",
    "login-server": "project0-login",
    "enrollment": "project0-enrollment",
}
_ALLOWED_ACTIONS = {"start", "stop", "restart"}


def execute(request: dict, secret_hex: str, runner: Callable[..., subprocess.CompletedProcess] = subprocess.run) -> dict:
    token = request.get("operator_token", "")
    identity = verify_operator_token(token, secret_hex)
    if identity is None or ("*" not in identity.scopes and "lifecycle" not in identity.scopes):
        return {"outcome": "rejected", "reason": "operator_scope_denied"}
    target = request.get("target", "")
    action = request.get("action", "")
    unit = _ALLOWED_UNITS.get(target)
    if unit is None or action not in _ALLOWED_ACTIONS:
        return {"outcome": "rejected", "reason": "unsupported_action"}
    result = runner(["systemctl", action, unit], capture_output=True, text=True, timeout=30, check=False, shell=False)
    if result.returncode != 0:
        return {"outcome": "rejected", "reason": "host_command_failed"}
    return {"outcome": "accepted", "reason": "ok", "operator_identity": identity.identity}


def main() -> int:
    secret_hex = __import__("os").environ.get("PROJECT0_ASSERTION_SECRET_HEX", "")
    result = execute(json.load(sys.stdin), secret_hex)
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["outcome"] == "accepted" else 1


if __name__ == "__main__":
    raise SystemExit(main())
