"""FastAPI wiring for the enrollment service's HTTP surface.

Exposes `POST /redeem` and `POST /login`. Every rejection reason from
`EnrollmentService.redeem` / the login authority delegation maps to a bounded
HTTP status; the client never receives a stack trace or unbounded error text.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md) and
Slice 088 (docs/slices/088-auth-gated-onboarding-login-delegation.md).
"""
from __future__ import annotations

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .config import EnrollmentConfig, load_config
from .login_client import LoginAuthorityClient, LoginAuthorityError, RealLoginAuthorityClient
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

# Slice 088: maps the loopback login authority's bounded outcome/transport
# reasons to a public HTTP status for POST /login, mirroring _REJECTION_STATUS
# above. BAD_CREDENTIALS/MALFORMED are reported to the caller as 401/400 (the
# login authority already pays a fixed PBKDF2 cost on an unknown username and
# returns the identical reason for both, so no enumeration is added here);
# UPSTREAM_UNAVAILABLE/UPSTREAM_ERROR (the loopback endpoint unreachable or
# returning an unexpected shape) are both reported as 502, never leaking
# transport detail.
_LOGIN_REJECTION_STATUS = {
    LoginAuthorityError.BAD_CREDENTIALS: 401,
    LoginAuthorityError.MALFORMED: 400,
    LoginAuthorityError.UPSTREAM_UNAVAILABLE: 502,
    LoginAuthorityError.UPSTREAM_ERROR: 502,
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


class LoginRequest(BaseModel):
    username: str = Field(min_length=1)
    password: str = Field(min_length=1)


class LoginResponse(BaseModel):
    assertion: str


def create_app(service: EnrollmentService, login_authority_client: LoginAuthorityClient) -> FastAPI:
    """Build a FastAPI app bound to the given (already-configured) service and login client.

    Production entrypoints call this with a service wired to the real
    OPNsense client and store, and a login client wired to the real loopback
    login authority; tests call it with fakes so no live call is ever made.
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

    @app.post("/login", response_model=LoginResponse)
    def login(request: LoginRequest) -> LoginResponse:
        try:
            assertion = login_authority_client.verify_and_mint(request.username, request.password)
        except LoginAuthorityError as exc:
            status_code = _LOGIN_REJECTION_STATUS.get(exc.reason, 502)
            raise HTTPException(status_code=status_code, detail=exc.reason) from exc
        return LoginResponse(assertion=assertion)

    return app


def build_production_service(config: EnrollmentConfig | None = None) -> EnrollmentService:
    """Wire the real OPNsense client and sqlite store. Never used by tests."""
    config = config or load_config()
    store = EnrollmentStore(config.db_path)
    opnsense_client: OpnsenseWireguardClient = RealOpnsenseWireguardClient(
        config.opnsense_api_key, config.opnsense_api_secret
    )
    return EnrollmentService(config, store, opnsense_client)


def build_production_login_authority_client(config: EnrollmentConfig | None = None) -> LoginAuthorityClient:
    """Wire the real loopback login-authority client. Never used by tests."""
    config = config or load_config()
    return RealLoginAuthorityClient(
        config.login_authority_host, config.login_authority_port, config.login_authority_timeout_seconds
    )


app = None  # Constructed lazily by an ASGI entrypoint (e.g. uvicorn factory), not at import time.
