"""Unit tests for infra/enrollment/opnsense_client.py's injectable seam.

Mocks subprocess.run (the underlying transport used by
setup_wireguard_game_tunnel.run_api_call) so RealOpnsenseWireguardClient's
request shape is proven correct without any real network access.
"""
from __future__ import annotations

import json
from unittest import mock

import pytest

from infra.enrollment.opnsense_client import OpnsenseApiError, RealOpnsenseWireguardClient
import setup_wireguard_game_tunnel as wg


def _fake_completed_process(stdout: str, returncode: int = 0, stderr: str = ""):
    result = mock.Mock()
    result.stdout = stdout
    result.stderr = stderr
    result.returncode = returncode
    return result


class RecordingApi:
    def __init__(self, responses: dict[str, dict]):
        self.responses = responses
        self.calls: list[dict] = []

    def __call__(self, cmd, capture_output=True, text=True, timeout=30):
        url = cmd[-1]
        method = "GET"
        if "-X" in cmd:
            method = cmd[cmd.index("-X") + 1]
        body = None
        if "-d" in cmd:
            body = json.loads(cmd[cmd.index("-d") + 1])
        self.calls.append({"url": url, "method": method, "body": body})
        for path, response in self.responses.items():
            if url.endswith(path):
                return _fake_completed_process(json.dumps(response))
        raise AssertionError(f"No mocked response registered for URL: {url}")


@pytest.fixture
def no_real_subprocess(monkeypatch):
    def _boom(*args, **kwargs):
        raise AssertionError(f"Unmocked subprocess.run call: args={args} kwargs={kwargs}")

    monkeypatch.setattr(wg.subprocess, "run", _boom)


GAME_SERVER_ROW = {
    "uuid": "game-server-uuid",
    "name": "project0-game",
    "port": "51900",
    "tunneladdress": "10.77.0.1/24",
    "instance": "2",
    "peers": "",
}


def test_add_client_sends_correct_payload(monkeypatch, no_real_subprocess):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": [GAME_SERVER_ROW]},
            "wireguard/client/addClient": {"result": "saved", "uuid": "peer-uuid"},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)
    client = RealOpnsenseWireguardClient("key", "secret")

    uuid = client.add_client(
        name="invite-abc12345", public_key="PUBKEY==", tunnel_address="10.77.0.7/32", keepalive_seconds=25
    )

    assert uuid == "peer-uuid"
    add_calls = [c for c in api.calls if c["url"].endswith("wireguard/client/addClient")]
    assert len(add_calls) == 1
    payload = add_calls[0]["body"]["client"]
    assert payload["pubkey"] == "PUBKEY=="
    assert payload["tunneladdress"] == "10.77.0.7/32"
    assert payload["keepalive"] == "25"
    assert payload["servers"] == "game-server-uuid"


def test_add_client_raises_when_server_missing(monkeypatch, no_real_subprocess):
    api = RecordingApi({"wireguard/server/searchServer": {"rows": []}})
    monkeypatch.setattr(wg.subprocess, "run", api)
    client = RealOpnsenseWireguardClient("key", "secret")

    with pytest.raises(OpnsenseApiError, match="does not exist"):
        client.add_client(name="x", public_key="PUBKEY==", tunnel_address="10.77.0.7/32", keepalive_seconds=25)


def test_add_client_raises_on_unsuccessful_response(monkeypatch, no_real_subprocess):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": [GAME_SERVER_ROW]},
            "wireguard/client/addClient": {"result": "failed"},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)
    client = RealOpnsenseWireguardClient("key", "secret")

    with pytest.raises(OpnsenseApiError, match="did not report success"):
        client.add_client(name="x", public_key="PUBKEY==", tunnel_address="10.77.0.7/32", keepalive_seconds=25)


def test_reconfigure_calls_service_reconfigure(monkeypatch, no_real_subprocess):
    api = RecordingApi({"wireguard/service/reconfigure": {"result": "ok"}})
    monkeypatch.setattr(wg.subprocess, "run", api)
    client = RealOpnsenseWireguardClient("key", "secret")

    client.reconfigure()

    reconfigure_calls = [c for c in api.calls if c["url"].endswith("wireguard/service/reconfigure")]
    assert len(reconfigure_calls) == 1


def test_reconfigure_raises_on_failure(monkeypatch, no_real_subprocess):
    api = RecordingApi({"wireguard/service/reconfigure": {"result": "failed"}})
    monkeypatch.setattr(wg.subprocess, "run", api)
    client = RealOpnsenseWireguardClient("key", "secret")

    with pytest.raises(OpnsenseApiError, match="did not report ok"):
        client.reconfigure()
