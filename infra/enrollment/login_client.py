"""Injectable client for the login authority's loopback delegation endpoint.

`LoginAuthorityClient` is the seam `EnrollmentService`/the `/login` route
depends on; tests substitute a fake so no real network call is ever made.
`RealLoginAuthorityClient` is the only implementation that talks to the login
process's loopback HTTP endpoint (`server/login_loopback_http_endpoint.gd`,
`POST /internal/verify-and-mint`) — mirroring `opnsense_client.py`'s
`Protocol` + `Real*` split.

Delivered for Slice 088 (docs/slices/088-auth-gated-onboarding-login-delegation.md).
"""
from __future__ import annotations

import json
from typing import Protocol
from urllib import error as urllib_error
from urllib import request as urllib_request


class LoginAuthorityError(Exception):
    """Raised for every rejection/timeout/connection-failure path.

    `reason` is a bounded string reused verbatim from the login authority's
    own outcome vocabulary (`bad_credentials`, `malformed`, `unavailable`) or
    one of this client's own bounded transport reasons
    (`upstream_unavailable`, `upstream_error`) — never a raw exception
    message that could embed request/response content.
    """

    BAD_CREDENTIALS = "bad_credentials"
    MALFORMED = "malformed"
    UPSTREAM_UNAVAILABLE = "upstream_unavailable"
    UPSTREAM_ERROR = "upstream_error"

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


class LoginAuthorityClient(Protocol):
    """The interface the enrollment service's /login route depends on. Never call a real implementation in a test."""

    def verify_and_mint(self, username: str, password: str) -> str:
        """Verifies credentials against the login authority and returns the signed assertion.

        Raises LoginAuthorityError on any rejection, timeout, or connection failure.
        """
        ...


class RealLoginAuthorityClient:
    """The only implementation that performs real network I/O against the login authority's loopback endpoint."""

    def __init__(self, host: str, port: int, timeout_seconds: float) -> None:
        self._host = host
        self._port = port
        self._timeout_seconds = timeout_seconds

    def verify_and_mint(self, username: str, password: str) -> str:
        body = json.dumps({"username": username, "password": password}).encode("utf-8")
        url = f"http://{self._host}:{self._port}/internal/verify-and-mint"
        req = urllib_request.Request(
            url,
            data=body,
            method="POST",
            headers={"Content-Type": "application/json", "Content-Length": str(len(body))},
        )
        try:
            with urllib_request.urlopen(req, timeout=self._timeout_seconds) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib_error.HTTPError as exc:
            reason = self._reason_from_rejection_body(exc)
            raise LoginAuthorityError(reason) from exc
        except (urllib_error.URLError, TimeoutError, OSError) as exc:
            raise LoginAuthorityError(LoginAuthorityError.UPSTREAM_UNAVAILABLE) from exc
        except (json.JSONDecodeError, ValueError) as exc:
            raise LoginAuthorityError(LoginAuthorityError.UPSTREAM_ERROR) from exc

        if payload.get("outcome") != "ok" or not isinstance(payload.get("assertion"), str):
            raise LoginAuthorityError(LoginAuthorityError.UPSTREAM_ERROR)
        return payload["assertion"]

    @staticmethod
    def _reason_from_rejection_body(exc: urllib_error.HTTPError) -> str:
        try:
            payload = json.loads(exc.read().decode("utf-8"))
            outcome = payload.get("outcome")
        except (json.JSONDecodeError, ValueError, AttributeError):
            outcome = None
        if outcome == LoginAuthorityError.BAD_CREDENTIALS:
            return LoginAuthorityError.BAD_CREDENTIALS
        if outcome == LoginAuthorityError.MALFORMED:
            return LoginAuthorityError.MALFORMED
        return LoginAuthorityError.UPSTREAM_ERROR


class AssertionValidationError(Exception):
    """Slice 089: raised for every assertion-validation rejection/timeout/
    connection-failure path. `reason` is a bounded string (the login authority's
    own SessionAssertion.REASON_* vocabulary, or one of this client's transport
    reasons) \u2014 never a raw exception message that could embed the token.
    """

    REJECTED = "assertion_rejected"
    UPSTREAM_UNAVAILABLE = "upstream_unavailable"
    UPSTREAM_ERROR = "upstream_error"

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


class AssertionValidationClient(Protocol):
    """Slice 089: the seam EnrollmentService.redeem_with_assertion depends on for
    validating an assertion. Never call a real implementation in a test."""

    def validate(self, assertion: str) -> tuple[str, int]:
        """Validates the assertion via the login authority and returns
        (account_id, expires_at). Raises AssertionValidationError on any
        rejection, timeout, or connection failure."""
        ...


