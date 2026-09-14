"""Production ASGI entrypoint for the Linux enrollment service."""
from __future__ import annotations

from .app import build_production_service, create_app

app = create_app(build_production_service())
