"""Core enrollment redemption and revocation logic: the public seam for
Slices 048 and 049.

`EnrollmentService.redeem` is the single authoritative entry point. It never
touches a client private key (the client never sends one), and it never
commits a local IP allocation or marks an invite redeemed unless the OPNsense
registration call already succeeded — so a failed upstream call leaves no
partial durable state.

`RevocationService.revoke` is the single authoritative ban/revocation entry
point. It never releases a local allocation unless the OPNsense delete call
already succeeded — a fail-closed ban, so a swallowed upstream error can
never leave a banned peer with working access.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md)
against the resolved design in
.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md, and
Slice 049 (docs/slices/049-wireguard-revocation-lifecycle.md) against
.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from enum import Enum

from .config import EnrollmentConfig
from .login_client import AssertionValidationClient, AssertionValidationError
from .opnsense_client import OpnsenseApiError, OpnsenseWireguardClient
from .pubkey import InvalidPublicKeyError, validate_public_key
from .store import (
    AccountAlreadyHasPeerError,
    AllocationRecord,
    EnrollmentStore,
    InviteAlreadyRedeemedError,
    PoolExhaustedError,
)


class RedeemRejectionReason(str, Enum):
    INVITE_NOT_FOUND = "INVITE_NOT_FOUND"
    INVITE_EXPIRED = "INVITE_EXPIRED"
    INVITE_ALREADY_REDEEMED = "INVITE_ALREADY_REDEEMED"
    INVALID_PUBLIC_KEY = "INVALID_PUBLIC_KEY"
    POOL_EXHAUSTED = "POOL_EXHAUSTED"
    UPSTREAM_REGISTRATION_FAILED = "UPSTREAM_REGISTRATION_FAILED"
    # Slice 089: assertion-path rejections.
    ASSERTION_REJECTED = "ASSERTION_REJECTED"
    ACCOUNT_PEER_KEY_MISMATCH = "ACCOUNT_PEER_KEY_MISMATCH"


class RedeemRejected(Exception):
    """Raised for every rejection path. `reason` is a bounded enum, never free text."""

    def __init__(self, reason: RedeemRejectionReason, detail: str = "") -> None:
        self.reason = reason
        self.detail = detail
        super().__init__(f"{reason.value}: {detail}" if detail else reason.value)


@dataclass(frozen=True)
class PeerConfigBundle:
    server_public_key: str
    endpoint: str
    assigned_address: str
    allowed_ips: str
    persistent_keepalive_seconds: int


class EnrollmentService:
    def __init__(
        self,
        config: EnrollmentConfig,
        store: EnrollmentStore,
        opnsense_client: OpnsenseWireguardClient,
        assertion_validation_client: AssertionValidationClient | None = None,
    ) -> None:
        self._config = config
        self._store = store
        self._opnsense = opnsense_client
        # Slice 089: the seam redeem_with_assertion delegates assertion
        # validation to (the login authority's loopback endpoint in production).
        # Optional so the pure invite-path callers/tests need not wire it.
        self._assertion_validation_client = assertion_validation_client

    def redeem(self, invite_code: str, public_key: str) -> PeerConfigBundle:
        try:
            validated_key = validate_public_key(public_key)
        except InvalidPublicKeyError as exc:
            raise RedeemRejected(RedeemRejectionReason.INVALID_PUBLIC_KEY, str(exc)) from exc

        invite = self._store.get_invite(invite_code)
        if invite is None:
            raise RedeemRejected(RedeemRejectionReason.INVITE_NOT_FOUND, invite_code)
        if invite.redeemed_at is not None:
            raise RedeemRejected(RedeemRejectionReason.INVITE_ALREADY_REDEEMED, invite_code)
        if invite.expires_at is not None and invite.expires_at < time.time():
            raise RedeemRejected(RedeemRejectionReason.INVITE_EXPIRED, invite_code)

        server_network_and_broadcast = {
            self._config.pool_cidr.network_address,
            self._config.pool_cidr.broadcast_address,
        }
        server_own_address = next(self._config.pool_cidr.hosts())
        excluded = server_network_and_broadcast | {server_own_address}

        try:
            candidate_address = self._store.next_free_address(self._config.pool_cidr, excluded)
        except PoolExhaustedError as exc:
            raise RedeemRejected(RedeemRejectionReason.POOL_EXHAUSTED, str(exc)) from exc

        try:
            client_uuid = self._opnsense.add_client(
                name=f"invite-{invite_code[:8]}",
                public_key=validated_key,
                tunnel_address=f"{candidate_address}/32",
                keepalive_seconds=self._config.persistent_keepalive_seconds,
            )
            self._opnsense.reconfigure()
        except OpnsenseApiError as exc:
            raise RedeemRejected(RedeemRejectionReason.UPSTREAM_REGISTRATION_FAILED, str(exc)) from exc

        try:
            self._store.redeem_invite(
                code=invite_code,
                public_key=validated_key,
                ip_address=candidate_address,
                opnsense_client_uuid=client_uuid,
            )
        except InviteAlreadyRedeemedError as exc:
            raise RedeemRejected(RedeemRejectionReason.INVITE_ALREADY_REDEEMED, invite_code) from exc
        except PoolExhaustedError as exc:
            raise RedeemRejected(RedeemRejectionReason.POOL_EXHAUSTED, str(exc)) from exc

        return PeerConfigBundle(
            server_public_key=self._config.server_public_key,
            endpoint=self._config.wireguard_endpoint,
            assigned_address=f"{candidate_address}/32",
            allowed_ips=self._config.split_tunnel_allowed_ips,
            persistent_keepalive_seconds=self._config.persistent_keepalive_seconds,
        )

    def _make_bundle(self, assigned_ip: str) -> PeerConfigBundle:
        """Build a PeerConfigBundle for an already-assigned /32 host address
        (no CIDR suffix) plus the static server-side config fields."""
        return PeerConfigBundle(
            server_public_key=self._config.server_public_key,
            endpoint=self._config.wireguard_endpoint,
            assigned_address=f"{assigned_ip}/32",
            allowed_ips=self._config.split_tunnel_allowed_ips,
            persistent_keepalive_seconds=self._config.persistent_keepalive_seconds,
        )

    def redeem_with_assertion(
        self, assertion: str, public_key: str, now: float | None = None
    ) -> PeerConfigBundle:
        """Slice 089: the assertion-gated redeem path (ADR 0004 sub-decision 3).

        Validates the assertion via the delegation seam (never the shared secret
        locally), then provisions a WireGuard peer keyed idempotently on the
        account: a re-redeem from the same account with the same public key
        returns the existing peer (no OPNsense call); a different public key is
        rejected (no silent key rotation); a first redeem allocates a fresh /32
        with the same fail-closed ordering as the invite path (no durable commit
        unless the OPNsense registration already succeeded).
        """
        if self._assertion_validation_client is None:
            raise RedeemRejected(RedeemRejectionReason.ASSERTION_REJECTED, "no validation client")
        try:
            validated_key = validate_public_key(public_key)
        except InvalidPublicKeyError as exc:
            raise RedeemRejected(RedeemRejectionReason.INVALID_PUBLIC_KEY, str(exc)) from exc

        try:
            account_id, _expires_at = self._assertion_validation_client.validate(assertion)
        except AssertionValidationError as exc:
            raise RedeemRejected(RedeemRejectionReason.ASSERTION_REJECTED, exc.reason) from exc

        existing = self._store.get_allocation_by_account_id(account_id)
        if existing is not None:
            return self._resolve_existing_account_peer(existing, account_id, validated_key, now)

        server_network_and_broadcast = {
            self._config.pool_cidr.network_address,
            self._config.pool_cidr.broadcast_address,
        }
        server_own_address = next(self._config.pool_cidr.hosts())
        excluded = server_network_and_broadcast | {server_own_address}

        try:
            candidate_address = self._store.next_free_address(self._config.pool_cidr, excluded)
        except PoolExhaustedError as exc:
            raise RedeemRejected(RedeemRejectionReason.POOL_EXHAUSTED, str(exc)) from exc

        try:
            client_uuid = self._opnsense.add_client(
                name=f"acct-{account_id[:8]}",
                public_key=validated_key,
                tunnel_address=f"{candidate_address}/32",
                keepalive_seconds=self._config.persistent_keepalive_seconds,
            )
            self._opnsense.reconfigure()
        except OpnsenseApiError as exc:
            raise RedeemRejected(RedeemRejectionReason.UPSTREAM_REGISTRATION_FAILED, str(exc)) from exc

        try:
            self._store.record_assertion_redeem(
                account_id=account_id,
                public_key=validated_key,
                ip_address=candidate_address,
                opnsense_client_uuid=client_uuid,
                now=now,
            )
        except AccountAlreadyHasPeerError:
            # A concurrent first-redeem for this account won the race. Roll back
            # our just-created (and now orphaned) OPNsense peer, then resolve
            # against the winning row exactly as a normal re-redeem would.
            self._best_effort_delete_client(client_uuid)
            winner = self._store.get_allocation_by_account_id(account_id)
            if winner is None:
                raise RedeemRejected(RedeemRejectionReason.ASSERTION_REJECTED, "lost race, no winner")
            return self._resolve_existing_account_peer(winner, account_id, validated_key, now)
        except PoolExhaustedError as exc:
            raise RedeemRejected(RedeemRejectionReason.POOL_EXHAUSTED, str(exc)) from exc

        return self._make_bundle(str(candidate_address))

    def _resolve_existing_account_peer(
        self, existing: "AllocationRecord", account_id: str, validated_key: str, now: float | None
    ) -> PeerConfigBundle:
        """Idempotent re-redeem resolution: same key -> touch + return the same
        peer (no OPNsense call); different key -> reject (rotation is out of
        scope, ADR 0004 gives an assertion no device-continuity guarantee)."""
        if existing.public_key == validated_key:
            self._store.touch_allocation_last_seen(account_id, now)
            return self._make_bundle(existing.ip_address)
        raise RedeemRejected(RedeemRejectionReason.ACCOUNT_PEER_KEY_MISMATCH, account_id)

    def _best_effort_delete_client(self, client_uuid: str) -> None:
        """Roll back an orphaned OPNsense peer after a lost redeem race. Best
        effort: a failure here leaves an orphan for the next deprovision sweep
        rather than surfacing as a redeem error to the winning caller."""
        try:
            self._opnsense.delete_client(client_uuid)
            self._opnsense.reconfigure()
        except OpnsenseApiError:
            pass

    def deprovision_stale_peers(self, now: float | None = None) -> list["RevocationResult"]:
        """Slice 089: reclaim assertion-path peers idle past the configured TTL,
        reusing RevocationService.revoke verbatim (atomic, fail-closed OPNsense
        delete then local release). A single peer's upstream failure is isolated
        \u2014 the sweep continues and that peer's row is left for the next run."""
        now = now if now is not None else time.time()
        threshold = now - self._config.peer_idle_ttl_seconds
        revocation = RevocationService(self._store, self._opnsense)
        results: list[RevocationResult] = []
        for _account_id, public_key in self._store.list_stale_account_allocations(threshold):
            try:
                results.append(revocation.revoke(public_key))
            except RevocationRejected:
                continue
        return results


