"""Slice 090: the enrollment service's HTTPS character routes (via FakeCharacterClient)."""
from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from infra.enrollment.app import create_app
from infra.enrollment.login_client import CharacterAuthorityError
from infra.enrollment.service import EnrollmentService
from infra.enrollment.store import EnrollmentStore
from infra.enrollment.tests.fakes import (
    FakeAssertionValidationClient,
    FakeCharacterClient,
    FakeLoginAuthorityClient,
    FakeOpnsenseWireguardClient,
)
from infra.enrollment.tests.test_service import make_config


@pytest.fixture
def store(tmp_path):
    s = EnrollmentStore(os.path.join(str(tmp_path), "e.sqlite3"))
    yield s
    s.close()


def _client(store, character_client) -> TestClient:
    service = EnrollmentService(
        make_config(), store, FakeOpnsenseWireguardClient(), FakeAssertionValidationClient()
    )
    return TestClient(create_app(service, FakeLoginAuthorityClient(), character_client))


def test_list_returns_characters(store):
    fake = FakeCharacterClient(characters=[{"character_id": "c1"}, {"character_id": "c2"}])
    client = _client(store, fake)

    response = client.post("/characters/list", json={"assertion": "tok"})

    assert response.status_code == 200
    assert response.json()["characters"] == [{"character_id": "c1"}, {"character_id": "c2"}]
    assert fake.calls[0]["assertion"] == "tok"


def test_create_returns_character(store):
    client = _client(store, FakeCharacterClient(created_character={"character_id": "c9", "display_name": "Hero"}))

    response = client.post("/characters/create", json={"assertion": "tok", "name": "Hero", "cosmetic": {}})

    assert response.status_code == 200
    assert response.json()["character"]["display_name"] == "Hero"


def test_create_name_taken_maps_to_409(store):
    client = _client(store, FakeCharacterClient(fail_with_reason="NAME_TAKEN"))

    response = client.post("/characters/create", json={"assertion": "tok", "name": "Dup", "cosmetic": {}})

    assert response.status_code == 409
    assert response.json()["detail"] == "NAME_TAKEN"


def test_select_returns_character_assertion(store):
    client = _client(store, FakeCharacterClient(selected_assertion="character-token"))

    response = client.post("/characters/select", json={"assertion": "tok", "character_id": "c1"})

    assert response.status_code == 200
    assert response.json()["assertion"] == "character-token"


def test_select_unknown_character_maps_to_404(store):
    client = _client(store, FakeCharacterClient(fail_with_reason="NO_SUCH_CHARACTER"))

    response = client.post("/characters/select", json={"assertion": "tok", "character_id": "nope"})

    assert response.status_code == 404


def test_delete_ok(store):
    client = _client(store, FakeCharacterClient())

    response = client.post("/characters/delete", json={"assertion": "tok", "character_id": "c1"})

    assert response.status_code == 200
    assert response.json()["outcome"] == "ok"


def test_bad_assertion_maps_to_401(store):
    client = _client(store, FakeCharacterClient(fail_with_reason=CharacterAuthorityError.ASSERTION_REJECTED))

    response = client.post("/characters/list", json={"assertion": "bad"})

    assert response.status_code == 401


def test_missing_assertion_rejected_by_validation(store):
    client = _client(store, FakeCharacterClient())

    response = client.post("/characters/list", json={})

    assert response.status_code == 422


def test_character_route_unavailable_when_client_not_wired(store):
    # create_app without a character client (the pre-090 two-arg call).
    service = EnrollmentService(
        make_config(), store, FakeOpnsenseWireguardClient(), FakeAssertionValidationClient()
    )
    client = TestClient(create_app(service, FakeLoginAuthorityClient()))

    response = client.post("/characters/list", json={"assertion": "tok"})

    assert response.status_code == 503
