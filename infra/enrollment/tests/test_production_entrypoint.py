from __future__ import annotations

from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.tests.fakes import FakeLoginAuthorityClient


def test_healthz_is_available_without_enrollment_configuration(tmp_path):
    response = TestClient(create_app(FakeLoginAuthorityClient())).get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
