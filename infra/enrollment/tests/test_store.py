"""Unit tests for infra/enrollment/store.py's sqlite-backed invite/allocation store."""
from __future__ import annotations

import ipaddress
import os
import time

import pytest

from infra.enrollment.store import (
    EnrollmentStore,
    InviteAlreadyRedeemedError,
    PoolExhaustedError,
)

POOL = ipaddress.ip_network("10.77.0.0/24")
SERVER_ADDR = ipaddress.ip_address("10.77.0.1")


@pytest.fixture
def store(tmp_path):
    db_path = os.path.join(str(tmp_path), "enrollment.sqlite3")
    s = EnrollmentStore(db_path)
    yield s
    s.close()


def test_mint_and_get_invite(store):
    store.mint_invite("code-1")
    invite = store.get_invite("code-1")
    assert invite is not None
    assert invite.code == "code-1"
    assert invite.redeemed_at is None
    assert invite.expires_at is None


def test_get_missing_invite_returns_none(store):
    assert store.get_invite("does-not-exist") is None


def test_next_free_address_excludes_network_server_and_broadcast(store):
    excluded = {POOL.network_address, SERVER_ADDR, POOL.broadcast_address}
    address = store.next_free_address(POOL, excluded)
    assert address == ipaddress.ip_address("10.77.0.2")


def test_next_free_address_skips_allocated(store):
    store.mint_invite("code-1")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.2"),
        opnsense_client_uuid="uuid-1",
    )
    excluded = {POOL.network_address, SERVER_ADDR, POOL.broadcast_address}
    address = store.next_free_address(POOL, excluded)
    assert address == ipaddress.ip_address("10.77.0.3")


def test_pool_exhaustion_raises(store):
    tiny_pool = ipaddress.ip_network("10.77.0.0/30")  # hosts: .1, .2
    excluded = {tiny_pool.network_address, ipaddress.ip_address("10.77.0.1"), tiny_pool.broadcast_address}
    store.mint_invite("code-1")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.2"),
        opnsense_client_uuid="uuid-1",
    )
    with pytest.raises(PoolExhaustedError):
        store.next_free_address(tiny_pool, excluded)


def test_redeem_invite_atomically_commits_both_rows(store):
    store.mint_invite("code-1")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.5"),
        opnsense_client_uuid="uuid-1",
    )
    invite = store.get_invite("code-1")
    assert invite.redeemed_at is not None
    assert invite.redeemed_by_public_key == "PUBKEY1"
    assert ipaddress.ip_address("10.77.0.5") in store.allocated_addresses()


def test_redeem_invite_twice_raises_and_keeps_single_allocation(store):
    store.mint_invite("code-1")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.5"),
        opnsense_client_uuid="uuid-1",
    )
    with pytest.raises(InviteAlreadyRedeemedError):
        store.redeem_invite(
            code="code-1",
            public_key="PUBKEY2",
            ip_address=ipaddress.ip_address("10.77.0.6"),
            opnsense_client_uuid="uuid-2",
        )
    assert len(store.allocated_addresses()) == 1


def test_redeem_invite_rollback_leaves_no_allocation_on_duplicate_address(store):
    store.mint_invite("code-1")
    store.mint_invite("code-2")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.5"),
        opnsense_client_uuid="uuid-1",
    )
    with pytest.raises(PoolExhaustedError):
        store.redeem_invite(
            code="code-2",
            public_key="PUBKEY2",
            ip_address=ipaddress.ip_address("10.77.0.5"),
            opnsense_client_uuid="uuid-2",
        )
    # code-2 must remain unredeemed since its transaction rolled back.
    invite_2 = store.get_invite("code-2")
    assert invite_2.redeemed_at is None
    assert len(store.allocated_addresses()) == 1


def test_mint_invite_with_expiry(store):
    expires_at = time.time() + 3600
    store.mint_invite("code-exp", expires_at=expires_at)
    invite = store.get_invite("code-exp")
    assert invite.expires_at == expires_at


def test_get_allocation_by_public_key_returns_uuid(store):
    store.mint_invite("code-1")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.5"),
        opnsense_client_uuid="uuid-1",
    )
    assert store.get_allocation_by_public_key("PUBKEY1") == "uuid-1"


def test_get_allocation_by_public_key_returns_none_when_absent(store):
    assert store.get_allocation_by_public_key("no-such-key") is None


def test_release_allocation_by_public_key_deletes_row_and_returns_uuid(store):
    store.mint_invite("code-1")
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=ipaddress.ip_address("10.77.0.5"),
        opnsense_client_uuid="uuid-1",
    )

    released_uuid = store.release_allocation_by_public_key("PUBKEY1")

    assert released_uuid == "uuid-1"
    assert ipaddress.ip_address("10.77.0.5") not in store.allocated_addresses()
    assert store.get_allocation_by_public_key("PUBKEY1") is None


def test_release_allocation_by_public_key_is_noop_when_absent(store):
    assert store.release_allocation_by_public_key("no-such-key") is None
    assert store.allocated_addresses() == set()


def test_released_address_is_handed_out_again(store):
    store.mint_invite("code-1")
    excluded = {POOL.network_address, SERVER_ADDR, POOL.broadcast_address}
    address = store.next_free_address(POOL, excluded)
    store.redeem_invite(
        code="code-1",
        public_key="PUBKEY1",
        ip_address=address,
        opnsense_client_uuid="uuid-1",
    )

    store.release_allocation_by_public_key("PUBKEY1")

    reallocated = store.next_free_address(POOL, excluded)
    assert reallocated == address
