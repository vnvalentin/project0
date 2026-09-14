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
    finally:
        store.close()
    return 1


if __name__ == "__main__":
    sys.exit(main())
