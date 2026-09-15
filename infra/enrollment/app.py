"""FastAPI wiring for the enrollment service's HTTP surface.

Exposes `POST /redeem` and `POST /login`. Every rejection reason from
`EnrollmentService.redeem` / the login authority delegation maps to a bounded
HTTP status; the client never receives a stack trace or unbounded error text.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md) and
Slice 088 (docs/slices/088-auth-gated-onboarding-login-delegation.md).
"""
from __future__ import annotations

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, model_validator

from .config import EnrollmentConfig, load_config
from .login_client import (
    AssertionValidationClient,
    CharacterAuthorityError,
    CharacterClient,
    LoginAuthorityClient,
    LoginAuthorityError,
    RealAssertionValidationClient,
    RealCharacterClient,
    RealLoginAuthorityClient,
)
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
    # Slice 089: assertion-path rejections.
    RedeemRejectionReason.ASSERTION_REJECTED: 401,
    RedeemRejectionReason.ACCOUNT_PEER_KEY_MISMATCH: 409,
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

# Slice 090 (ADR 0005): maps a character op's bounded reason to a public HTTP
# status. Transport/auth reasons and the login authority's domain outcomes
# (CharacterRecord.REJECT_*) are enumerated; any unlisted reason falls back to
# 400 rather than leaking detail.
_CHARACTER_REJECTION_STATUS = {
    CharacterAuthorityError.ASSERTION_REJECTED: 401,
    CharacterAuthorityError.UPSTREAM_UNAVAILABLE: 502,
    CharacterAuthorityError.UPSTREAM_ERROR: 502,
    "NOT_AUTHENTICATED": 401,
    "NAME_TAKEN": 409,
    "NAME_INVALID": 422,
    "CHARACTER_CAP_REACHED": 409,
    "NOT_OWNER": 403,
    "NO_SUCH_CHARACTER": 404,
    "ALREADY_DELETED": 409,
}


class RedeemRequest(BaseModel):
    # Slice 089: /redeem accepts EITHER an invite_code (operator/fallback path)
    # OR a signed assertion (self-service path) — exactly one, never both.
    invite_code: str | None = None
    assertion: str | None = None
    public_key: str

    @model_validator(mode="after")
    def _exactly_one_credential(self) -> "RedeemRequest":
        if (self.invite_code is None) == (self.assertion is None):
            raise ValueError("exactly one of invite_code or assertion must be provided")
        return self


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


class CharacterListRequest(BaseModel):
    assertion: str = Field(min_length=1)


class CharacterCreateRequest(BaseModel):
    assertion: str = Field(min_length=1)
    name: str
    cosmetic: dict = Field(default_factory=dict)


class CharacterMutateRequest(BaseModel):
    assertion: str = Field(min_length=1)
    character_id: str = Field(min_length=1)


class CharacterListResponse(BaseModel):
    characters: list


class CharacterResponse(BaseModel):
    character: dict


class CharacterAssertionResponse(BaseModel):
    assertion: str


def create_app(
    service: EnrollmentService,
    login_authority_client: LoginAuthorityClient,
    character_client: CharacterClient | None = None,
) -> FastAPI:
    """Build a FastAPI app bound to the given (already-configured) service and clients.

    Production entrypoints call this with a service wired to the real OPNsense
    client and store, a login client wired to the real loopback login
    authority, and (Slice 090) a real character client; tests call it with
    fakes so no live call is ever made.
    """
    app = FastAPI(title="Project0 WireGuard Enrollment Service")

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/redeem", response_model=RedeemResponse)
    def redeem(request: RedeemRequest) -> RedeemResponse:
        try:
            if request.assertion is not None:
                bundle = service.redeem_with_assertion(request.assertion, request.public_key)
            else:
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

    def _require_character_client() -> CharacterClient:
        if character_client is None:
            raise HTTPException(status_code=503, detail="character_authority_unavailable")
        return character_client

    def _character_http_error(exc: CharacterAuthorityError) -> HTTPException:
        return HTTPException(status_code=_CHARACTER_REJECTION_STATUS.get(exc.reason, 400), detail=exc.reason)

    @app.post("/characters/list", response_model=CharacterListResponse)
    def characters_list(request: CharacterListRequest) -> CharacterListResponse:
        try:
            characters = _require_character_client().list_characters(request.assertion)
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return CharacterListResponse(characters=characters)

    @app.post("/characters/create", response_model=CharacterResponse)
    def characters_create(request: CharacterCreateRequest) -> CharacterResponse:
        try:
            character = _require_character_client().create_character(
                request.assertion, request.name, request.cosmetic
            )
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return CharacterResponse(character=character)

    @app.post("/characters/delete")
    def characters_delete(request: CharacterMutateRequest) -> dict:
        try:
            _require_character_client().delete_character(request.assertion, request.character_id)
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return {"outcome": "ok"}

    @app.post("/characters/select", response_model=CharacterAssertionResponse)
    def characters_select(request: CharacterMutateRequest) -> CharacterAssertionResponse:
        try:
            assertion = _require_character_client().select_character(request.assertion, request.character_id)
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return CharacterAssertionResponse(assertion=assertion)

    return app


def build_production_service(config: EnrollmentConfig | None = None) -> EnrollmentService:
    """Wire the real OPNsense client, sqlite store, and (Slice 089) the real
    loopback assertion-validation client. Never used by tests."""
    config = config or load_config()
    store = EnrollmentStore(config.db_path)
    opnsense_client: OpnsenseWireguardClient = RealOpnsenseWireguardClient(
        config.opnsense_api_key, config.opnsense_api_secret
    )
    assertion_validation_client: AssertionValidationClient = RealAssertionValidationClient(
        config.login_authority_host, config.login_authority_port, config.login_authority_timeout_seconds
    )
    return EnrollmentService(config, store, opnsense_client, assertion_validation_client)


def build_production_login_authority_client(config: EnrollmentConfig | None = None) -> LoginAuthorityClient:
    """Wire the real loopback login-authority client. Never used by tests."""
    config = config or load_config()
    return RealLoginAuthorityClient(
        config.login_authority_host, config.login_authority_port, config.login_authority_timeout_seconds
    )


def build_production_character_client(config: EnrollmentConfig | None = None) -> CharacterClient:
    """Wire the real loopback character client (Slice 090). Never used by tests."""
    config = config or load_config()
    return RealCharacterClient(
        config.login_authority_host, config.login_authority_port, config.login_authority_timeout_seconds
    )


app = None  # Constructed lazily by an ASGI entrypoint (e.g. uvicorn factory), not at import time.
