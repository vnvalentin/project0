"""BDD-scenario tests for infra/enrollment/service.py's RevocationService.

Covers every scenario in docs/slices/049-wireguard-revocation-lifecycle.md's
BDD section: revoking an active peer frees its /32, revoking an unknown or
already-revoked peer is an idempotent no-op, and both delClient and
reconfigure upstream failures are fail-closed (no local release).
"""
from __future__ import annotations

import ipaddress

import pytest

from infra.enrollment.service import (
    EnrollmentService,
    RevocationOutcome,
    RevocationRejected,
    RevocationRejectionReason,
    RevocationService,
)
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeOpnsenseWireguardClient
from infra.enrollment.tests.test_service import VALID_PUBLIC_KEY, make_config

POOL = ipaddress.ip_network("10.77.0.0/24")


@pytest.fixture
def store(tmp_path):
    import os

    db_path = os.path.join(str(tmp_path), "enrollment.sqlite3")
    s = EnrollmentStore(db_path)
    yield s
    s.close()


def _enroll_one_peer(store, fake_opnsense, public_key=VALID_PUBLIC_KEY):
    enrollment_service = EnrollmentService(make_config(), store, fake_opnsense)
    store.mint_invite("code-1")
    return enrollment_service.redeem("code-1", public_key)


def test_revoking_active_peer_succeeds_and_frees_address(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    bundle = _enroll_one_peer(store, fake_opnsense)
    assert store.get_allocation_by_public_key(VALID_PUBLIC_KEY) is not None

    reconfigure_calls_before_revoke = fake_opnsense.reconfigure_calls
    revocation_service = RevocationService(store, fake_opnsense)
    result = revocation_service.revoke(VALID_PUBLIC_KEY)

    assert result.outcome == RevocationOutcome.REVOKED
    assert fake_opnsense.delete_client_calls == ["fake-client-uuid-1"]
    assert fake_opnsense.reconfigure_calls == reconfigure_calls_before_revoke + 1
    assert store.get_allocation_by_public_key(VALID_PUBLIC_KEY) is None

    # The freed /32 is handed out again to a fresh redemption.
    store.mint_invite("code-2")
    enrollment_service = EnrollmentService(make_config(), store, fake_opnsense)
    from infra.enrollment.tests.test_service import OTHER_VALID_PUBLIC_KEY

    new_bundle = enrollment_service.redeem("code-2", OTHER_VALID_PUBLIC_KEY)
    assert new_bundle.assigned_address == bundle.assigned_address


def test_revoking_unknown_public_key_is_idempotent_noop(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    revocation_service = RevocationService(store, fake_opnsense)

    result = revocation_service.revoke("never-enrolled-key")

    assert result.outcome == RevocationOutcome.ALREADY_ABSENT
    assert fake_opnsense.delete_client_calls == []
    assert fake_opnsense.reconfigure_calls == 0

    # Repeating the call produces the identical result, with no error.
    second_result = revocation_service.revoke("never-enrolled-key")
    assert second_result.outcome == RevocationOutcome.ALREADY_ABSENT


def test_revoking_already_revoked_peer_is_idempotent_noop(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    _enroll_one_peer(store, fake_opnsense)
    revocation_service = RevocationService(store, fake_opnsense)
    first_result = revocation_service.revoke(VALID_PUBLIC_KEY)
    assert first_result.outcome == RevocationOutcome.REVOKED

    second_result = revocation_service.revoke(VALID_PUBLIC_KEY)

    assert second_result.outcome == RevocationOutcome.ALREADY_ABSENT
    # No second delete_client call for the already-gone peer.
    assert fake_opnsense.delete_client_calls == ["fake-client-uuid-1"]


def test_delclient_failure_is_fail_closed_no_local_release(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    _enroll_one_peer(store, fake_opnsense)
    failing_opnsense = FakeOpnsenseWireguardClient(fail_delete_client=True)
    # Reuse the same store; only the OPNsense client used for revoke fails.
    revocation_service = RevocationService(store, failing_opnsense)

    with pytest.raises(RevocationRejected) as exc_info:
        revocation_service.revoke(VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RevocationRejectionReason.UPSTREAM_DELETE_FAILED
    assert failing_opnsense.reconfigure_calls == 0
    allocation_uuid = store.get_allocation_by_public_key(VALID_PUBLIC_KEY)
    assert allocation_uuid == "fake-client-uuid-1"

    # Retry succeeds once OPNsense is healthy again, proving no partial state remained.
    healthy_opnsense = FakeOpnsenseWireguardClient()
    retry_service = RevocationService(store, healthy_opnsense)
    result = retry_service.revoke(VALID_PUBLIC_KEY)
    assert result.outcome == RevocationOutcome.REVOKED


def test_reconfigure_failure_after_successful_delete_is_also_fail_closed(store):
    fake_opnsense = FakeOpnsenseWireguardClient()
    _enroll_one_peer(store, fake_opnsense)
    failing_opnsense = FakeOpnsenseWireguardClient(fail_reconfigure=True)
    revocation_service = RevocationService(store, failing_opnsense)

    with pytest.raises(RevocationRejected) as exc_info:
        revocation_service.revoke(VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RevocationRejectionReason.UPSTREAM_DELETE_FAILED
    allocation_uuid = store.get_allocation_by_public_key(VALID_PUBLIC_KEY)
    assert allocation_uuid == "fake-client-uuid-1"
    assert ipaddress.ip_address("10.77.0.2") in store.allocated_addresses()
