"""HTTP-contract tests for infra/enrollment/app.py's POST /redeem endpoint.

Uses FastAPI's TestClient (backed by httpx) with a fake OPNsense client and a
temp-file sqlite store wired directly into create_app — no real network call,
no production entrypoint invoked.
"""
from __future__ import annotations

import base64
import ipaddress
import os
import time

import pytest
from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.config import EnrollmentConfig
from infra.enrollment.service import EnrollmentService
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import FakeOpnsenseWireguardClient

VALID_PUBLIC_KEY = base64.b64encode(bytes(range(32))).decode("ascii")


def make_config() -> EnrollmentConfig:
    return EnrollmentConfig(
        opnsense_host="192.168.1.1",
        opnsense_api_key="test-key",
        opnsense_api_secret="test-secret",
        opnsense_ca_cert="",
        server_public_key="SERVERPUBKEY==",
        wireguard_endpoint="game.valentin.vip:51900",
        split_tunnel_allowed_ips="192.168.1.254/32",
        pool_cidr=ipaddress.ip_network("10.77.0.0/24"),
        persistent_keepalive_seconds=25,
        db_path=":memory:",
    )


@pytest.fixture
def store(tmp_path):
    db_path = os.path.join(str(tmp_path), "enrollment.sqlite3")
    s = EnrollmentStore(db_path)
    yield s
    s.close()


@pytest.fixture
def fake_opnsense():
    return FakeOpnsenseWireguardClient()


@pytest.fixture
def client(store, fake_opnsense):
    service = EnrollmentService(make_config(), store, fake_opnsense)
    app = create_app(service)
    return TestClient(app)


def test_redeem_success_returns_200_and_bundle(client, store):
    store.mint_invite("good-code")

    response = client.post("/redeem", json={"invite_code": "good-code", "public_key": VALID_PUBLIC_KEY})

    assert response.status_code == 200
    body = response.json()
    assert body["server_public_key"] == "SERVERPUBKEY=="
    assert body["assigned_address"] == "10.77.0.2/32"
    assert body["allowed_ips"] == "192.168.1.254/32"
    assert body["endpoint"] == "game.valentin.vip:51900"


def test_redeem_unknown_code_returns_404(client):
    response = client.post("/redeem", json={"invite_code": "nope", "public_key": VALID_PUBLIC_KEY})
    assert response.status_code == 404
    assert response.json()["detail"] == "INVITE_NOT_FOUND"


def test_redeem_already_redeemed_returns_409(client, store):
    store.mint_invite("good-code")
    client.post("/redeem", json={"invite_code": "good-code", "public_key": VALID_PUBLIC_KEY})

    response = client.post("/redeem", json={"invite_code": "good-code", "public_key": VALID_PUBLIC_KEY})

    assert response.status_code == 409
    assert response.json()["detail"] == "INVITE_ALREADY_REDEEMED"


def test_redeem_expired_returns_410(client, store):
    store.mint_invite("expired-code", expires_at=time.time() - 60)

    response = client.post("/redeem", json={"invite_code": "expired-code", "public_key": VALID_PUBLIC_KEY})

    assert response.status_code == 410
    assert response.json()["detail"] == "INVITE_EXPIRED"


def test_redeem_malformed_public_key_returns_422(client, store):
    store.mint_invite("good-code")

    response = client.post("/redeem", json={"invite_code": "good-code", "public_key": "not-a-key"})

    assert response.status_code == 422
    assert response.json()["detail"] == "INVALID_PUBLIC_KEY"


def test_redeem_upstream_failure_returns_502(store):
    failing_opnsense = FakeOpnsenseWireguardClient(fail_add_client=True)
    service = EnrollmentService(make_config(), store, failing_opnsense)
    app = create_app(service)
    client = TestClient(app)
    store.mint_invite("good-code")

    response = client.post("/redeem", json={"invite_code": "good-code", "public_key": VALID_PUBLIC_KEY})

    assert response.status_code == 502
    assert response.json()["detail"] == "UPSTREAM_REGISTRATION_FAILED"


def test_redeem_missing_fields_returns_422(client):
    response = client.post("/redeem", json={"invite_code": "good-code"})
    assert response.status_code == 422
