"""Unit tests for infra/opnsense/setup_wireguard_game_tunnel.py.

All OPNsense HTTP access goes through `subprocess.run` invoking curl; every
test here mocks that call so no real network/API access ever happens. These
tests assert idempotency, exact request payload shape, next-free-instance and
next-free-peer-address computation, and that --dry-run performs zero writes.

Delivered for Slice 028
(docs/slices/028-wireguard-remote-access-infrastructure-foundation.md)
against decision issue 03
(.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md).
"""
from __future__ import annotations

import json
import os
import sys
from unittest import mock

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import setup_wireguard_game_tunnel as wg  # noqa: E402


GAME_SERVER_ROW = {
    "uuid": "game-server-uuid",
    "name": "project0-game",
    "port": "51900",
    "tunneladdress": "10.77.0.1/24",
    "instance": "2",
    "peers": "",
}

WG_SERVER_GET_TWO_ADMIN_INSTANCES = {
    "wireguard": {
        "server": {
            "servers": {
                "server": {
                    "admin0-uuid": {"instance": "0", "name": "admin-a"},
                    "admin1-uuid": {"instance": "1", "name": "admin-b"},
                }
            }
        }
    }
}

WG_SERVER_GET_WITH_GAME_INSTANCE = {
    "wireguard": {
        "server": {
            "servers": {
                "server": {
                    "admin0-uuid": {"instance": "0", "name": "admin-a"},
                    "admin1-uuid": {"instance": "1", "name": "admin-b"},
                    "game-server-uuid": {"instance": "2", "name": "project0-game"},
                }
            }
        }
    }
}


def _fake_completed_process(stdout: str, returncode: int = 0, stderr: str = ""):
    result = mock.Mock()
    result.stdout = stdout
    result.stderr = stderr
    result.returncode = returncode
    return result


@pytest.fixture
def no_real_subprocess(monkeypatch):
    """Fail loudly if any test forgets to mock subprocess.run."""

    def _boom(*args, **kwargs):
        raise AssertionError(f"Unmocked subprocess.run call: args={args} kwargs={kwargs}")

    monkeypatch.setattr(wg.subprocess, "run", _boom)


@pytest.fixture
def api_creds(monkeypatch):
    monkeypatch.setenv("OPNSENSE_API_KEY", "test-key")
    monkeypatch.setenv("OPNSENSE_API_SECRET", "test-secret")
    return wg.get_api_credentials()


class RecordingApi:
    """Routes mocked curl calls to canned JSON responses and records writes."""

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

    @property
    def writes(self):
        return [c for c in self.calls if c["method"] != "GET"]


def test_next_free_instance_computation(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi({"wireguard/server/searchServer": {"rows": [
        {"uuid": "admin0-uuid", "name": "admin-a", "instance": "0"},
        {"uuid": "admin1-uuid", "name": "admin-b", "instance": "1"},
    ]}})
    monkeypatch.setattr(wg.subprocess, "run", api)

    instance = wg.compute_next_free_instance(*api_creds)

    assert instance == 2


def test_ensure_server_creates_with_correct_payload_when_absent(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": [
                {"uuid": "admin0-uuid", "name": "admin-a", "instance": "0"},
                {"uuid": "admin1-uuid", "name": "admin-b", "instance": "1"},
            ]},
            "wireguard/server/addServer": {"result": "saved", "uuid": "new-uuid"},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)
    monkeypatch.setattr(wg, "generate_wg_keypair", lambda: ("PRIVKEY==", "PUBKEY=="))

    uuid = wg.ensure_game_wg_server(*api_creds)

    assert uuid == "new-uuid"
    add_calls = [c for c in api.calls if c["url"].endswith("wireguard/server/addServer")]
    assert len(add_calls) == 1
    payload = add_calls[0]["body"]["server"]
    assert payload["name"] == "project0-game"
    assert payload["port"] == "51900"
    assert payload["tunneladdress"] == "10.77.0.1/24"
    assert payload["disableroutes"] == "1"
    assert payload["instance"] == "2"
    assert payload["privkey"] == "PRIVKEY=="
    assert payload["pubkey"] == "PUBKEY=="


