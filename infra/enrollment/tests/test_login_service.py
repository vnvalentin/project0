"""Unit tests for infra/enrollment/login_client.py's injectable seam.

Mocks urllib.request.urlopen (the underlying transport RealLoginAuthorityClient
uses to call the login authority's loopback endpoint) so its request shape and
bounded reason mapping are proven correct without any real network access or a
live Godot login process — mirroring test_opnsense_client.py's approach of
mocking the real client's underlying transport rather than the business logic.
The real loopback socket contract itself is covered by the Godot-side GUT test
tests/integration/test_login_loopback_http_endpoint.gd.
"""
from __future__ import annotations

import io
import json
from unittest import mock
from urllib.error import HTTPError, URLError

import pytest

from infra.enrollment.login_client import LoginAuthorityError, RealLoginAuthorityClient


def _fake_success_response(body: dict):
    context_manager = mock.MagicMock()
    context_manager.__enter__.return_value.read.return_value = json.dumps(body).encode("utf-8")
    return context_manager


def _http_error(code: int, body: dict) -> HTTPError:
    return HTTPError(
        url="http://127.0.0.1:9997/internal/verify-and-mint",
        code=code,
        msg="rejected",
        hdrs=None,
        fp=io.BytesIO(json.dumps(body).encode("utf-8")),
    )


def test_verify_and_mint_sends_correct_payload_and_returns_assertion(monkeypatch):
    captured = {}

    def fake_urlopen(req, timeout):
        captured["url"] = req.full_url
        captured["method"] = req.get_method()
        captured["body"] = json.loads(req.data.decode("utf-8"))
        captured["content_type"] = req.get_header("Content-type")
        captured["timeout"] = timeout
        return _fake_success_response({"outcome": "ok", "assertion": "signed-token"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    assertion = client.verify_and_mint("alice", "hunter2222")

    assert assertion == "signed-token"
    assert captured["url"] == "http://127.0.0.1:9997/internal/verify-and-mint"
    assert captured["method"] == "POST"
    assert captured["body"] == {"username": "alice", "password": "hunter2222"}
    assert captured["content_type"] == "application/json"
    assert captured["timeout"] == 5.0


def test_verify_and_mint_raises_bad_credentials_on_401_with_bounded_reason(monkeypatch):
    def fake_urlopen(req, timeout):
        raise _http_error(401, {"outcome": "bad_credentials"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", "wrong-password")

    assert exc_info.value.reason == LoginAuthorityError.BAD_CREDENTIALS


def test_verify_and_mint_raises_malformed_on_400_with_bounded_reason(monkeypatch):
    def fake_urlopen(req, timeout):
        raise _http_error(400, {"outcome": "malformed"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", "hunter2222")

    assert exc_info.value.reason == LoginAuthorityError.MALFORMED


def test_verify_and_mint_raises_upstream_error_on_unrecognized_rejection_body(monkeypatch):
    def fake_urlopen(req, timeout):
        raise _http_error(503, {"outcome": "unavailable"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", "hunter2222")

    assert exc_info.value.reason == LoginAuthorityError.UPSTREAM_ERROR


def test_verify_and_mint_raises_upstream_unavailable_on_connection_failure(monkeypatch):
    def fake_urlopen(req, timeout):
        raise URLError("connection refused")

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", "hunter2222")

    assert exc_info.value.reason == LoginAuthorityError.UPSTREAM_UNAVAILABLE


def test_verify_and_mint_raises_upstream_unavailable_on_timeout(monkeypatch):
    def fake_urlopen(req, timeout):
        raise TimeoutError("timed out")

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", "hunter2222")

    assert exc_info.value.reason == LoginAuthorityError.UPSTREAM_UNAVAILABLE


def test_verify_and_mint_raises_upstream_error_on_malformed_success_body(monkeypatch):
    def fake_urlopen(req, timeout):
        return _fake_success_response({"outcome": "ok"})  # missing "assertion"

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", "hunter2222")

    assert exc_info.value.reason == LoginAuthorityError.UPSTREAM_ERROR


def test_verify_and_mint_never_logs_or_raises_raw_credential_material(monkeypatch, capsys):
    def fake_urlopen(req, timeout):
        raise _http_error(401, {"outcome": "bad_credentials"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealLoginAuthorityClient("127.0.0.1", 9997, 5.0)
    secret_password = "super-secret-password-value"

    with pytest.raises(LoginAuthorityError) as exc_info:
        client.verify_and_mint("alice", secret_password)

    assert secret_password not in str(exc_info.value)
    captured = capsys.readouterr()
    assert secret_password not in captured.out
    assert secret_password not in captured.err
