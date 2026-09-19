from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from infra.operator.app import create_app
from infra.operator.jobs import AuditLog
from infra.operator.operations import OperationsService
from infra.operator.services import StatusService
from infra.operator.tests.fakes import FakePeerAdmin, FakeServiceController, FakeServiceInspector

TOKEN = "operator-secret-token"
PUBKEY = "AbCdEf0123456789AbCdEf0123456789AbCdEf01234="


def _make_client(peer_admin: FakePeerAdmin) -> TestClient:
    services = {"game-server": ("systemd", "project0-server")}
    inspector = FakeServiceInspector(systemd={"project0-server": "active"})
    operations = OperationsService(services, FakeServiceController(), AuditLog(), peer_admin=peer_admin)
    return TestClient(create_app(StatusService(services, inspector), operations, TOKEN))


def _auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def client() -> TestClient:
    return _make_client(FakePeerAdmin(outcome="REVOKED"))


def test_revoke_requires_token(client):
    assert client.post("/peers/revoke", json={"public_key": PUBKEY}).status_code == 401


def test_revoke_rejects_wrong_token(client):
    assert client.post("/peers/revoke", json={"public_key": PUBKEY}, headers={"Authorization": "Bearer wrong"}).status_code == 403


def test_revoke_empty_public_key_is_422(client):
    assert client.post("/peers/revoke", json={"public_key": "   "}, headers=_auth()).status_code == 422


def test_revoke_succeeds_and_records_operator(client):
    resp = client.post("/peers/revoke", json={"public_key": PUBKEY}, headers={**_auth(), "X-Operator": "erin"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["state"] == "succeeded"
    assert body["action"] == "revoke_peer"
    assert body["target"] == PUBKEY
    assert body["operator"] == "erin"

    jobs = client.get("/jobs", headers=_auth()).json()["jobs"]
    assert jobs[-1]["action"] == "revoke_peer"


def test_revoke_upstream_failure_reports_failed_job():
    client = _make_client(FakePeerAdmin(reject_reason="UPSTREAM_DELETE_FAILED"))
    resp = client.post("/peers/revoke", json={"public_key": PUBKEY}, headers=_auth())
    assert resp.status_code == 200
    body = resp.json()
    assert body["state"] == "failed"
    assert body["detail"] == "UPSTREAM_DELETE_FAILED"
