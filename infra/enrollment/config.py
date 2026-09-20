"""Environment-driven configuration for the public HTTPS service."""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class EnrollmentConfig:
    login_authority_host: str
    login_authority_port: int
    login_authority_timeout_seconds: float
    public_auth_max_attempts: int = 5
    public_auth_window_seconds: float = 60.0
    public_auth_lockout_seconds: float = 300.0


def load_config() -> EnrollmentConfig:
    """Load only settings required by the retained HTTPS authority calls."""
    try:
        login_authority_port = int(os.getenv("LOGIN_AUTHORITY_PORT", "9997").strip())
        login_authority_timeout_seconds = float(
            os.getenv("LOGIN_AUTHORITY_TIMEOUT_SECONDS", "5").strip()
        )
        public_auth_max_attempts = int(os.getenv("PUBLIC_AUTH_MAX_ATTEMPTS", "5").strip())
        public_auth_window_seconds = float(os.getenv("PUBLIC_AUTH_WINDOW_SECONDS", "60").strip())
        public_auth_lockout_seconds = float(os.getenv("PUBLIC_AUTH_LOCKOUT_SECONDS", "300").strip())
    except ValueError as exc:
        raise RuntimeError("LOGIN_AUTHORITY_* and PUBLIC_AUTH_* values must be numeric") from exc
    if public_auth_max_attempts < 1 or public_auth_window_seconds <= 0 or public_auth_lockout_seconds <= 0:
        raise RuntimeError("PUBLIC_AUTH_* values must be positive")
    return EnrollmentConfig(
        login_authority_host=os.getenv("LOGIN_AUTHORITY_HOST", "127.0.0.1").strip(),
        login_authority_port=login_authority_port,
        login_authority_timeout_seconds=login_authority_timeout_seconds,
        public_auth_max_attempts=public_auth_max_attempts,
        public_auth_window_seconds=public_auth_window_seconds,
        public_auth_lockout_seconds=public_auth_lockout_seconds,
    )
