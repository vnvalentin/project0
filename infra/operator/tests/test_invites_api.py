from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from infra.operator.app import create_app
from infra.operator.jobs import AuditLog
from infra.operator.operations import OperationsService
from infra.operator.services import StatusService
from infra.operator.tests.fakes import FakeInviteAdmin, FakeServiceController, FakeServiceInspector

TOKEN = "operator-secret-token"
CODE = "invite-secret-code-xyz"


@pytest.fixture
def client() -> TestClient:
    services = {"game-server": ("systemd", "project0-server")}
    inspector = FakeServiceInspector(systemd={"project0-server": "active"})
    operations = OperationsService(
        services, FakeServiceController(), AuditLog(), invite_admin=FakeInviteAdmin(code=CODE)
    )
    return TestClient(create_app(StatusService(services, inspector), operations, TOKEN))


def _auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


def test_mint_requires_token(client):
    assert client.post("/invites").status_code == 401


def test_mint_rejects_wrong_token(client):
    assert client.post("/invites", headers={"Authorization": "Bearer wrong"}).status_code == 403


def test_mint_returns_code_and_records_job(client):
    resp = client.post("/invites", json={"expires_in_seconds": 3600}, headers={**_auth(), "X-Operator": "dave"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["invite_code"] == CODE
    assert body["job"]["state"] == "succeeded"
    assert body["job"]["action"] == "mint_invite"
    assert body["job"]["operator"] == "dave"

    jobs = client.get("/jobs", headers=_auth()).json()["jobs"]
    assert len(jobs) == 1
    assert jobs[0]["action"] == "mint_invite"


def test_jobs_never_exposes_the_invite_code(client):
    client.post("/invites", headers=_auth())
    jobs_text = client.get("/jobs", headers=_auth()).text
    assert CODE not in jobs_text
