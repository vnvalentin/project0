"""Unit tests for infra/enrollment/cli.py's invite-minting admin CLI."""
from __future__ import annotations

import os
import time

import pytest

from infra.enrollment.cli import cmd_mint_invite, generate_invite_code
from infra.enrollment.store import EnrollmentStore


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