class RealAssertionValidationClient:
    """The only implementation that performs real network I/O against the login
    authority's loopback POST /internal/validate-assertion endpoint."""

    def __init__(self, host: str, port: int, timeout_seconds: float) -> None:
        self._host = host
        self._port = port
        self._timeout_seconds = timeout_seconds

    def validate(self, assertion: str) -> tuple[str, int]:
        body = json.dumps({"assertion": assertion}).encode("utf-8")
        url = f"http://{self._host}:{self._port}/internal/validate-assertion"
        req = urllib_request.Request(
            url,
            data=body,
            method="POST",
            headers={"Content-Type": "application/json", "Content-Length": str(len(body))},
        )
        try:
            with urllib_request.urlopen(req, timeout=self._timeout_seconds) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib_error.HTTPError as exc:
            # Any bounded validation rejection (expired/tampered/wrong-issuer/...)
            # collapses to a single opaque reason; the token itself is never logged.
            raise AssertionValidationError(AssertionValidationError.REJECTED) from exc
        except (urllib_error.URLError, TimeoutError, OSError) as exc:
            raise AssertionValidationError(AssertionValidationError.UPSTREAM_UNAVAILABLE) from exc
        except (json.JSONDecodeError, ValueError) as exc:
            raise AssertionValidationError(AssertionValidationError.UPSTREAM_ERROR) from exc

        account_id = payload.get("account_id")
        expires_at = payload.get("expires_at")
        if payload.get("outcome") != "ok" or not isinstance(account_id, str) or not isinstance(expires_at, int):
            raise AssertionValidationError(AssertionValidationError.UPSTREAM_ERROR)
        return account_id, expires_at


class CharacterAuthorityError(Exception):
    """Slice 090 (ADR 0005): raised for every character-op rejection/transport
    failure. `reason` is a bounded string — the login authority's own domain
    outcome (e.g. `NAME_TAKEN`, `NO_SUCH_CHARACTER`), `assertion_rejected` when
    the account assertion is invalid, or a transport reason — never a raw
    exception message or the assertion token.
    """

    ASSERTION_REJECTED = "assertion_rejected"
    UPSTREAM_UNAVAILABLE = "upstream_unavailable"
    UPSTREAM_ERROR = "upstream_error"

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


class CharacterClient(Protocol):
    """Slice 090: the seam the enrollment character routes depend on. Every call
    is account-scoped by the presented account assertion; a real implementation
    delegates to the login authority's loopback character endpoints. Never call
    a real implementation in a test."""

    def list_characters(self, assertion: str) -> list[dict]: ...

    def create_character(self, assertion: str, name: str, cosmetic: dict) -> dict: ...

    def delete_character(self, assertion: str, character_id: str) -> None: ...

    def select_character(self, assertion: str, character_id: str) -> str: ...


class RealCharacterClient:
    """The only implementation that performs real network I/O against the login
    authority's loopback character endpoints."""

    def __init__(self, host: str, port: int, timeout_seconds: float) -> None:
        self._host = host
        self._port = port
        self._timeout_seconds = timeout_seconds

    def _post(self, path: str, body: dict) -> dict:
        data = json.dumps(body).encode("utf-8")
        url = f"http://{self._host}:{self._port}{path}"
        req = urllib_request.Request(
            url,
            data=data,
            method="POST",
            headers={"Content-Type": "application/json", "Content-Length": str(len(data))},
        )
        try:
            with urllib_request.urlopen(req, timeout=self._timeout_seconds) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib_error.HTTPError as exc:
            # A non-2xx from the loopback endpoint means the account assertion
            # itself was rejected (401) or the request was malformed (400);
            # both collapse to a single opaque reason — the token is never logged.
            raise CharacterAuthorityError(CharacterAuthorityError.ASSERTION_REJECTED) from exc
        except (urllib_error.URLError, TimeoutError, OSError) as exc:
            raise CharacterAuthorityError(CharacterAuthorityError.UPSTREAM_UNAVAILABLE) from exc
        except (json.JSONDecodeError, ValueError) as exc:
            raise CharacterAuthorityError(CharacterAuthorityError.UPSTREAM_ERROR) from exc

    def list_characters(self, assertion: str) -> list[dict]:
        payload = self._post("/internal/characters/list", {"assertion": assertion})
        if payload.get("outcome") != "ok" or not isinstance(payload.get("characters"), list):
            raise CharacterAuthorityError(str(payload.get("outcome", CharacterAuthorityError.UPSTREAM_ERROR)))
        return payload["characters"]

    def create_character(self, assertion: str, name: str, cosmetic: dict) -> dict:
        payload = self._post(
            "/internal/characters/create", {"assertion": assertion, "name": name, "cosmetic": cosmetic}
        )
        if payload.get("outcome") != "ok" or not isinstance(payload.get("character"), dict):
            raise CharacterAuthorityError(str(payload.get("outcome", CharacterAuthorityError.UPSTREAM_ERROR)))
        return payload["character"]

    def delete_character(self, assertion: str, character_id: str) -> None:
        payload = self._post(
            "/internal/characters/delete", {"assertion": assertion, "character_id": character_id}
        )
        if payload.get("outcome") != "ok":
            raise CharacterAuthorityError(str(payload.get("outcome", CharacterAuthorityError.UPSTREAM_ERROR)))

    def select_character(self, assertion: str, character_id: str) -> str:
        payload = self._post(
            "/internal/characters/select", {"assertion": assertion, "character_id": character_id}
        )
        if payload.get("outcome") != "ok" or not isinstance(payload.get("assertion"), str):
            raise CharacterAuthorityError(str(payload.get("outcome", CharacterAuthorityError.UPSTREAM_ERROR)))
        return payload["assertion"]
