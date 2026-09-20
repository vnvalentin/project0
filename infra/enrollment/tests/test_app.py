"""Shared configuration helper for retained public HTTPS route tests."""
from infra.enrollment.config import EnrollmentConfig


def make_config(**overrides) -> EnrollmentConfig:
    values = {
        "login_authority_host": "127.0.0.1",
        "login_authority_port": 9997,
        "login_authority_timeout_seconds": 1.0,
    }
    values.update(overrides)
    return EnrollmentConfig(**values)
