"""FastAPI wiring for the enrollment service's HTTP surface.

Exposes exactly one endpoint, `POST /redeem`. Every rejection reason from
`EnrollmentService.redeem` maps to a bounded HTTP status; the client never
receives a stack trace or unbounded error text.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md).
"""
from __future__ import annotations

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .config import EnrollmentConfig, load_config
from .opnsense_client import OpnsenseWireguardClient, RealOpnsenseWireguardClient
from .service import EnrollmentService, RedeemRejected, RedeemRejectionReason
from .store import EnrollmentStore

_REJECTION_STATUS = {
    RedeemRejectionReason.INVITE_NOT_FOUND: 404,
    RedeemRejectionReason.INVITE_EXPIRED: 410,
    RedeemRejectionReason.INVITE_ALREADY_REDEEMED: 409,
    RedeemRejectionReason.INVALID_PUBLIC_KEY: 422,
    RedeemRejectionReason.POOL_EXHAUSTED: 409,
    RedeemRejectionReason.UPSTREAM_REGISTRATION_FAILED: 502,
}


class RedeemRequest(BaseModel):
    invite_code: str
    public_key: str


class RedeemResponse(BaseModel):
    server_public_key: str
    endpoint: str
    assigned_address: str
    allowed_ips: str
    persistent_keepalive_seconds: int


def create_app(service: EnrollmentService) -> FastAPI:
    """Build a FastAPI app bound to the given (already-configured) service.

    Production entrypoints call this with a service wired to the real
    OPNsense client and store; tests call it with a fake OPNsense client and
    a temp-file store so no live call is ever made.
    """
    app = FastAPI(title="Project0 WireGuard Enrollment Service")

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/redeem", response_model=RedeemResponse)
    def redeem(request: RedeemRequest) -> RedeemResponse:
        try:
            bundle = service.redeem(request.invite_code, request.public_key)
        except RedeemRejected as exc:
            status_code = _REJECTION_STATUS[exc.reason]
            raise HTTPException(status_code=status_code, detail=exc.reason.value) from exc
        return RedeemResponse(
            server_public_key=bundle.server_public_key,
            endpoint=bundle.endpoint,
            assigned_address=bundle.assigned_address,
            allowed_ips=bundle.allowed_ips,
            persistent_keepalive_seconds=bundle.persistent_keepalive_seconds,
        )

    return app


def build_production_service(config: EnrollmentConfig | None = None) -> EnrollmentService:
    """Wire the real OPNsense client and sqlite store. Never used by tests."""
    config = config or load_config()
    store = EnrollmentStore(config.db_path)
    opnsense_client: OpnsenseWireguardClient = RealOpnsenseWireguardClient(
        config.opnsense_api_key, config.opnsense_api_secret
    )
    return EnrollmentService(config, store, opnsense_client)


app = None  # Constructed lazily by an ASGI entrypoint (e.g. uvicorn factory), not at import time.
