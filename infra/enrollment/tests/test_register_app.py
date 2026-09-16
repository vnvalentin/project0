from __future__ import annotations

import os

from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.service import EnrollmentService
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient, FakeOpnsenseWireguardClient
from infra.enrollment.tests.test_service import make_config


def test_register_delegates_and_returns_account(tmp_path):
    store = EnrollmentStore(os.path.join(str(tmp_path), "e.sqlite3"))
    try:
        fake = FakeLoginAuthorityClient()
        service = EnrollmentService(make_config(), store, FakeOpnsenseWireguardClient())
        response = TestClient(create_app(service, fake)).post(
            "/register", json={"username": "alice", "password": "hunter2222"}
        )
        assert response.status_code == 200
        assert response.json() == {"account_id": "acct-registered", "username": "alice"}
    finally:
        store.close()