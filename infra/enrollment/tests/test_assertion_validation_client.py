"""Unit tests for infra/enrollment/login_client.py's RealAssertionValidationClient.

Mocks urllib.request.urlopen (the transport RealAssertionValidationClient uses to
call the login authority's POST /internal/validate-assertion loopback endpoint)
so its request shape and bounded reason mapping are proven without any real
network access or a live Godot login process. The real loopback socket contract
is covered Godot-side by tests/integration/test_login_loopback_http_endpoint.gd.

Slice 089 (docs/slices/089-auth-gated-onboarding-peer-provisioning.md).
"""
from __future__ import annotations

import io
import json
from urllib.error import HTTPError, URLError

import pytest

from infra.enrollment.login_client import AssertionValidationError, RealAssertionValidationClient


def _fake_success_response(body: dict):
    from unittest import mock

    context_manager = mock.MagicMock()
    context_manager.__enter__.return_value.read.return_value = json.dumps(body).encode("utf-8")
    return context_manager


def _http_error(code: int, body: dict) -> HTTPError:
    return HTTPError(
        url="http://127.0.0.1:9997/internal/validate-assertion",
        code=code,
        msg="rejected",
        hdrs=None,
        fp=io.BytesIO(json.dumps(body).encode("utf-8")),
    )


def test_validate_sends_correct_payload_and_returns_account_and_expiry(monkeypatch):
    captured = {}

    def fake_urlopen(req, timeout):
        captured["url"] = req.full_url
        captured["method"] = req.get_method()
        captured["body"] = json.loads(req.data.decode("utf-8"))
        captured["content_type"] = req.get_header("Content-type")
        captured["timeout"] = timeout
        return _fake_success_response({"outcome": "ok", "account_id": "acct-42", "expires_at": 1893456000})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealAssertionValidationClient("127.0.0.1", 9997, 5.0)

    account_id, expires_at = client.validate("signed-token")

    assert (account_id, expires_at) == ("acct-42", 1893456000)
    assert captured["url"] == "http://127.0.0.1:9997/internal/validate-assertion"
    assert captured["method"] == "POST"
    assert captured["body"] == {"assertion": "signed-token"}
    assert captured["content_type"] == "application/json"
    assert captured["timeout"] == 5.0


def test_validate_raises_rejected_on_any_http_error(monkeypatch):
    def fake_urlopen(req, timeout):
        raise _http_error(401, {"outcome": "expired"})

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealAssertionValidationClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(AssertionValidationError) as exc_info:
        client.validate("expired-token")

    assert exc_info.value.reason == AssertionValidationError.REJECTED


def test_validate_raises_upstream_unavailable_on_connection_failure(monkeypatch):
    def fake_urlopen(req, timeout):
        raise URLError("connection refused")

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealAssertionValidationClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(AssertionValidationError) as exc_info:
        client.validate("token")

    assert exc_info.value.reason == AssertionValidationError.UPSTREAM_UNAVAILABLE


def test_validate_raises_upstream_unavailable_on_timeout(monkeypatch):
    def fake_urlopen(req, timeout):
        raise TimeoutError("timed out")

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealAssertionValidationClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(AssertionValidationError) as exc_info:
        client.validate("token")

    assert exc_info.value.reason == AssertionValidationError.UPSTREAM_UNAVAILABLE


def test_validate_raises_upstream_error_on_unexpected_success_shape(monkeypatch):
    def fake_urlopen(req, timeout):
        return _fake_success_response({"outcome": "ok", "account_id": "acct-42"})  # missing expires_at

    monkeypatch.setattr("infra.enrollment.login_client.urllib_request.urlopen", fake_urlopen)
    client = RealAssertionValidationClient("127.0.0.1", 9997, 5.0)

    with pytest.raises(AssertionValidationError) as exc_info:
        client.validate("token")

    assert exc_info.value.reason == AssertionValidationError.UPSTREAM_ERROR
