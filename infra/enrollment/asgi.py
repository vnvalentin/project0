"""Production ASGI entrypoint for the Linux enrollment service."""
from __future__ import annotations

import os

from .app import (
    build_production_character_client,
    build_production_login_authority_client,
    create_app,
)
from .config import load_config
from .rate_limit import PublicAuthRateLimiter

_config = load_config()
app = create_app(
    build_production_login_authority_client(_config),
    build_production_character_client(_config),
    PublicAuthRateLimiter(
        max_attempts=_config.public_auth_max_attempts,
        window_seconds=_config.public_auth_window_seconds,
        lockout_seconds=_config.public_auth_lockout_seconds,
    ),
    patches_dir=os.environ.get("ENROLLMENT_PATCHES_DIR") or None,
)
