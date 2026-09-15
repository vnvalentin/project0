"""Environment-driven configuration for the enrollment service.

Mirrors `infra/opnsense/setup_wireguard_game_tunnel.py`'s `os.getenv` pattern:
all values come from the environment, nothing is hardcoded as a secret, and a
missing required value fails loudly rather than silently defaulting.

Delivered for Slice 048
(docs/slices/048-wireguard-enrollment-service.md) against the resolved design
in .scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md.
"""
from __future__ import annotations

import ipaddress
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class EnrollmentConfig:
    opnsense_host: str
    opnsense_api_key: str
    opnsense_api_secret: str
    opnsense_ca_cert: str
    server_public_key: str
    wireguard_endpoint: str
    split_tunnel_allowed_ips: str
    pool_cidr: ipaddress.IPv4Network
    persistent_keepalive_seconds: int
    db_path: str
    # Slice 088: locates the login authority's loopback-only HTTP delegation
    # endpoint (server/login_loopback_http_endpoint.gd). Co-located by default
    # (ADR 0004) — the enrollment service and the login process run on the
    # same host, so this is a loopback call, never a second public hop.
    login_authority_host: str
    login_authority_port: int
    login_authority_timeout_seconds: float
    # Slice 089: an assertion-path peer whose last redeem/touch is older than
    # this is eligible for the operator-invoked deprovision sweep. Default 30
    # days. Invite-path peers are never aged by this.
    peer_idle_ttl_seconds: int


DEFAULT_DB_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), ".data", "enrollment.sqlite3"
)


def load_config() -> EnrollmentConfig:
    """Load configuration strictly from the environment.

    Raises RuntimeError with a clear message when a required value is
    missing, the same fail-loud behavior as
    `setup_wireguard_game_tunnel.get_api_credentials`.
    """
    api_key = os.getenv("OPNSENSE_API_KEY", "").strip()
    api_secret = os.getenv("OPNSENSE_API_SECRET", "").strip()
    server_pubkey = os.getenv("ENROLLMENT_SERVER_PUBLIC_KEY", "").strip()
    if not api_key or not api_secret:
        raise RuntimeError(
            "OPNSENSE_API_KEY and OPNSENSE_API_SECRET must be set in the environment"
        )
    if not server_pubkey:
        raise RuntimeError("ENROLLMENT_SERVER_PUBLIC_KEY must be set in the environment")

    pool_cidr_raw = os.getenv("ENROLLMENT_POOL_CIDR", "10.77.0.0/24").strip()
    try:
        pool_cidr = ipaddress.ip_network(pool_cidr_raw)
    except ValueError as exc:
        raise RuntimeError(f"ENROLLMENT_POOL_CIDR is not a valid CIDR: {pool_cidr_raw}") from exc

    keepalive_raw = os.getenv("ENROLLMENT_PERSISTENT_KEEPALIVE_SECONDS", "25").strip()
    try:
        keepalive = int(keepalive_raw)
    except ValueError as exc:
        raise RuntimeError(
            f"ENROLLMENT_PERSISTENT_KEEPALIVE_SECONDS must be an integer: {keepalive_raw}"
        ) from exc

    login_authority_port_raw = os.getenv("LOGIN_AUTHORITY_PORT", "9997").strip()
    try:
        login_authority_port = int(login_authority_port_raw)
    except ValueError as exc:
        raise RuntimeError(
            f"LOGIN_AUTHORITY_PORT must be an integer: {login_authority_port_raw}"
        ) from exc

    login_authority_timeout_raw = os.getenv("LOGIN_AUTHORITY_TIMEOUT_SECONDS", "5").strip()
    try:
        login_authority_timeout_seconds = float(login_authority_timeout_raw)
    except ValueError as exc:
        raise RuntimeError(
            f"LOGIN_AUTHORITY_TIMEOUT_SECONDS must be a number: {login_authority_timeout_raw}"
        ) from exc

    peer_idle_ttl_raw = os.getenv("ENROLLMENT_PEER_IDLE_TTL_SECONDS", "2592000").strip()
    try:
        peer_idle_ttl_seconds = int(peer_idle_ttl_raw)
    except ValueError as exc:
        raise RuntimeError(
            f"ENROLLMENT_PEER_IDLE_TTL_SECONDS must be an integer: {peer_idle_ttl_raw}"
        ) from exc

    return EnrollmentConfig(
        opnsense_host=os.getenv("OPNSENSE_HOST", "192.168.1.1").strip(),
        opnsense_api_key=api_key,
        opnsense_api_secret=api_secret,
        opnsense_ca_cert=os.getenv("OPNSENSE_CA_CERT", "").strip(),
        server_public_key=server_pubkey,
        wireguard_endpoint=os.getenv(
            "ENROLLMENT_WIREGUARD_ENDPOINT", "game.valentin.vip:51900"
        ).strip(),
        split_tunnel_allowed_ips=os.getenv(
            "ENROLLMENT_SPLIT_TUNNEL_ALLOWED_IPS", "192.168.1.254/32"
        ).strip(),
        pool_cidr=pool_cidr,
        persistent_keepalive_seconds=keepalive,
        db_path=os.getenv("ENROLLMENT_DB_PATH", DEFAULT_DB_PATH).strip(),
        login_authority_host=os.getenv("LOGIN_AUTHORITY_HOST", "127.0.0.1").strip(),
        login_authority_port=login_authority_port,
        login_authority_timeout_seconds=login_authority_timeout_seconds,
        peer_idle_ttl_seconds=peer_idle_ttl_seconds,
    )
