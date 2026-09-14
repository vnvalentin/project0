"""Production ASGI entrypoint for the Linux operator control plane."""
from __future__ import annotations

from .app import build_production_app

app = build_production_app()
