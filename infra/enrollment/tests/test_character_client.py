"""Slice 090: unit tests for RealCharacterClient (mocks the urllib transport)."""
from __future__ import annotations

import io
import json
from unittest import mock
from urllib.error import HTTPError, URLError

import pytest

from infra.enrollment.login_client import CharacterAuthorityError, RealCharacterClient


def _ok(body: dict):
    cm = mock.MagicMock()
    cm.__enter__.return_value.read.return_value = json.dumps(body).encode("utf-8")
    return cm


def _http_error(code: int) -> HTTPError:
    return HTTPError(url="http://127.0.0.1:9997/x", code=code, msg="rejected", hdrs=None, fp=io.BytesIO(b"{}"))


def _client() -> RealCharacterClient:
    return RealCharacterClient("127.0.0.1", 9997, 5.0)


def test_list_characters_sends_assertion_and_returns_list(monkeypatch):
    captured = {}

    def fake_urlopen(req, timeout):
        captured["url"] = req.full_url
        captured["body"] = json.loads(req.data.decode("utf-8"))
        return _ok({"outcome": "ok", "characters": [{"character_id": "c1"}]})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)

    result = _client().list_characters("tok")

    assert result == [{"character_id": "c1"}]
    assert captured["url"].endswith("/internal/characters/list")
    assert captured["body"] == {"assertion": "tok"}


def test_create_returns_character(monkeypatch):
    def fake_urlopen(req, timeout):
        assert json.loads(req.data.decode("utf-8")) == {"assertion": "tok", "name": "Hero", "cosmetic": {"c": 1}}
        return _ok({"outcome": "ok", "character": {"character_id": "c9", "display_name": "Hero"}})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)

    assert _client().create_character("tok", "Hero", {"c": 1})["character_id"] == "c9"


def test_select_returns_character_assertion(monkeypatch):
    def fake_urlopen(req, timeout):
        return _ok({"outcome": "ok", "assertion": "character-token"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)

    assert _client().select_character("tok", "c1") == "character-token"


def test_delete_ok_returns_none(monkeypatch):
    monkeypatch.setattr(
        "infra.enrollment.login_client.urllib_request.urlopen", lambda req, timeout: _ok({"outcome": "ok"})
    )
    assert _client().delete_character("tok", "c1") is None


def test_domain_rejection_raises_with_bounded_reason(monkeypatch):
    monkeypatch.setattr(
        "infra.enrollment.login_client.urllib_request.urlopen",
        lambda req, timeout: _ok({"outcome": "NAME_TAKEN"}),
    )
    with pytest.raises(CharacterAuthorityError) as exc:
        _client().create_character("tok", "Hero", {})
    assert exc.value.reason == "NAME_TAKEN"


def test_http_error_raises_assertion_rejected(monkeypatch):
    def fake_urlopen(req, timeout):
        raise _http_error(401)

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    with pytest.raises(CharacterAuthorityError) as exc:
        _client().list_characters("bad")
    assert exc.value.reason == CharacterAuthorityError.ASSERTION_REJECTED


def test_connection_failure_raises_upstream_unavailable(monkeypatch):
    def fake_urlopen(req, timeout):
        raise URLError("refused")

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    with pytest.raises(CharacterAuthorityError) as exc:
        _client().select_character("tok", "c1")
    assert exc.value.reason == CharacterAuthorityError.UPSTREAM_UNAVAILABLE
