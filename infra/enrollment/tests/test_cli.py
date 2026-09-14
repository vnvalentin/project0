"""Unit tests for infra/enrollment/cli.py's invite-minting and revocation admin CLI."""
from __future__ import annotations

import os
import time

import pytest

from infra.enrollment.cli import cmd_mint_invite, cmd_revoke_peer, generate_invite_code
from infra.enrollment.service import EnrollmentService, RevocationRejected
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeOpnsenseWireguardClient
from infra.enrollment.tests.test_service import VALID_PUBLIC_KEY, make_config


@pytest.fixture
def store(tmp_path):
    db_path = os.path.join(str(tmp_path), "enrollment.sqlite3")
    s = EnrollmentStore(db_path)
    yield s
    s.close()


def test_generate_invite_code_is_high_entropy_and_unique():
    codes = {generate_invite_code() for _ in range(50)}
    assert len(codes) == 50
    for code in codes:
        assert len(code) >= 24


def test_mint_invite_persists_a_redeemable_code(store):
    code = cmd_mint_invite(store, expires_in_seconds=None)

    invite = store.get_invite(code)
    assert invite is not None
    assert invite.redeemed_at is None
    assert invite.expires_at is None


def test_mint_invite_with_expiry_records_future_expiry(store):
    before = time.time()
    code = cmd_mint_invite(store, expires_in_seconds=3600)
    after = time.time()

    invite = store.get_invite(code)
    assert invite.expires_at is not None
    assert before + 3600 <= invite.expires_at <= after + 3600


def test_revoke_peer_revokes_enrolled_peer(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    enrollment_service = EnrollmentService(make_config(), store, fake_opnsense)
    store.mint_invite("code-1")
    enrollment_service.redeem("code-1", VALID_PUBLIC_KEY)

    outcome = cmd_revoke_peer(store, fake_opnsense, VALID_PUBLIC_KEY)

    assert outcome == "REVOKED"
    assert store.get_allocation_by_public_key(VALID_PUBLIC_KEY) is None


def test_revoke_peer_on_unknown_key_is_idempotent_noop(store):
    fake_opnsense = FakeOpnsenseWireguardClient()

    outcome = cmd_revoke_peer(store, fake_opnsense, "never-enrolled-key")

    assert outcome == "ALREADY_ABSENT"


def test_revoke_peer_raises_on_upstream_failure(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    enrollment_service = EnrollmentService(make_config(), store, fake_opnsense)
    store.mint_invite("code-1")
    enrollment_service.redeem("code-1", VALID_PUBLIC_KEY)

    failing_opnsense = FakeOpnsenseWireguardClient(fail_delete_client=True)
    with pytest.raises(RevocationRejected):
        cmd_revoke_peer(store, failing_opnsense, VALID_PUBLIC_KEY)
