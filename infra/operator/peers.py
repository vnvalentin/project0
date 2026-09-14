"""Peer administration adapter for the operator control plane.

Reuses the enrollment RevocationService (delete the OPNsense peer, release its
/32) so the operator can revoke a peer without reimplementing the logic. The
bounded enrollment outcome/rejection is translated into an outcome string or a
bounded PeerRevocationError, decoupling the operations layer from enrollment
internals.
"""
from __future__ import annotations

from typing import Protocol


class PeerRevocationError(Exception):
    """Bounded revocation failure; `reason` is an enum value, never free text."""

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


class PeerAdmin(Protocol):
    def revoke_peer(self, public_key: str) -> str: ...


class RealPeerAdmin:
    def __init__(self, revocation_service) -> None:
        self._svc = revocation_service

    def revoke_peer(self, public_key: str) -> str:
        # Imported lazily so the operator service does not require the OPNsense
        # client stack unless a revoke is actually wired.
        from infra.enrollment.service import RevocationRejected

        try:
            result = self._svc.revoke(public_key)
        except RevocationRejected as exc:
            raise PeerRevocationError(exc.reason.value) from exc
        return result.outcome.value
