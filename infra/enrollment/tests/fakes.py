"""Test-only fakes for the retained public HTTPS service seams."""
from __future__ import annotations

from infra.enrollment.login_client import CharacterAuthorityError, LoginAuthorityError


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

    def register(self, username: str, password: str) -> dict[str, str]:
        self.calls.append({"operation": "register", "username": username, "password": password})
        if self.fail_with_reason is not None:
            raise LoginAuthorityError(self.fail_with_reason)
        return {"account_id": "acct-registered", "username": username}


class FakeCharacterClient:
    """Slice 090: records character-op calls; returns configured data or raises a
    bounded CharacterAuthorityError (matching what the real loopback client would
    raise on an auth/domain/transport failure)."""

    def __init__(
        self,
        characters: list | None = None,
        created_character: dict | None = None,
        selected_assertion: str = "fake-character-assertion",
        fail_with_reason: str | None = None,
    ) -> None:
        self.characters = characters if characters is not None else []
        self.created_character = created_character if created_character is not None else {"character_id": "char-1"}
        self.selected_assertion = selected_assertion
        self.fail_with_reason = fail_with_reason
        self.calls: list[dict] = []

    def _maybe_fail(self) -> None:
        if self.fail_with_reason is not None:
            raise CharacterAuthorityError(self.fail_with_reason)

    def list_characters(self, assertion: str) -> list[dict]:
        self.calls.append({"op": "list", "assertion": assertion})
        self._maybe_fail()
        return self.characters

    def create_character(self, assertion: str, name: str, cosmetic: dict) -> dict:
        self.calls.append({"op": "create", "assertion": assertion, "name": name, "cosmetic": cosmetic})
        self._maybe_fail()
        return self.created_character

    def delete_character(self, assertion: str, character_id: str) -> None:
        self.calls.append({"op": "delete", "assertion": assertion, "character_id": character_id})
        self._maybe_fail()

    def select_character(self, assertion: str, character_id: str) -> str:
        self.calls.append({"op": "select", "assertion": assertion, "character_id": character_id})
        self._maybe_fail()
        return self.selected_assertion
