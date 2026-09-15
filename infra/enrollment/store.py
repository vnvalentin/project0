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


class AccountAlreadyHasPeerError(Exception):
    """Slice 089: a concurrent first-time assertion redeem lost the race on the
    account_id partial unique index — another request already committed a live
    peer for this account."""


@dataclass(frozen=True)
class Invite:
    code: str
    created_at: float
    expires_at: float | None
    redeemed_at: float | None
    redeemed_by_public_key: str | None


@dataclass(frozen=True)
class AllocationRecord:
    """Slice 089: a full allocations row, enough to answer assertion-path
    idempotency and rebuild a PeerConfigBundle without a second OPNsense call."""

    ip_address: str
    public_key: str
    opnsense_client_uuid: str
    account_id: str | None
    last_seen_at: float | None


_INVITES_SCHEMA = """
CREATE TABLE IF NOT EXISTS invites (
    code TEXT PRIMARY KEY,
    created_at REAL NOT NULL,
    expires_at REAL,
    redeemed_at REAL,
    redeemed_by_public_key TEXT
);
"""

# Slice 089: allocations gains a nullable account_id (set for assertion-path
# peers, NULL for invite-path peers) and last_seen_at (redeem/touch time).
# invite_code becomes NULLABLE (assertion-path peers have no invite) — enforced
# by a PARTIAL unique index instead of an inline UNIQUE NOT NULL, so both
# invite_code and account_id are "at most one live row per non-NULL value".
_ALLOCATIONS_SCHEMA = """
CREATE TABLE IF NOT EXISTS allocations (
    ip_address TEXT PRIMARY KEY,
    invite_code TEXT,
    public_key TEXT NOT NULL,
    opnsense_client_uuid TEXT NOT NULL,
    allocated_at REAL NOT NULL,
    account_id TEXT,
    last_seen_at REAL,
    FOREIGN KEY (invite_code) REFERENCES invites (code)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_allocations_invite_code
    ON allocations(invite_code) WHERE invite_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_allocations_account_id
    ON allocations(account_id) WHERE account_id IS NOT NULL;
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
        self._conn.executescript(_INVITES_SCHEMA)
        self._ensure_allocations_schema()
        self._conn.commit()

    def _ensure_allocations_schema(self) -> None:
        """Slice 089: create the allocations table (new shape) or migrate an
        existing pre-089 table in place, idempotently. The pre-089 table has
        `invite_code TEXT NOT NULL UNIQUE` and no account_id/last_seen_at;
        assertion-path peers need invite_code nullable, which SQLite cannot do
        with ALTER COLUMN, so the migration rebuilds the table. Safe to run on
        every boot: once migrated (account_id present) it only re-asserts the
        IF-NOT-EXISTS table/indexes."""
        columns = [row[1] for row in self._conn.execute("PRAGMA table_info(allocations)").fetchall()]
        if columns and "account_id" not in columns:
            # Old shape on an already-populated DB: rebuild, preserving every
            # existing (invite-path) row with account_id NULL and
            # last_seen_at seeded from allocated_at. foreign_keys must be OFF
            # for the rename/drop and cannot be toggled inside a transaction.
            self._conn.execute("PRAGMA foreign_keys = OFF")
            try:
                with self._conn:
                    self._conn.execute("ALTER TABLE allocations RENAME TO allocations_old")
                    self._conn.executescript(_ALLOCATIONS_SCHEMA)
                    self._conn.execute(
                        "INSERT INTO allocations "
                        "(ip_address, invite_code, public_key, opnsense_client_uuid, allocated_at, account_id, last_seen_at) "
                        "SELECT ip_address, invite_code, public_key, opnsense_client_uuid, allocated_at, NULL, allocated_at "
                        "FROM allocations_old"
                    )
                    self._conn.execute("DROP TABLE allocations_old")
            finally:
                self._conn.execute("PRAGMA foreign_keys = ON")
        else:
            # Fresh DB, or already the new shape: create-if-absent is a no-op
            # once present, so this is safe to run every boot.
            self._conn.executescript(_ALLOCATIONS_SCHEMA)

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
                    "INSERT INTO allocations (ip_address, invite_code, public_key, opnsense_client_uuid, allocated_at, account_id, last_seen_at) "
                    "VALUES (?, ?, ?, ?, ?, NULL, ?)",
                    (str(ip_address), code, public_key, opnsense_client_uuid, now, now),
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

    def get_allocation_by_account_id(self, account_id: str) -> AllocationRecord | None:
        """Slice 089: return the full assertion-path allocation row for an account,
        or None. Used to answer idempotency (same-key re-redeem returns the same
        peer; different-key is rejected) without a second OPNsense call."""
        row = self._conn.execute(
            "SELECT ip_address, public_key, opnsense_client_uuid, account_id, last_seen_at "
            "FROM allocations WHERE account_id = ?",
            (account_id,),
        ).fetchone()
        return AllocationRecord(*row) if row is not None else None

    def record_assertion_redeem(
        self,
        account_id: str,
        public_key: str,
        ip_address: ipaddress.IPv4Address,
        opnsense_client_uuid: str,
        now: float | None = None,
    ) -> None:
        """Slice 089: atomically commit an assertion-path allocation (the sole
        durable-commit point for that path, exactly as redeem_invite is for the
        invite path). Callers MUST have completed the OPNsense registration
        first. Raises AccountAlreadyHasPeerError if the account already holds a
        live peer (partial unique index), or PoolExhaustedError if the address
        was taken — disambiguated by re-reading the account row."""
        now = now if now is not None else time.time()
        try:
            with self._conn:
                self._conn.execute(
                    "INSERT INTO allocations (ip_address, invite_code, public_key, opnsense_client_uuid, allocated_at, account_id, last_seen_at) "
                    "VALUES (?, NULL, ?, ?, ?, ?, ?)",
                    (str(ip_address), public_key, opnsense_client_uuid, now, account_id, now),
                )
        except sqlite3.IntegrityError as exc:
            if self.get_allocation_by_account_id(account_id) is not None:
                raise AccountAlreadyHasPeerError(account_id) from exc
            raise PoolExhaustedError(f"address {ip_address} was already allocated") from exc

    def touch_allocation_last_seen(self, account_id: str, now: float | None = None) -> None:
        """Slice 089: refresh last_seen_at for an account's peer on an idempotent
        re-redeem. No OPNsense call, no new row — just resets the aging clock."""
        now = now if now is not None else time.time()
        with self._conn:
            self._conn.execute(
                "UPDATE allocations SET last_seen_at = ? WHERE account_id = ?",
                (now, account_id),
            )

    def list_stale_account_allocations(self, older_than: float) -> list[tuple[str, str]]:
        """Slice 089: (account_id, public_key) for assertion-path peers idle since
        before `older_than`. Invite-path rows (account_id IS NULL) are never
        selected, so aging never touches operator/fallback invite peers."""
        rows = self._conn.execute(
            "SELECT account_id, public_key FROM allocations "
            "WHERE account_id IS NOT NULL AND last_seen_at < ?",
            (older_than,),
        ).fetchall()
        return [(row[0], row[1]) for row in rows]
