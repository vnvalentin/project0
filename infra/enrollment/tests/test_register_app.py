from __future__ import annotations

from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient


def test_register_delegates_and_returns_account(tmp_path):
    fake = FakeLoginAuthorityClient()
    response = TestClient(create_app(fake)).post(
        "/register", json={"username": "alice", "password": "hunter2222"}
    )
    assert response.status_code == 200
    assert response.json() == {"account_id": "acct-registered", "username": "alice"}