"""Test-only fakes for the enrollment service's injectable seams.

No test in this package ever performs real network I/O; `FakeOpnsenseWireguardClient`
is the substitute for `OpnsenseWireguardClient` that every test wires in, and
`FakeLoginAuthorityClient` (Slice 088) is the substitute for `LoginAuthorityClient`.
"""
from __future__ import annotations

from infra.enrollment.login_client import AssertionValidationError, LoginAuthorityError
from infra.enrollment.opnsense_client import OpnsenseApiError


class FakeOpnsenseWireguardClient:
    """Records add_client/reconfigure/delete_client calls; can be configured to fail."""

    def __init__(
        self,
        fail_add_client: bool = False,
        fail_reconfigure: bool = False,
        fail_delete_client: bool = False,
    ) -> None:
        self.fail_add_client = fail_add_client
        self.fail_reconfigure = fail_reconfigure
        self.fail_delete_client = fail_delete_client
        self.add_client_calls: list[dict] = []
        self.reconfigure_calls = 0
        self.delete_client_calls: list[str] = []
        self._next_uuid = 0

    def add_client(self, name: str, public_key: str, tunnel_address: str, keepalive_seconds: int) -> str:
        if self.fail_add_client:
            raise OpnsenseApiError("simulated addClient failure")
        self.add_client_calls.append(
            {
                "name": name,
                "public_key": public_key,
                "tunnel_address": tunnel_address,
                "keepalive_seconds": keepalive_seconds,
            }
        )
        self._next_uuid += 1
        return f"fake-client-uuid-{self._next_uuid}"

    def reconfigure(self) -> None:
        if self.fail_reconfigure:
            raise OpnsenseApiError("simulated reconfigure failure")
        self.reconfigure_calls += 1

    def delete_client(self, client_uuid: str) -> None:
        if self.fail_delete_client:
            raise OpnsenseApiError("simulated delClient failure")
        self.delete_client_calls.append(client_uuid)


class FakeLoginAuthorityClient:
    """Records verify_and_mint calls; can be configured to return a fixed
    assertion or raise a bounded LoginAuthorityError (matching what the real
    loopback client would raise on a rejection/timeout/connection failure)."""

    def __init__(self, assertion: str = "fake-assertion-token", fail_with_reason: str | None = None) -> None:
        self.assertion = assertion
        self.fail_with_reason = fail_with_reason
        self.calls: list[dict] = []

    def verify_and_mint(self, username: str, password: str) -> str:
        self.calls.append({"username": username, "password": password})
        if self.fail_with_reason is not None:
            raise LoginAuthorityError(self.fail_with_reason)
        return self.assertion


class FakeAssertionValidationClient:
    """Slice 089: records validate() calls; returns a fixed
    (account_id, expires_at) or raises a bounded AssertionValidationError
    (matching what the real loopback client raises on a rejection/failure)."""

    def __init__(
        self,
        account_id: str = "acct-1",
        expires_at: int = 9999999999,
        fail_with_reason: str | None = None,
    ) -> None:
        self.account_id = account_id
        self.expires_at = expires_at
        self.fail_with_reason = fail_with_reason
        self.calls: list[str] = []

    def validate(self, assertion: str) -> tuple[str, int]:
        self.calls.append(assertion)
        if self.fail_with_reason is not None:
            raise AssertionValidationError(self.fail_with_reason)
        return self.account_id, self.expires_at
