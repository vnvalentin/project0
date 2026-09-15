from __future__ import annotations

from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.tests.test_app import make_config
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.service import EnrollmentService
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient, FakeOpnsenseWireguardClient


def test_healthz_is_available_without_enrollment_configuration(tmp_path):
    store = EnrollmentStore(str(tmp_path / "enrollment.sqlite3"))
    service = EnrollmentService(make_config(), store, FakeOpnsenseWireguardClient())
    try:
        response = TestClient(create_app(service, FakeLoginAuthorityClient())).get("/healthz")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
    finally:
        store.close()
