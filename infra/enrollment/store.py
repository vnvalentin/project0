"""Local sqlite3 store for invite codes and IP allocations.

Uses the Python stdlib `sqlite3` module (not `godot-sqlite`, which is a Godot
GDExtension with no meaning outside the engine process). All queries are
parameterized; no string-formatted SQL is ever built from request input.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md).
"""
from __future__ import annotations

import ipaddress
import os
import sqlite3
import time
from dataclasses import dataclass


class InviteNotFoundError(Exception):
    pass


class InviteExpiredError(Exception):
    pass


class InviteAlreadyRedeemedError(Exception):
    pass


class PoolExhaustedError(Exception):
    pass


@dataclass(frozen=True)
class Invite:
    code: str
    created_at: float
    expires_at: float | None
    redeemed_at: float | None
    redeemed_by_public_key: str | None


_SCHEMA = """
CREATE TABLE IF NOT EXISTS invites (
    code TEXT PRIMARY KEY,
    created_at REAL NOT NULL,
    expires_at REAL,
    redeemed_at REAL,
    redeemed_by_public_key TEXT
);

CREATE TABLE IF NOT EXISTS allocations (
    ip_address TEXT PRIMARY KEY,
    invite_code TEXT NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    opnsense_client_uuid TEXT NOT NULL,
    allocated_at REAL NOT NULL,
    FOREIGN KEY (invite_code) REFERENCES invites (code)
);
"""


class EnrollmentStore:
    """Owns one sqlite connection and all invite/allocation persistence."""

    def __init__(self, db_path: str) -> None:
        self._db_path = db_path
        if db_path != ":memory:":
            parent = os.path.dirname(db_path)
            if parent:
                os.makedirs(parent, exist_ok=True)
        # check_same_thread=False: FastAPI dispatches sync endpoints to a
        # worker threadpool, so a single request's store calls may not run on
        # the thread that opened the connection. Safe here because sqlite3's
        # underlying library serializes access and every mutation already
        # goes through an explicit single-statement or `with self._conn:`
        # transaction.
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.execute("PRAGMA foreign_keys = ON")
        self._conn.executescript(_SCHEMA)
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    def mint_invite(self, code: str, expires_at: float | None = None) -> Invite:
        now = time.time()
        self._conn.execute(
            "INSERT INTO invites (code, created_at, expires_at, redeemed_at, redeemed_by_public_key) "
            "VALUES (?, ?, ?, NULL, NULL)",
            (code, now, expires_at),
        )
        self._conn.commit()
        return Invite(code=code, created_at=now, expires_at=expires_at, redeemed_at=None, redeemed_by_public_key=None)

    def get_invite(self, code: str) -> Invite | None:
        row = self._conn.execute(
            "SELECT code, created_at, expires_at, redeemed_at, redeemed_by_public_key "
            "FROM invites WHERE code = ?",
            (code,),
        ).fetchone()
        if row is None:
            return None
        return Invite(*row)

    def allocated_addresses(self) -> set[ipaddress.IPv4Address]:
        rows = self._conn.execute("SELECT ip_address FROM allocations").fetchall()
        return {ipaddress.ip_address(row[0]) for row in rows}

    def next_free_address(
        self, pool_cidr: ipaddress.IPv4Network, excluded: set[ipaddress.IPv4Address]
    ) -> ipaddress.IPv4Address:
        """Return the next free host address in pool_cidr, skipping `excluded` and used allocations."""
        used = self.allocated_addresses()
        for host in pool_cidr.hosts():
            if host in excluded or host in used:
                continue
            return host
        raise PoolExhaustedError(f"No free address remains in {pool_cidr}")

    def redeem_invite(
        self,
        code: str,
        public_key: str,
        ip_address: ipaddress.IPv4Address,
        opnsense_client_uuid: str,
        now: float | None = None,
    ) -> None:
        """Atomically mark the invite redeemed and commit the IP allocation.

        Callers MUST have already validated the invite exists, is unexpired,
        and is unredeemed, and MUST have already completed the OPNsense
        registration call before invoking this — this method is the single
        durable-commit point and must not be called on a path that can still
        fail upstream.
        """
        now = now if now is not None else time.time()
        try:
            with self._conn:
                cursor = self._conn.execute(
                    "UPDATE invites SET redeemed_at = ?, redeemed_by_public_key = ? "
                    "WHERE code = ? AND redeemed_at IS NULL",
                    (now, public_key, code),
                )
                if cursor.rowcount != 1:
                    raise InviteAlreadyRedeemedError(f"invite {code!r} was already redeemed")
                self._conn.execute(
                    "INSERT INTO allocations (ip_address, invite_code, public_key, opnsense_client_uuid, allocated_at) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (str(ip_address), code, public_key, opnsense_client_uuid, now),
                )
        except sqlite3.IntegrityError as exc:
            raise PoolExhaustedError(f"address {ip_address} was already allocated") from exc

    def get_allocation_by_public_key(self, public_key: str) -> str | None:
        """Return the allocation's opnsense_client_uuid for public_key, or None if absent."""
        row = self._conn.execute(
            "SELECT opnsense_client_uuid FROM allocations WHERE public_key = ?",
            (public_key,),
        ).fetchone()
        return row[0] if row is not None else None

    def release_allocation_by_public_key(self, public_key: str) -> str | None:
        """Atomically delete the allocation row for public_key, freeing its /32.

        Returns the released opnsense_client_uuid, or None if no allocation
        exists for public_key (an idempotent no-op). Callers MUST have
        already confirmed the OPNsense delClient + reconfigure calls
        succeeded before invoking this — this method is the single durable
        release point and must not be called on a path that can still fail
        upstream.
        """
        with self._conn:
            row = self._conn.execute(
                "SELECT opnsense_client_uuid FROM allocations WHERE public_key = ?",
                (public_key,),
            ).fetchone()
            if row is None:
                return None
            self._conn.execute("DELETE FROM allocations WHERE public_key = ?", (public_key,))
            return row[0]