def test_ensure_server_is_idempotent_when_already_present(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi({"wireguard/server/searchServer": {"rows": [GAME_SERVER_ROW]}})
    monkeypatch.setattr(wg.subprocess, "run", api)

    uuid = wg.ensure_game_wg_server(*api_creds)

    assert uuid == "game-server-uuid"
    assert api.writes == [], "existing server must not be recreated"


def test_firewall_rules_payloads_are_correct_and_sequenced(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi(
        {
            "firewall/filter/searchRule": {"rows": []},
            "firewall/filter/addRule": {"result": "saved", "uuid": "rule-uuid"},
            "firewall/filter/apply": {"status": "ok"},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)

    created = wg.ensure_firewall_rules(*api_creds, "game-server-uuid")

    assert created == [
        "P0-GAME: WAN UDP 51900",
        "P0-GAME: allow game host",
        "P0-GAME: deny LAN",
    ]

    add_calls = [c["body"]["rule"] for c in api.calls if c["url"].endswith("firewall/filter/addRule")]
    wan_rule, allow_rule, deny_rule = add_calls

    assert wan_rule["interface"] == "wan"
    assert wan_rule["protocol"] == "UDP"
    assert wan_rule["destination_port"] == "51900"
    assert wan_rule["action"] == "pass"

    assert allow_rule["interface"] == "wireguard"
    assert allow_rule["source_net"] == "10.77.0.0/24"
    assert allow_rule["destination_net"] == "192.168.1.254/32"
    assert allow_rule["destination_port"] == "9999"
    assert allow_rule["protocol"] == "UDP"
    assert allow_rule["action"] == "pass"

    assert deny_rule["interface"] == "wireguard"
    assert deny_rule["source_net"] == "10.77.0.0/24"
    assert deny_rule["destination_net"] == "192.168.1.0/24"
    assert deny_rule["action"] == "block"

    assert int(allow_rule["sequence"]) < int(deny_rule["sequence"])
    apply_calls = [c for c in api.calls if c["url"].endswith("firewall/filter/apply")]
    assert len(apply_calls) == 1


def test_firewall_rules_idempotent_when_all_present(monkeypatch, no_real_subprocess, api_creds):
    existing_rows = [
        {"description": "P0-GAME: WAN UDP 51900"},
        {"description": "P0-GAME: allow game host"},
        {"description": "P0-GAME: deny LAN"},
    ]
    api = RecordingApi({"firewall/filter/searchRule": {"rows": existing_rows}})
    monkeypatch.setattr(wg.subprocess, "run", api)

    created = wg.ensure_firewall_rules(*api_creds, "game-server-uuid")

    assert created == []
    assert api.writes == [], "no rule or apply calls should happen when all rules already exist"


def test_peer_allocation_starts_at_dot_two_when_no_clients(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi({"wireguard/client/searchClient": {"rows": []}})
    monkeypatch.setattr(wg.subprocess, "run", api)

    address = wg.next_free_peer_address(*api_creds)

    assert address == "10.77.0.2/32"


def test_peer_allocation_skips_used_addresses(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi({"wireguard/client/searchClient": {"rows": [
        {"tunneladdress": "10.77.0.2/32"},
        {"tunneladdress": "10.77.0.3/32"},
    ]}})
    monkeypatch.setattr(wg.subprocess, "run", api)

    address = wg.next_free_peer_address(*api_creds)

    assert address == "10.77.0.4/32"


def test_dry_run_performs_zero_writes(monkeypatch, no_real_subprocess, api_creds, capsys):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": []},
            "firewall/filter/searchRule": {"rows": []},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)

    exit_code = wg.cmd_dry_run(*api_creds)

    assert exit_code == 0
    assert api.writes == [], "dry-run must never write"
    for call in api.calls:
        assert call["method"] == "GET"


def test_main_defaults_to_dry_run_with_zero_writes(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": [GAME_SERVER_ROW]},
            "firewall/filter/searchRule": {"rows": []},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)

    exit_code = wg.main([])

    assert exit_code == 0
    assert api.writes == []


def test_add_peer_links_client_into_server_and_reconfigures(monkeypatch, no_real_subprocess, api_creds):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": [GAME_SERVER_ROW]},
            "wireguard/client/searchClient": {"rows": []},
            "wireguard/client/addClient": {"result": "saved", "uuid": "peer-uuid"},
            f"wireguard/server/setServer/{GAME_SERVER_ROW['uuid']}": {"result": "saved"},
            "wireguard/service/reconfigure": {"result": "ok"},
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)

    exit_code = wg.cmd_add_peer(*api_creds, "tester-windows", "fakepubkey==")

    assert exit_code == 0
    add_client_calls = [c for c in api.calls if c["url"].endswith("wireguard/client/addClient")]
    assert len(add_client_calls) == 1
    client_payload = add_client_calls[0]["body"]["client"]
    assert client_payload["name"] == "tester-windows"
    assert client_payload["pubkey"] == "fakepubkey=="
    assert client_payload["tunneladdress"] == "10.77.0.2/32"
    assert client_payload["keepalive"] == "25"
    assert client_payload["servers"] == GAME_SERVER_ROW["uuid"]

    set_server_calls = [
        c for c in api.calls if c["url"].endswith(f"wireguard/server/setServer/{GAME_SERVER_ROW['uuid']}")
    ]
    assert len(set_server_calls) == 1
    assert "peer-uuid" in set_server_calls[0]["body"]["server"]["peers"]

    reconfigure_calls = [c for c in api.calls if c["url"].endswith("wireguard/service/reconfigure")]
    assert len(reconfigure_calls) == 1


def test_missing_credentials_raise_clear_error(monkeypatch):
    monkeypatch.delenv("OPNSENSE_API_KEY", raising=False)
    monkeypatch.delenv("OPNSENSE_API_SECRET", raising=False)

    with pytest.raises(RuntimeError, match="OPNSENSE_API_KEY"):
        wg.get_api_credentials()


def test_print_server_pubkey_never_prints_private_key(monkeypatch, no_real_subprocess, api_creds, capsys):
    api = RecordingApi(
        {
            "wireguard/server/searchServer": {"rows": [GAME_SERVER_ROW]},
            f"wireguard/server/getServer/{GAME_SERVER_ROW['uuid']}": {
                "server": {"pubkey": "PUBLICKEY==", "privkey": "SECRETPRIVATEKEY=="}
            },
        }
    )
    monkeypatch.setattr(wg.subprocess, "run", api)

    exit_code = wg.cmd_print_server_pubkey(*api_creds)

    assert exit_code == 0
    captured = capsys.readouterr()
    assert "PUBLICKEY==" in captured.out
    assert "SECRETPRIVATEKEY==" not in captured.out
