"""FastAPI wiring for the enrollment service's HTTP surface.

Exposes the public HTTPS login, registration, character, and patch routes.
Every rejection reason from the login/character authority delegation maps to a
bounded HTTP status; the client never receives a stack trace or unbounded error
text.

Delivered for Slice 088 (docs/slices/088-auth-gated-onboarding-login-delegation.md).
"""
from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .config import EnrollmentConfig, load_config
from .login_client import (
    CharacterAuthorityError,
    CharacterClient,
    LoginAuthorityClient,
    LoginAuthorityError,
    RealCharacterClient,
    RealLoginAuthorityClient,
)
from .rate_limit import PublicAuthRateLimiter

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


class LoginRequest(BaseModel):
    username: str = Field(min_length=1)
    password: str = Field(min_length=1)


class LoginResponse(BaseModel):
    assertion: str


class RegisterResponse(BaseModel):
    account_id: str
    username: str


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


LATEST_WINDOWS_CLIENT_PATH = "/patches/downloads/0.13.2/Project0-client-windows-x64-0.13.2.zip"


def create_app(
    login_authority_client: LoginAuthorityClient,
    character_client: CharacterClient | None = None,
    public_auth_limiter: PublicAuthRateLimiter | None = None,
    patches_dir: str | None = None,
) -> FastAPI:
    """Build a FastAPI app bound to the configured authority clients.

    Production entrypoints wire the login and character clients to the real
    loopback authority; tests inject fakes so no live call is ever made.
    """
    app = FastAPI(title="Project0 Public HTTPS Service")
    public_auth_limiter = public_auth_limiter or PublicAuthRateLimiter()

    @app.get("/", response_class=HTMLResponse)
    def landing_page() -> str:
        return _public_page(
            "Project0",
            "A shared world for friends.",
            f"""
            <a class="primary" href="{LATEST_WINDOWS_CLIENT_PATH}">Download the latest Windows client</a>
            <p class="endpoint">project0.valentin.vip:9999<br><small>UDP game endpoint</small></p>
            <a href="/telemetry">Service status</a>
            <a href="/dashboard">Dashboard</a>
            """,
        )

    @app.get("/downloads/", response_class=HTMLResponse)
    def downloads_page() -> str:
        return _public_page(
            "Downloads",
            "Get the latest Windows client and launcher.",
            '<a class="primary" href="/patches/downloads/">Open downloads</a><a href="/">Back to Project0</a>',
        )

    @app.get("/telemetry", response_class=HTMLResponse)
    def telemetry_page() -> str:
        return _public_page(
            "Telemetry",
            "Public service status.",
            '<p class="status">Enrollment service: online</p><a href="/healthz">Health check</a><a href="/">Back to Project0</a>',
        )

    @app.get("/dashboard", response_class=HTMLResponse)
    def dashboard_page() -> str:
        return _public_page(
            "Dashboard",
            "Operator dashboard access is available on the private network.",
            '<a href="/telemetry">Service status</a><a href="/">Back to Project0</a>',
        )

    @app.get("/game", response_class=HTMLResponse)
    def game_page() -> str:
        return _public_page(
            "Game connection",
            "Connect the latest launcher to the Project0 world.",
            f'<p class="endpoint">project0.valentin.vip:9999<br><small>UDP game endpoint</small></p><a class="primary" href="{LATEST_WINDOWS_CLIENT_PATH}">Download the latest Windows client</a><a href="/">Back to Project0</a>',
        )

    # Public by design: an outdated client cannot authenticate before it patches.
    if patches_dir:
        app.mount("/patches", StaticFiles(directory=patches_dir, html=True), name="patches")

    def _rate_limited(detail: str = "public_auth_rate_limited") -> HTTPException:
        return HTTPException(status_code=429, detail=detail)

    def _login_key(http_request: Request, username: str) -> str:
        return f"login:{http_request.client.host if http_request.client else 'unknown'}:{username.casefold()}"

    def _character_key(http_request: Request) -> str:
        return f"characters:{http_request.client.host if http_request.client else 'unknown'}"

    def _enforce_character_limit(http_request: Request) -> None:
        if not public_auth_limiter.consume(_character_key(http_request)):
            raise _rate_limited()

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/login", response_model=LoginResponse)
    def login(http_request: Request, request: LoginRequest) -> LoginResponse:
        key = _login_key(http_request, request.username)
        if not public_auth_limiter.allowed(key):
            raise _rate_limited()
        try:
            assertion = login_authority_client.verify_and_mint(request.username, request.password)
        except LoginAuthorityError as exc:
            if exc.reason == LoginAuthorityError.BAD_CREDENTIALS:
                public_auth_limiter.record_failure(key)
            status_code = _LOGIN_REJECTION_STATUS.get(exc.reason, 502)
            raise HTTPException(status_code=status_code, detail=exc.reason) from exc
        public_auth_limiter.record_success(key)
        return LoginResponse(assertion=assertion)

    @app.post("/register", response_model=RegisterResponse)
    def register(http_request: Request, request: LoginRequest) -> RegisterResponse:
        key = _login_key(http_request, request.username)
        if not public_auth_limiter.consume(key):
            raise _rate_limited()
        try:
            result = login_authority_client.register(request.username, request.password)
        except LoginAuthorityError as exc:
            status_code = 409 if exc.reason == "username_taken" else _LOGIN_REJECTION_STATUS.get(exc.reason, 502)
            raise HTTPException(status_code=status_code, detail=exc.reason) from exc
        return RegisterResponse(account_id=result["account_id"], username=result["username"])

    def _require_character_client() -> CharacterClient:
        if character_client is None:
            raise HTTPException(status_code=503, detail="character_authority_unavailable")
        return character_client

    def _character_http_error(exc: CharacterAuthorityError) -> HTTPException:
        return HTTPException(status_code=_CHARACTER_REJECTION_STATUS.get(exc.reason, 400), detail=exc.reason)

    @app.post("/characters/list", response_model=CharacterListResponse)
    def characters_list(http_request: Request, request: CharacterListRequest) -> CharacterListResponse:
        _enforce_character_limit(http_request)
        try:
            characters = _require_character_client().list_characters(request.assertion)
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return CharacterListResponse(characters=characters)

    @app.post("/characters/create", response_model=CharacterResponse)
    def characters_create(http_request: Request, request: CharacterCreateRequest) -> CharacterResponse:
        _enforce_character_limit(http_request)
        try:
            character = _require_character_client().create_character(
                request.assertion, request.name, request.cosmetic
            )
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return CharacterResponse(character=character)

    @app.post("/characters/delete")
    def characters_delete(http_request: Request, request: CharacterMutateRequest) -> dict:
        _enforce_character_limit(http_request)
        try:
            _require_character_client().delete_character(request.assertion, request.character_id)
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return {"outcome": "ok"}

    @app.post("/characters/select", response_model=CharacterAssertionResponse)
    def characters_select(http_request: Request, request: CharacterMutateRequest) -> CharacterAssertionResponse:
        _enforce_character_limit(http_request)
        try:
            assertion = _require_character_client().select_character(request.assertion, request.character_id)
        except CharacterAuthorityError as exc:
            raise _character_http_error(exc) from exc
        return CharacterAssertionResponse(assertion=assertion)

    return app


def _public_page(title: str, subtitle: str, body: str) -> str:
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} | Project0</title>
<style>body{{margin:0;background:#101820;color:#edf4f2;font:16px system-ui,sans-serif}}main{{max-width:760px;margin:12vh auto;padding:32px}}h1{{font-size:clamp(2.5rem,8vw,5rem);margin:0 0 12px;color:#f7c873}}p{{color:#b8c9c5;line-height:1.6}}a{{display:inline-block;margin:18px 18px 0 0;color:#8ed8c7;text-decoration:none;border-bottom:1px solid #8ed8c7;padding-bottom:4px}}a.primary{{background:#f7c873;color:#101820;border:0;padding:12px 16px;border-radius:4px;font-weight:700}}.status,.endpoint{{border-left:3px solid #8ed8c7;padding:12px 16px;color:#edf4f2}}.endpoint{{font:700 1.4rem ui-monospace,monospace}}small{{font:14px system-ui,sans-serif;color:#b8c9c5}}</style></head>
<body><main><p>PROJECT0 / {title.upper()}</p><h1>{title}</h1><p>{subtitle}</p>{body}</main></body></html>"""


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
