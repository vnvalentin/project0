"""Slice 089: store tests for the assertion-path allocation schema, migration,
and idempotent per-account lifecycle methods."""
from __future__ import annotations

import ipaddress
import os
import sqlite3

import pytest

from infra.enrollment.store import AccountAlreadyHasPeerError, EnrollmentStore

_OLD_SCHEMA = """
CREATE TABLE invites (
    code TEXT PRIMARY KEY, created_at REAL NOT NULL, expires_at REAL,
    redeemed_at REAL, redeemed_by_public_key TEXT
);
CREATE TABLE allocations (
    ip_address TEXT PRIMARY KEY,
    invite_code TEXT NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    opnsense_client_uuid TEXT NOT NULL,
    allocated_at REAL NOT NULL,
    FOREIGN KEY (invite_code) REFERENCES invites (code)
);
"""


def _seed_old_shape_db(path: str) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(_OLD_SCHEMA)
    conn.execute(
        "INSERT INTO invites (code, created_at, expires_at, redeemed_at, redeemed_by_public_key) "
        "VALUES ('old-code', 1000.0, NULL, 1000.0, 'OLDKEY')"
    )
    conn.execute(
        "INSERT INTO allocations (ip_address, invite_code, public_key, opnsense_client_uuid, allocated_at) "
        "VALUES ('10.77.0.2', 'old-code', 'OLDKEY', 'old-uuid', 1000.0)"
    )
    conn.commit()
    conn.close()


@pytest.fixture
def store(tmp_path):
    s = EnrollmentStore(os.path.join(str(tmp_path), "enroll.sqlite3"))
    yield s
    s.close()


def test_migration_preserves_invite_row_and_is_idempotent(tmp_path):
    db = os.path.join(str(tmp_path), "enroll.sqlite3")
    _seed_old_shape_db(db)

    first = EnrollmentStore(db)  # runs the migration
    # The pre-existing invite-path row survives with its uuid, and the new
    # account_id column now exists (get_allocation_by_account_id would raise
    # otherwise) with the old row's account_id NULL (never matched).
    assert first.get_allocation_by_public_key("OLDKEY") == "old-uuid"
    assert first.get_allocation_by_account_id("OLDKEY") is None
    first.close()

    # A second boot against the migrated DB must not raise and must preserve data.
    second = EnrollmentStore(db)
    assert second.get_allocation_by_public_key("OLDKEY") == "old-uuid"
    second.close()


def test_record_and_get_assertion_allocation(store):
    store.record_assertion_redeem("acct-1", "KEY1", ipaddress.ip_address("10.77.0.2"), "uuid-1", now=100.0)
    record = store.get_allocation_by_account_id("acct-1")
    assert record is not None
    assert (record.ip_address, record.public_key, record.opnsense_client_uuid) == ("10.77.0.2", "KEY1", "uuid-1")
    assert record.account_id == "acct-1"
    assert record.last_seen_at == 100.0


def test_duplicate_account_id_raises_account_already_has_peer(store):
    store.record_assertion_redeem("acct-1", "KEY1", ipaddress.ip_address("10.77.0.2"), "uuid-1")
    with pytest.raises(AccountAlreadyHasPeerError):
        store.record_assertion_redeem("acct-1", "KEY2", ipaddress.ip_address("10.77.0.3"), "uuid-2")


def test_touch_updates_last_seen(store):
    store.record_assertion_redeem("acct-1", "KEY1", ipaddress.ip_address("10.77.0.2"), "uuid-1", now=100.0)
    store.touch_allocation_last_seen("acct-1", now=500.0)
    assert store.get_allocation_by_account_id("acct-1").last_seen_at == 500.0


def test_list_stale_selects_only_idle_assertion_rows(store):
    store.record_assertion_redeem("acct-old", "KEYOLD", ipaddress.ip_address("10.77.0.2"), "uuid-old", now=100.0)
    store.record_assertion_redeem("acct-new", "KEYNEW", ipaddress.ip_address("10.77.0.3"), "uuid-new", now=1000.0)
    # An invite-path row (account_id NULL) must never be selected by aging.
    store.mint_invite("inv")
    store.redeem_invite("inv", "INVKEY", ipaddress.ip_address("10.77.0.4"), "uuid-inv", now=100.0)

    stale = store.list_stale_account_allocations(older_than=500.0)

    assert stale == [("acct-old", "KEYOLD")]
