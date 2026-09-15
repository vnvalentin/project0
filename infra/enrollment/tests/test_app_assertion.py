"""Slice 089: /redeem dual-credential dispatch (invite OR assertion) at the route."""
from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.login_client import AssertionValidationError
from infra.enrollment.service import EnrollmentService
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import (
    FakeAssertionValidationClient,
    FakeLoginAuthorityClient,
    FakeOpnsenseWireguardClient,
)
from infra.enrollment.tests.test_service import OTHER_VALID_PUBLIC_KEY, VALID_PUBLIC_KEY, make_config


@pytest.fixture
def store(tmp_path):
    s = EnrollmentStore(os.path.join(str(tmp_path), "e.sqlite3"))
    yield s
    s.close()


def _client(store, validator=None) -> TestClient:
    service = EnrollmentService(
        make_config(), store, FakeOpnsenseWireguardClient(), validator or FakeAssertionValidationClient()
    )
    return TestClient(create_app(service, FakeLoginAuthorityClient()))


def test_redeem_with_assertion_returns_200_and_bundle(store):
    client = _client(store, FakeAssertionValidationClient(account_id="acct-1"))

    response = client.post("/redeem", json={"assertion": "tok", "public_key": VALID_PUBLIC_KEY})

    assert response.status_code == 200
    assert response.json()["assigned_address"] == "10.77.0.2/32"


def test_redeem_rejects_both_credentials_with_422(store):
    client = _client(store)
    response = client.post(
        "/redeem", json={"invite_code": "x", "assertion": "y", "public_key": VALID_PUBLIC_KEY}
    )
    assert response.status_code == 422


def test_redeem_rejects_neither_credential_with_422(store):
    client = _client(store)
    response = client.post("/redeem", json={"public_key": VALID_PUBLIC_KEY})
    assert response.status_code == 422


def test_redeem_assertion_rejected_returns_401(store):
    client = _client(store, FakeAssertionValidationClient(fail_with_reason=AssertionValidationError.REJECTED))
    response = client.post("/redeem", json={"assertion": "bad", "public_key": VALID_PUBLIC_KEY})
    assert response.status_code == 401


def test_redeem_key_mismatch_returns_409(store):
    client = _client(store, FakeAssertionValidationClient(account_id="acct-1"))
    client.post("/redeem", json={"assertion": "tok", "public_key": VALID_PUBLIC_KEY})

    response = client.post("/redeem", json={"assertion": "tok", "public_key": OTHER_VALID_PUBLIC_KEY})

    assert response.status_code == 409


def test_invite_path_still_works_unchanged(store):
    store.mint_invite("code-1")
    client = _client(store)

    response = client.post("/redeem", json={"invite_code": "code-1", "public_key": VALID_PUBLIC_KEY})

    assert response.status_code == 200
