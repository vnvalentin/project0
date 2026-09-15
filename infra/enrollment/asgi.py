"""Production ASGI entrypoint for the Linux enrollment service."""
from __future__ import annotations

from .app import build_production_login_authority_client, build_production_service, create_app
from .config import load_config

_config = load_config()
app = create_app(build_production_service(_config), build_production_login_authority_client(_config))
