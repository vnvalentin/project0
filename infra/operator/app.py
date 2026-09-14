"""FastAPI surface for the operator control plane (read-only status).

Private and operator-token authenticated; loopback/management-only. No mutating
endpoints in this slice. Mirrors infra/enrollment/app.py's create_app factory so
tests inject a fake inspector and never touch a real systemctl/docker call.
"""
from __future__ import annotations

import hmac
from dataclasses import asdict

from fastapi import Depends, FastAPI, Header, HTTPException

from .config import load_config
from .services import RealServiceInspector, StatusService, UnknownServiceError


def create_app(status_service: StatusService, operator_token: str) -> FastAPI:
    app = FastAPI(title="Project0 Operator Control Plane")

    def require_operator(authorization: str | None = Header(default=None)) -> None:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="missing bearer token")
        presented = authorization[len("Bearer "):]
        if not hmac.compare_digest(presented, operator_token):
            raise HTTPException(status_code=403, detail="invalid operator token")

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/status", dependencies=[Depends(require_operator)])
    def status() -> dict:
        return {"services": [asdict(s) for s in status_service.status_all()]}

    @app.get("/status/{name}", dependencies=[Depends(require_operator)])
    def status_one(name: str) -> dict:
        try:
            return asdict(status_service.status_one(name))
        except UnknownServiceError as exc:
            raise HTTPException(status_code=404, detail="unknown service") from exc

    return app


def build_production_app() -> FastAPI:
    config = load_config()
    status_service = StatusService(config.services, RealServiceInspector())
    return create_app(status_service, config.operator_token)
