from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from infra.operator.app import create_app
from infra.operator.jobs import AuditLog
from infra.operator.operations import OperationsService
from infra.operator.services import StatusService
from infra.operator.tests.fakes import FakeServiceController, FakeServiceInspector

TOKEN = "operator-secret-token"


def _services() -> dict[str, tuple[str, str]]:
    return {
        "game-server": ("systemd", "project0-server"),
        "dashboard": ("docker", "project0-flow"),
    }


def _make_client(controller: FakeServiceController) -> TestClient:
    services = _services()
    inspector = FakeServiceInspector(systemd={"project0-server": "active"}, docker={"project0-flow": "running"})
    operations = OperationsService(services, controller, AuditLog())
    return TestClient(create_app(StatusService(services, inspector), operations, TOKEN))


def _auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def client() -> TestClient:
    return _make_client(FakeServiceController())


def test_restart_requires_token(client):
    assert client.post("/services/game-server/restart").status_code == 401


def test_restart_rejects_wrong_token(client):
    assert client.post("/services/game-server/restart", headers={"Authorization": "Bearer wrong"}).status_code == 403


def test_restart_unknown_service_is_404(client):
    assert client.post("/services/nope/restart", headers=_auth()).status_code == 404


def test_restart_known_service_succeeds_and_records_operator(client):
    headers = {**_auth(), "X-Operator": "carol"}
    resp = client.post("/services/game-server/restart", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["state"] == "succeeded"
    assert body["action"] == "restart"
    assert body["target"] == "game-server"
    assert body["operator"] == "carol"

    jobs = client.get("/jobs", headers=_auth()).json()["jobs"]
    assert len(jobs) == 1
    assert jobs[0]["job_id"] == body["job_id"]


def test_restart_controller_failure_reports_failed_job():
    client = _make_client(FakeServiceController(systemd_ok=False))
    resp = client.post("/services/game-server/restart", headers=_auth())
    assert resp.status_code == 200
    body = resp.json()
    assert body["state"] == "failed"
    assert body["detail"] == "systemd boom"


@pytest.mark.parametrize("action", ["start", "stop"])
def test_lifecycle_action_requires_token(client, action):
    assert client.post(f"/services/game-server/{action}").status_code == 401


@pytest.mark.parametrize("action", ["start", "stop"])
def test_lifecycle_action_unknown_service_is_404(client, action):
    assert client.post(f"/services/nope/{action}", headers=_auth()).status_code == 404


@pytest.mark.parametrize("action", ["start", "stop"])
def test_lifecycle_action_succeeds_and_audits(client, action):
    resp = client.post(f"/services/game-server/{action}", headers={**_auth(), "X-Operator": "carol"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["state"] == "succeeded"
    assert body["action"] == action
    assert body["operator"] == "carol"
    jobs = client.get("/jobs", headers=_auth()).json()["jobs"]
    assert jobs[-1]["job_id"] == body["job_id"]


def test_jobs_requires_token(client):
    assert client.get("/jobs").status_code == 401
