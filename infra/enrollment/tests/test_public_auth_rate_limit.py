from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.login_client import LoginAuthorityError
from infra.enrollment.rate_limit import PublicAuthRateLimiter
from infra.enrollment.service import EnrollmentService
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import (
    FakeCharacterClient,
    FakeLoginAuthorityClient,
    FakeOpnsenseWireguardClient,
)
from infra.enrollment.tests.test_service import make_config


@pytest.fixture
def store(tmp_path):
    value = EnrollmentStore(os.path.join(str(tmp_path), "e.sqlite3"))
    yield value
    value.close()


class FakeClock:
    def __init__(self) -> None:
        self.value = 100.0

    def __call__(self) -> float:
        return self.value


def _client(store, login, character, limiter) -> TestClient:
    service = EnrollmentService(make_config(), store, FakeOpnsenseWireguardClient())
    return TestClient(create_app(service, login, character, limiter))


def test_failed_login_locks_only_the_same_username_and_host(store):
    clock = FakeClock()
    login = FakeLoginAuthorityClient(fail_with_reason=LoginAuthorityError.BAD_CREDENTIALS)
    client = _client(store, login, FakeCharacterClient(), PublicAuthRateLimiter(2, 10, 5, clock))

    assert client.post("/login", json={"username": "Alice", "password": "bad"}).status_code == 401
    assert client.post("/login", json={"username": "alice", "password": "bad"}).status_code == 401
    locked = client.post("/login", json={"username": "alice", "password": "bad"})

    assert locked.status_code == 429
    assert locked.json() == {"detail": "public_auth_rate_limited"}
    assert len(login.calls) == 2


def test_login_lockout_expires_and_success_clears_failure_window(store):
    clock = FakeClock()
    login = FakeLoginAuthorityClient(fail_with_reason=LoginAuthorityError.BAD_CREDENTIALS)
    limiter = PublicAuthRateLimiter(2, 10, 5, clock)
    client = _client(store, login, FakeCharacterClient(), limiter)

    client.post("/login", json={"username": "alice", "password": "bad"})
    client.post("/login", json={"username": "alice", "password": "bad"})
    clock.value += 6
    assert client.post("/login", json={"username": "alice", "password": "bad"}).status_code == 401

    login.fail_with_reason = None
    assert client.post("/login", json={"username": "alice", "password": "good"}).status_code == 200


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        ("/characters/list", {"assertion": "token"}),
        ("/characters/create", {"assertion": "token", "name": "Hero", "cosmetic": {}}),
        ("/characters/delete", {"assertion": "token", "character_id": "c1"}),
        ("/characters/select", {"assertion": "token", "character_id": "c1"}),
    ],
)
def test_each_character_route_is_rate_limited_before_authority(store, path, payload):
    clock = FakeClock()
    character = FakeCharacterClient()
    client = _client(store, FakeLoginAuthorityClient(), character, PublicAuthRateLimiter(1, 10, 5, clock))

    assert client.post(path, json=payload).status_code == 200
    assert client.post(path, json=payload).status_code == 429
    assert len(character.calls) == 1


def test_limiter_never_stores_raw_credentials_or_assertions():
    clock = FakeClock()
    limiter = PublicAuthRateLimiter(2, 10, 5, clock)
    limiter.record_failure("login:host:alice")
    limiter.consume("characters:host")

    assert limiter._events == {"login:host:alice": [100.0], "characters:host": [100.0]}
    assert "password" not in repr(limiter._events)
    assert "token" not in repr(limiter._events)
