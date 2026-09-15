"""HTTP-contract tests for infra/enrollment/app.py's POST /login endpoint.

Uses FastAPI's TestClient with a fake LoginAuthorityClient wired directly into
create_app — no real network call, no production entrypoint invoked, matching
test_app.py's pattern for /redeem. The fake is the seam under test, not a real
socket (the real loopback socket contract is covered by the Godot-side GUT
test tests/integration/test_login_loopback_http_endpoint.gd).

Delivered for Slice 088 (docs/slices/088-auth-gated-onboarding-login-delegation.md).
"""
from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.login_client import LoginAuthorityError
from infra.enrollment.service import EnrollmentService
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient, FakeOpnsenseWireguardClient
from infra.enrollment.tests.test_app import make_config


@pytest.fixture
def store(tmp_path):
    db_path = os.path.join(str(tmp_path), "enrollment.sqlite3")
    s = EnrollmentStore(db_path)
    yield s
    s.close()


def _client(store, login_authority_client) -> TestClient:
    service = EnrollmentService(make_config(), store, FakeOpnsenseWireguardClient())
    return TestClient(create_app(service, login_authority_client))


def test_login_success_returns_200_and_assertion(store):
    fake_login_authority = FakeLoginAuthorityClient(assertion="signed-assertion-token")
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "alice", "password": "hunter2222"})

    assert response.status_code == 200
    assert response.json() == {"assertion": "signed-assertion-token"}
    assert fake_login_authority.calls == [{"username": "alice", "password": "hunter2222"}]


def test_login_bad_credentials_returns_401_not_the_fakes_internal_text(store):
    fake_login_authority = FakeLoginAuthorityClient(fail_with_reason=LoginAuthorityError.BAD_CREDENTIALS)
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "alice", "password": "wrong-password"})

    assert response.status_code == 401
    assert response.json()["detail"] == LoginAuthorityError.BAD_CREDENTIALS


def test_login_upstream_unavailable_returns_502(store):
    fake_login_authority = FakeLoginAuthorityClient(fail_with_reason=LoginAuthorityError.UPSTREAM_UNAVAILABLE)
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "alice", "password": "hunter2222"})

    assert response.status_code == 502
    assert response.json()["detail"] == LoginAuthorityError.UPSTREAM_UNAVAILABLE


def test_login_upstream_error_returns_502(store):
    fake_login_authority = FakeLoginAuthorityClient(fail_with_reason=LoginAuthorityError.UPSTREAM_ERROR)
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "alice", "password": "hunter2222"})

    assert response.status_code == 502
    assert response.json()["detail"] == LoginAuthorityError.UPSTREAM_ERROR


def test_login_missing_password_rejected_before_the_fake_is_called(store):
    fake_login_authority = FakeLoginAuthorityClient()
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "alice"})

    assert response.status_code == 422
    assert fake_login_authority.calls == []


def test_login_empty_username_rejected_before_the_fake_is_called(store):
    fake_login_authority = FakeLoginAuthorityClient()
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "", "password": "hunter2222"})

    assert response.status_code == 422
    assert fake_login_authority.calls == []


def test_login_empty_password_rejected_before_the_fake_is_called(store):
    fake_login_authority = FakeLoginAuthorityClient()
    client = _client(store, fake_login_authority)

    response = client.post("/login", json={"username": "alice", "password": ""})

    assert response.status_code == 422
    assert fake_login_authority.calls == []
