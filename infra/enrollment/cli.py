#!/usr/bin/env python3
"""Admin CLI to mint single-use WireGuard enrollment invite codes and to
revoke/ban an enrolled peer.

Codes are CSPRNG (secrets.token_urlsafe), never derived from guessable
input. Run as: python -m infra.enrollment.cli mint-invite [--expires-in-seconds N]
Revoke a peer as: python -m infra.enrollment.cli revoke-peer <public_key>

This CLI is the only revocation surface (operator/shell access only); no
HTTP admin endpoint is exposed, per Slice 049's documented scope decision.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md)
and Slice 049 (docs/slices/049-wireguard-revocation-lifecycle.md).
"""
from __future__ import annotations

import argparse
import secrets
import sys
import time

from .config import load_config
from .opnsense_client import OpnsenseWireguardClient, RealOpnsenseWireguardClient
from .service import RevocationRejected, RevocationService
from .store import EnrollmentStore

INVITE_CODE_BYTES = 24


def generate_invite_code() -> str:
    return secrets.token_urlsafe(INVITE_CODE_BYTES)


def cmd_mint_invite(store: EnrollmentStore, expires_in_seconds: int | None) -> str:
    code = generate_invite_code()
    expires_at = time.time() + expires_in_seconds if expires_in_seconds is not None else None
    store.mint_invite(code, expires_at=expires_at)
    return code


def cmd_revoke_peer(store: EnrollmentStore, opnsense_client: OpnsenseWireguardClient, public_key: str) -> str:
    service = RevocationService(store, opnsense_client)
    result = service.revoke(public_key)
    return result.outcome.value


def cmd_deprovision_stale(
    store: EnrollmentStore,
    opnsense_client: OpnsenseWireguardClient,
    older_than_seconds: int,
    dry_run: bool,
    now: float | None = None,
) -> list[str]:
    """Slice 089: reclaim assertion-path peers idle past `older_than_seconds`.
    Returns the public keys reclaimed (or, with dry_run, the keys that would be).
    Each revoke is atomic/fail-closed (RevocationService); a single upstream
    failure is skipped so one bad peer never blocks the whole sweep."""
    now = now if now is not None else time.time()
    threshold = now - older_than_seconds
    stale = store.list_stale_account_allocations(threshold)
    if dry_run:
        return [public_key for _account_id, public_key in stale]
    service = RevocationService(store, opnsense_client)
    reclaimed: list[str] = []
    for _account_id, public_key in stale:
        try:
            service.revoke(public_key)
            reclaimed.append(public_key)
        except RevocationRejected:
            continue
    return reclaimed


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Admin CLI for the enrollment service.")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    mint = subparsers.add_parser("mint-invite", help="Mint a new single-use invite code.")
    mint.add_argument(
        "--expires-in-seconds",
        type=int,
        default=None,
        help="Optional expiry, in seconds from now. Omit for a non-expiring invite.",
    )

    revoke = subparsers.add_parser("revoke-peer", help="Revoke/ban an enrolled peer by its public key.")
    revoke.add_argument("public_key", help="The WireGuard public key of the peer to revoke.")

    deprovision = subparsers.add_parser(
        "deprovision-stale", help="Reclaim assertion-path peers idle past the TTL."
    )
    deprovision.add_argument(
        "--older-than-seconds",
        type=int,
        default=None,
        help="Idle threshold in seconds; defaults to ENROLLMENT_PEER_IDLE_TTL_SECONDS.",
    )
    deprovision.add_argument(
        "--dry-run",
        action="store_true",
        help="List the peers that would be reclaimed without revoking them.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    config = load_config()
    store = EnrollmentStore(config.db_path)
    try:
        if args.subcommand == "mint-invite":
            code = cmd_mint_invite(store, args.expires_in_seconds)
            print(code)
            return 0
        if args.subcommand == "revoke-peer":
            opnsense_client = RealOpnsenseWireguardClient(config.opnsense_api_key, config.opnsense_api_secret)
            try:
                outcome = cmd_revoke_peer(store, opnsense_client, args.public_key)
            except RevocationRejected as exc:
                print(f"REJECTED: {exc.reason.value}", file=sys.stderr)
                return 1
            print(outcome)
            return 0
        if args.subcommand == "deprovision-stale":
            older_than = (
                args.older_than_seconds
                if args.older_than_seconds is not None
                else config.peer_idle_ttl_seconds
            )
            opnsense_client = RealOpnsenseWireguardClient(config.opnsense_api_key, config.opnsense_api_secret)
            reclaimed = cmd_deprovision_stale(store, opnsense_client, older_than, args.dry_run)
            for public_key in reclaimed:
                print(public_key)
            print(f"{'would reclaim' if args.dry_run else 'reclaimed'}: {len(reclaimed)}")
            return 0
    finally:
        store.close()
    return 1


if __name__ == "__main__":
    sys.exit(main())
