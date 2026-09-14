from __future__ import annotations

import pytest

from infra.operator.config import DEFAULT_SERVICES, load_config


def test_load_config_requires_token(monkeypatch):
    monkeypatch.delenv("OPERATOR_TOKEN", raising=False)
    with pytest.raises(RuntimeError):
        load_config()


def test_load_config_defaults(monkeypatch):
    monkeypatch.setenv("OPERATOR_TOKEN", "secret-token")
    monkeypatch.delenv("OPERATOR_BIND_HOST", raising=False)
    monkeypatch.delenv("OPERATOR_BIND_PORT", raising=False)
    config = load_config()
    assert config.bind_host == "127.0.0.1"
    assert config.bind_port == 8099
    assert config.operator_token == "secret-token"
    assert config.services == DEFAULT_SERVICES


def test_load_config_rejects_bad_port(monkeypatch):
    monkeypatch.setenv("OPERATOR_TOKEN", "secret-token")
    monkeypatch.setenv("OPERATOR_BIND_PORT", "not-a-number")
    with pytest.raises(RuntimeError):
        load_config()
