"""Invite administration adapter for the operator control plane.

Reuses the enrollment store for persistence and the same CSPRNG code primitive
as infra/enrollment/cli.py, so the operator can mint single-use invites without
reimplementing the logic or pulling the enrollment CLI's OPNsense imports.

The returned code is a single-use SECRET credential — callers MUST NOT log it or
place it in the audit log.
"""
from __future__ import annotations

import secrets
import time
from typing import Protocol

# Mirrors infra/enrollment/cli.py::INVITE_CODE_BYTES — a CSPRNG code, never
# derived from guessable input.
_INVITE_CODE_BYTES = 24


class InviteAdmin(Protocol):
    def mint_invite(self, expires_in_seconds: int | None) -> str: ...


class RealInviteAdmin:
    def __init__(self, store) -> None:
        self._store = store

    def mint_invite(self, expires_in_seconds: int | None) -> str:
        code = secrets.token_urlsafe(_INVITE_CODE_BYTES)
        expires_at = time.time() + expires_in_seconds if expires_in_seconds is not None else None
        self._store.mint_invite(code, expires_at=expires_at)
        return code
