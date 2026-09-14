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
from pydantic import BaseModel

from .config import load_config
from .control import RealServiceController
from .invites import RealInviteAdmin
from .jobs import AuditLog
from .operations import OperationsService
from .services import RealServiceInspector, StatusService, UnknownServiceError


class MintInviteRequest(BaseModel):
    expires_in_seconds: int | None = None


def create_app(status_service: StatusService, operations_service: OperationsService, operator_token: str) -> FastAPI:
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

    @app.post("/services/{name}/restart", dependencies=[Depends(require_operator)])
    def restart(name: str, x_operator: str | None = Header(default=None)) -> dict:
        try:
            job = operations_service.restart(name, (x_operator or "operator").strip() or "operator")
        except UnknownServiceError as exc:
            raise HTTPException(status_code=404, detail="unknown service") from exc
        return job.to_dict()

    @app.get("/jobs", dependencies=[Depends(require_operator)])
    def jobs() -> dict:
        return {"jobs": [job.to_dict() for job in operations_service.recent_jobs()]}

    @app.post("/invites", dependencies=[Depends(require_operator)])
    def mint_invite(body: MintInviteRequest | None = None, x_operator: str | None = Header(default=None)) -> dict:
        expires = body.expires_in_seconds if body else None
        job, code = operations_service.mint_invite((x_operator or "operator").strip() or "operator", expires)
        result: dict = {"job": job.to_dict()}
        if code:
            # The invite code is a secret returned to the operator only; it is
            # never in the job/audit log.
            result["invite_code"] = code
        return result

    return app


def build_production_app() -> FastAPI:
    config = load_config()
    status_service = StatusService(config.services, RealServiceInspector())
    from infra.enrollment.config import DEFAULT_DB_PATH as ENROLLMENT_DEFAULT_DB_PATH
    from infra.enrollment.store import EnrollmentStore

    enrollment_db = os.getenv("ENROLLMENT_DB_PATH", ENROLLMENT_DEFAULT_DB_PATH)
    invite_admin = RealInviteAdmin(EnrollmentStore(enrollment_db))
    operations_service = OperationsService(
        config.services, RealServiceController(), AuditLog(), invite_admin=invite_admin
    )
    return create_app(status_service, operations_service, config.operator_token)
