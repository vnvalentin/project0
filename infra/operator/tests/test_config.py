from __future__ import annotations

import pytest

from infra.operator.config import DEFAULT_AUDIT_DB_PATH, DEFAULT_SERVICES, load_config


def test_load_config_requires_token(monkeypatch):
    monkeypatch.delenv("OPERATOR_TOKEN", raising=False)
    with pytest.raises(RuntimeError):
        load_config()


def test_load_config_defaults(monkeypatch):
    monkeypatch.setenv("OPERATOR_TOKEN", "secret-token")
    monkeypatch.delenv("OPERATOR_BIND_HOST", raising=False)
    monkeypatch.delenv("OPERATOR_BIND_PORT", raising=False)
    monkeypatch.delenv("OPERATOR_AUDIT_DB_PATH", raising=False)
    config = load_config()
    assert config.bind_host == "127.0.0.1"
    assert config.bind_port == 8099
    assert config.operator_token == "secret-token"
    assert config.services == DEFAULT_SERVICES
    assert config.audit_db_path == DEFAULT_AUDIT_DB_PATH


def test_load_config_honors_audit_db_path_override(monkeypatch):
    monkeypatch.setenv("OPERATOR_TOKEN", "secret-token")
    monkeypatch.setenv("OPERATOR_AUDIT_DB_PATH", "/var/lib/project0/operator/audit.sqlite3")
    config = load_config()
    assert config.audit_db_path == "/var/lib/project0/operator/audit.sqlite3"


def test_load_config_rejects_bad_port(monkeypatch):
    monkeypatch.setenv("OPERATOR_TOKEN", "secret-token")
    monkeypatch.setenv("OPERATOR_BIND_PORT", "not-a-number")
    with pytest.raises(RuntimeError):
        load_config()
