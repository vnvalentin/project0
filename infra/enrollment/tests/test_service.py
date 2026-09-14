"""BDD-scenario tests for infra/enrollment/service.py's EnrollmentService.redeem().

Covers every scenario in docs/slices/048-wireguard-enrollment-service.md's BDD
section: normal redemption, single-use re-redeem rejection, pool exhaustion,
invalid/expired code, malformed public key, and OPNsense failure rollback.
Also proves the private-key-never-touched invariant directly.
"""
from __future__ import annotations

import base64
import inspect
import ipaddress
import os
import time

import pytest

from infra.enrollment.config import EnrollmentConfig
from infra.enrollment.service import EnrollmentService, RedeemRejected, RedeemRejectionReason
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeOpnsenseWireguardClient

VALID_PUBLIC_KEY = base64.b64encode(bytes(range(32))).decode("ascii")
OTHER_VALID_PUBLIC_KEY = base64.b64encode(bytes(range(1, 33))).decode("ascii")


def make_config(**overrides) -> EnrollmentConfig:
    defaults = dict(
        opnsense_host="192.168.1.1",
        opnsense_api_key="test-key",
        opnsense_api_secret="test-secret",
        opnsense_ca_cert="",
        server_public_key="SERVERPUBKEY==",
        wireguard_endpoint="game.valentin.vip:51900",
        split_tunnel_allowed_ips="192.168.1.254/32",
        pool_cidr=ipaddress.ip_network("10.77.0.0/24"),
        persistent_keepalive_seconds=25,
        db_path=":memory:",
    )
    defaults.update(overrides)
    return EnrollmentConfig(**defaults)


@pytest.fixture
def store(tmp_path):
    db_path = os.path.join(str(tmp_path), "enrollment.sqlite3")
    s = EnrollmentStore(db_path)
    yield s
    s.close()


@pytest.fixture
def fake_opnsense():
    return FakeOpnsenseWireguardClient()


@pytest.fixture
def service(store, fake_opnsense):
    return EnrollmentService(make_config(), store, fake_opnsense)


def test_normal_redemption_returns_peer_bundle(service, store, fake_opnsense):
    store.mint_invite("good-code")

    bundle = service.redeem("good-code", VALID_PUBLIC_KEY)

    assert bundle.server_public_key == "SERVERPUBKEY=="
    assert bundle.endpoint == "game.valentin.vip:51900"
    assert bundle.assigned_address == "10.77.0.2/32"
    assert bundle.allowed_ips == "192.168.1.254/32"
    assert bundle.persistent_keepalive_seconds == 25
    assert len(fake_opnsense.add_client_calls) == 1
    assert fake_opnsense.reconfigure_calls == 1
    invite = store.get_invite("good-code")
    assert invite.redeemed_at is not None


def test_single_use_re_redeem_rejected(service, store, fake_opnsense):
    store.mint_invite("good-code")
    service.redeem("good-code", VALID_PUBLIC_KEY)

    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("good-code", OTHER_VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RedeemRejectionReason.INVITE_ALREADY_REDEEMED
    # No second OPNsense call and no second allocation.
    assert len(fake_opnsense.add_client_calls) == 1
    assert len(store.allocated_addresses()) == 1


def test_pool_exhausted_rejects_before_opnsense_call(store, fake_opnsense):
    tiny_pool = ipaddress.ip_network("10.77.0.0/30")  # only .1 (server) and .2 are hosts
    config = make_config(pool_cidr=tiny_pool)
    service = EnrollmentService(config, store, fake_opnsense)
    store.mint_invite("first")
    service.redeem("first", VALID_PUBLIC_KEY)  # consumes the only free address, .2

    store.mint_invite("second")
    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("second", OTHER_VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RedeemRejectionReason.POOL_EXHAUSTED
    assert len(fake_opnsense.add_client_calls) == 1  # no call for the rejected second attempt
    invite = store.get_invite("second")
    assert invite.redeemed_at is None


def test_invite_not_found_rejected(service, fake_opnsense):
    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("no-such-code", VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RedeemRejectionReason.INVITE_NOT_FOUND
    assert fake_opnsense.add_client_calls == []


def test_expired_invite_rejected(service, store, fake_opnsense):
    store.mint_invite("expired-code", expires_at=time.time() - 60)

    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("expired-code", VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RedeemRejectionReason.INVITE_EXPIRED
    assert fake_opnsense.add_client_calls == []
    invite = store.get_invite("expired-code")
    assert invite.redeemed_at is None


def test_malformed_public_key_rejected_before_allocation(service, store, fake_opnsense):
    store.mint_invite("good-code")

    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("good-code", "not-a-valid-key")

    assert exc_info.value.reason == RedeemRejectionReason.INVALID_PUBLIC_KEY
    assert fake_opnsense.add_client_calls == []
    assert store.allocated_addresses() == set()
    invite = store.get_invite("good-code")
    assert invite.redeemed_at is None


def test_opnsense_failure_rolls_back_with_no_local_allocation(store):
    failing_opnsense = FakeOpnsenseWireguardClient(fail_add_client=True)
    service = EnrollmentService(make_config(), store, failing_opnsense)
    store.mint_invite("good-code")

    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("good-code", VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RedeemRejectionReason.UPSTREAM_REGISTRATION_FAILED
    assert store.allocated_addresses() == set()
    invite = store.get_invite("good-code")
    assert invite.redeemed_at is None
    assert invite.redeemed_by_public_key is None

    # Retry succeeds once OPNsense is healthy again, proving no partial state remained.
    healthy_opnsense = FakeOpnsenseWireguardClient()
    retry_service = EnrollmentService(make_config(), store, healthy_opnsense)
    bundle = retry_service.redeem("good-code", VALID_PUBLIC_KEY)
    assert bundle.assigned_address == "10.77.0.2/32"


def test_opnsense_reconfigure_failure_also_rolls_back(store):
    failing_opnsense = FakeOpnsenseWireguardClient(fail_reconfigure=True)
    service = EnrollmentService(make_config(), store, failing_opnsense)
    store.mint_invite("good-code")

    with pytest.raises(RedeemRejected) as exc_info:
        service.redeem("good-code", VALID_PUBLIC_KEY)

    assert exc_info.value.reason == RedeemRejectionReason.UPSTREAM_REGISTRATION_FAILED
    assert store.allocated_addresses() == set()
    invite = store.get_invite("good-code")
    assert invite.redeemed_at is None


def test_private_key_never_appears_anywhere_in_the_source(service):
    """The client PRIVATE key must never be transmitted, logged, or stored.

    Since the service only ever accepts `public_key` as a request field and
    never generates or receives a private key, we prove the invariant by
    asserting no source file in this package references private-key material
    at all (no field, no log statement, no parameter).
    """
    import infra.enrollment.app as app_module
    import infra.enrollment.opnsense_client as opnsense_client_module
    import infra.enrollment.service as service_module
    import infra.enrollment.store as store_module

    for module in (service_module, app_module, opnsense_client_module, store_module):
        source = inspect.getsource(module)
        assert "private_key" not in source.lower().replace(" ", "")
        assert "privkey" not in source.lower()
