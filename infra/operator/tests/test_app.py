from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from infra.operator.app import create_app
from infra.operator.jobs import AuditLog
from infra.operator.operations import OperationsService
from infra.operator.services import StatusService
from infra.operator.tests.fakes import FakeServiceController, FakeServiceInspector

TOKEN = "operator-secret-token"


@pytest.fixture
def client() -> TestClient:
    services = {
        "game-server": ("systemd", "project0-server"),
        "dashboard": ("docker", "project0-flow"),
    }
    inspector = FakeServiceInspector(
        systemd={"project0-server": "active"},
        docker={"project0-flow": "running"},
    )
    operations = OperationsService(services, FakeServiceController(), AuditLog())
    return TestClient(create_app(StatusService(services, inspector), operations, TOKEN))


def _auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


def test_healthz_is_open(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_status_requires_token(client):
    assert client.get("/status").status_code == 401


def test_status_rejects_wrong_token(client):
    assert client.get("/status", headers={"Authorization": "Bearer wrong"}).status_code == 403


def test_status_returns_services_with_token(client):
    resp = client.get("/status", headers=_auth())
    assert resp.status_code == 200
    names = {s["name"] for s in resp.json()["services"]}
    assert names == {"game-server", "dashboard"}


def test_status_one_unknown_is_404(client):
    assert client.get("/status/nope", headers=_auth()).status_code == 404


def test_status_one_known_is_200(client):
    resp = client.get("/status/game-server", headers=_auth())
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "game-server"
    assert body["active"] is True


def test_control_rejects_unwired_gameplay_executor(client):
    response = client.post("/control", json={"action": "drain", "target": "game-server"}, headers=_auth())
    assert response.status_code == 200
    assert response.json()["reason"] == "executor_unavailable"


def test_control_routes_lifecycle_into_audited_operations(client):
    response = client.post("/control", json={"action": "restart", "target": "game-server"}, headers=_auth())
    assert response.status_code == 200
    assert response.json()["action"] == "restart"
