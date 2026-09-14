"""Environment-driven configuration for the operator control plane.

Mirrors infra/enrollment/config.py: values come from the environment, a missing
required value fails loud, and nothing secret is hardcoded.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

# Allowlisted services the control plane may inspect: name -> (kind, identifier).
# kind is "systemd" (a unit) or "docker" (a container). ONLY these names are ever
# inspectable; anything else is fail-closed.
DEFAULT_SERVICES: dict[str, tuple[str, str]] = {
    "game-server": ("systemd", "project0-server"),
    "enrollment": ("systemd", "project0-enrollment"),
    "dashboard": ("docker", "project0-flow"),
}


@dataclass(frozen=True)
class OperatorConfig:
    bind_host: str
    bind_port: int
    operator_token: str
    services: dict[str, tuple[str, str]]


def load_config() -> OperatorConfig:
    token = os.getenv("OPERATOR_TOKEN", "").strip()
    if not token:
        raise RuntimeError("OPERATOR_TOKEN must be set in the environment")

    host = os.getenv("OPERATOR_BIND_HOST", "127.0.0.1").strip()
    port_raw = os.getenv("OPERATOR_BIND_PORT", "8099").strip()
    try:
        port = int(port_raw)
    except ValueError as exc:
        raise RuntimeError(f"OPERATOR_BIND_PORT must be an integer: {port_raw}") from exc

    return OperatorConfig(
        bind_host=host,
        bind_port=port,
        operator_token=token,
        services=dict(DEFAULT_SERVICES),
    )
