"""FastAPI surface for the operator control plane (read-only status + audited
mutating actions).

Private and operator-token authenticated; loopback/management-only. Mutating
actions are allowlisted and wrapped in audited jobs. Mirrors
infra/enrollment/app.py's create_app factory so tests inject fakes and never
touch a real systemctl/docker call.
"""
from __future__ import annotations

import hmac
import os
from dataclasses import asdict

from fastapi import Depends, FastAPI, Header, HTTPException

from .config import load_config
from .control import RealServiceController
from .audit_store import SqliteAuditLog
from .operations import OperationsService
from .services import RealServiceInspector, StatusService, UnknownServiceError
from .operator_auth import verify_operator_token


def create_app(status_service: StatusService, operations_service: OperationsService, operator_token: str, assertion_secret_hex: str | None = None) -> FastAPI:
    app = FastAPI(title="Project0 Operator Control Plane")

    def require_operator(authorization: str | None = Header(default=None)) -> None:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="missing bearer token")
        presented = authorization[len("Bearer "):]
        if assertion_secret_hex:
            if verify_operator_token(presented, assertion_secret_hex) is None:
                raise HTTPException(status_code=403, detail="invalid operator assertion")
            return
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

    @app.post("/services/{name}/restart", dependencies=[Depends(require_operator)])
    def restart(name: str, x_operator: str | None = Header(default=None)) -> dict:
        try:
            job = operations_service.restart(name, (x_operator or "operator").strip() or "operator")
        except UnknownServiceError as exc:
            raise HTTPException(status_code=404, detail="unknown service") from exc
        return job.to_dict()

    @app.post("/services/{name}/start", dependencies=[Depends(require_operator)])
    def start(name: str, x_operator: str | None = Header(default=None)) -> dict:
        try:
            job = operations_service.start(name, (x_operator or "operator").strip() or "operator")
        except UnknownServiceError as exc:
            raise HTTPException(status_code=404, detail="unknown service") from exc
        return job.to_dict()

    @app.post("/services/{name}/stop", dependencies=[Depends(require_operator)])
    def stop(name: str, x_operator: str | None = Header(default=None)) -> dict:
        try:
            job = operations_service.stop(name, (x_operator or "operator").strip() or "operator")
        except UnknownServiceError as exc:
            raise HTTPException(status_code=404, detail="unknown service") from exc
        return job.to_dict()

    @app.get("/jobs", dependencies=[Depends(require_operator)])
    def jobs() -> dict:
        return {"jobs": [job.to_dict() for job in operations_service.recent_jobs()]}

    return app


def build_production_app() -> FastAPI:
    config = load_config()
    status_service = StatusService(config.services, RealServiceInspector())
    operations_service = OperationsService(
        config.services, RealServiceController(), SqliteAuditLog(config.audit_db_path),
    )
    return create_app(
        status_service, operations_service, config.operator_token,
        os.getenv("PROJECT0_ASSERTION_SECRET_HEX", "").strip() or None,
    )