class RevocationOutcome(str, Enum):
    REVOKED = "REVOKED"
    ALREADY_ABSENT = "ALREADY_ABSENT"


class RevocationRejectionReason(str, Enum):
    UPSTREAM_DELETE_FAILED = "UPSTREAM_DELETE_FAILED"


class RevocationRejected(Exception):
    """Raised for the fail-closed rejection path. `reason` is a bounded enum, never free text."""

    def __init__(self, reason: RevocationRejectionReason, detail: str = "") -> None:
        self.reason = reason
        self.detail = detail
        super().__init__(f"{reason.value}: {detail}" if detail else reason.value)


@dataclass(frozen=True)
class RevocationResult:
    outcome: RevocationOutcome


class RevocationService:
    """Revokes a peer by public key: deletes it on OPNsense, then releases its /32.

    Fail-closed: if the OPNsense delete/reconfigure calls do not both
    succeed, no local state changes and the peer keeps its allocation and
    OPNsense registration, so a swallowed error can never leave a banned
    peer with working access.
    """

    def __init__(self, store: EnrollmentStore, opnsense_client: OpnsenseWireguardClient) -> None:
        self._store = store
        self._opnsense = opnsense_client

    def revoke(self, public_key: str) -> RevocationResult:
        client_uuid = self._store.get_allocation_by_public_key(public_key)
        if client_uuid is None:
            return RevocationResult(outcome=RevocationOutcome.ALREADY_ABSENT)

        try:
            self._opnsense.delete_client(client_uuid)
            self._opnsense.reconfigure()
        except OpnsenseApiError as exc:
            raise RevocationRejected(RevocationRejectionReason.UPSTREAM_DELETE_FAILED, str(exc)) from exc

        self._store.release_allocation_by_public_key(public_key)
        return RevocationResult(outcome=RevocationOutcome.REVOKED)
