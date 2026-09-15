"""Slice 089: cli.py deprovision-stale command."""
from __future__ import annotations

import ipaddress
import os

import pytest

from infra.enrollment.cli import cmd_deprovision_stale
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeOpnsenseWireguardClient


@pytest.fixture
def store(tmp_path):
    s = EnrollmentStore(os.path.join(str(tmp_path), "e.sqlite3"))
    yield s
    s.close()


def test_deprovision_dry_run_lists_without_revoking(store):
    store.record_assertion_redeem("acct-1", "KEY1", ipaddress.ip_address("10.77.0.2"), "uuid-1", now=100.0)
    opn = FakeOpnsenseWireguardClient()

    reclaimed = cmd_deprovision_stale(store, opn, older_than_seconds=10, dry_run=True, now=1000.0)

    assert reclaimed == ["KEY1"]
    assert opn.delete_client_calls == []  # nothing revoked in dry-run
    assert store.get_allocation_by_account_id("acct-1") is not None


def test_deprovision_revokes_stale_peers(store):
    store.record_assertion_redeem("acct-1", "KEY1", ipaddress.ip_address("10.77.0.2"), "uuid-1", now=100.0)
    opn = FakeOpnsenseWireguardClient()

    reclaimed = cmd_deprovision_stale(store, opn, older_than_seconds=10, dry_run=False, now=1000.0)

    assert reclaimed == ["KEY1"]
    assert opn.delete_client_calls == ["uuid-1"]
    assert store.get_allocation_by_account_id("acct-1") is None


def test_deprovision_skips_fresh_peers(store):
    store.record_assertion_redeem("acct-1", "KEY1", ipaddress.ip_address("10.77.0.2"), "uuid-1", now=990.0)
    opn = FakeOpnsenseWireguardClient()

    reclaimed = cmd_deprovision_stale(store, opn, older_than_seconds=100, dry_run=False, now=1000.0)

    assert reclaimed == []
    assert store.get_allocation_by_account_id("acct-1") is not None
