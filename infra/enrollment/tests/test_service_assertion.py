"""Slice 089: EnrollmentService.redeem_with_assertion + deprovision_stale_peers."""
from __future__ import annotations

import os

import pytest

from infra.enrollment.login_client import AssertionValidationError
from infra.enrollment.service import EnrollmentService, RedeemRejected, RedeemRejectionReason
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeAssertionValidationClient, FakeOpnsenseWireguardClient
from infra.enrollment.tests.test_service import OTHER_VALID_PUBLIC_KEY, VALID_PUBLIC_KEY, make_config


@pytest.fixture
def store(tmp_path):
    s = EnrollmentStore(os.path.join(str(tmp_path), "e.sqlite3"))
    yield s
    s.close()


def _service(store, opnsense, validator, **cfg):
    return EnrollmentService(make_config(**cfg), store, opnsense, validator)


def test_first_assertion_redeem_allocates_peer(store):
    opn = FakeOpnsenseWireguardClient()
    val = FakeAssertionValidationClient(account_id="acct-1")
    svc = _service(store, opn, val)

    bundle = svc.redeem_with_assertion("tok", VALID_PUBLIC_KEY)

    assert bundle.assigned_address == "10.77.0.2/32"
    assert val.calls == ["tok"]
    assert len(opn.add_client_calls) == 1
    assert store.get_allocation_by_account_id("acct-1").public_key == VALID_PUBLIC_KEY


def test_idempotent_same_key_reredeem_returns_same_peer_without_opnsense(store):
    opn = FakeOpnsenseWireguardClient()
    svc = _service(store, opn, FakeAssertionValidationClient(account_id="acct-1"))

    first = svc.redeem_with_assertion("tok", VALID_PUBLIC_KEY, now=100.0)
    second = svc.redeem_with_assertion("tok", VALID_PUBLIC_KEY, now=500.0)

    assert second.assigned_address == first.assigned_address
    assert len(opn.add_client_calls) == 1  # no second allocation
    assert store.get_allocation_by_account_id("acct-1").last_seen_at == 500.0  # touched


def test_different_key_reredeem_is_rejected(store):
    svc = _service(store, FakeOpnsenseWireguardClient(), FakeAssertionValidationClient(account_id="acct-1"))
    svc.redeem_with_assertion("tok", VALID_PUBLIC_KEY)

    with pytest.raises(RedeemRejected) as exc:
        svc.redeem_with_assertion("tok", OTHER_VALID_PUBLIC_KEY)

    assert exc.value.reason == RedeemRejectionReason.ACCOUNT_PEER_KEY_MISMATCH


def test_rejected_assertion_yields_no_allocation(store):
    opn = FakeOpnsenseWireguardClient()
    val = FakeAssertionValidationClient(fail_with_reason=AssertionValidationError.REJECTED)
    svc = _service(store, opn, val)

    with pytest.raises(RedeemRejected) as exc:
        svc.redeem_with_assertion("bad", VALID_PUBLIC_KEY)

    assert exc.value.reason == RedeemRejectionReason.ASSERTION_REJECTED
    assert len(opn.add_client_calls) == 0


def test_invalid_public_key_rejected_before_validation(store):
    val = FakeAssertionValidationClient()
    svc = _service(store, FakeOpnsenseWireguardClient(), val)

    with pytest.raises(RedeemRejected) as exc:
        svc.redeem_with_assertion("tok", "not-a-valid-key")

    assert exc.value.reason == RedeemRejectionReason.INVALID_PUBLIC_KEY
    assert val.calls == []  # never validated


def test_deprovision_stale_reclaims_only_idle_account_peers(store):
    opn = FakeOpnsenseWireguardClient()
    svc = _service(store, opn, FakeAssertionValidationClient(account_id="acct-old"), peer_idle_ttl_seconds=100)
    svc.redeem_with_assertion("tok", VALID_PUBLIC_KEY, now=1000.0)

    results = svc.deprovision_stale_peers(now=2000.0)  # threshold 1900 > last_seen 1000

    assert len(results) == 1
    assert opn.delete_client_calls  # revoked upstream
    assert store.get_allocation_by_account_id("acct-old") is None


def test_deprovision_stale_keeps_fresh_peers(store):
    opn = FakeOpnsenseWireguardClient()
    svc = _service(store, opn, FakeAssertionValidationClient(account_id="acct-1"), peer_idle_ttl_seconds=100000)
    svc.redeem_with_assertion("tok", VALID_PUBLIC_KEY, now=1000.0)

    results = svc.deprovision_stale_peers(now=1500.0)

    assert results == []
    assert store.get_allocation_by_account_id("acct-1") is not None
