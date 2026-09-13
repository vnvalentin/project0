#!/usr/bin/env python3
"""Idempotent OPNsense automation for the isolated Project0 game WireGuard tunnel.

Provisions a dedicated WireGuard server (`project0-game`, UDP 51900,
`10.77.0.0/24`) that is split-tunneled to the authoritative game host
(`192.168.1.254:9999`) only, plus the WAN pass rule and the two WG-interface
isolation rules (allow to game host, deny to LAN). This is a second, isolated
instance alongside the existing admin WireGuard servers (instances 0 and 1,
port 51820, `10.14.0.0/24`), which this script MUST NOT touch.

Delivered for Slice 028 (docs/slices/028-wireguard-remote-access-infrastructure-foundation.md)
against decision issue 03
(.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md).
Credential handling mirrors infra/opnsense/deploy_to_opnsense.py's
`run_api_call` curl pattern. This module only ever performs writes when
invoked with --apply; --dry-run (the default) and --verify never mutate
OPNsense state.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

HOST = os.getenv("OPNSENSE_HOST", "192.168.1.1").strip()
API_BASE = f"https://{HOST}:8443/api"

GAME_WG_NAME = "project0-game"
GAME_WG_PORT = "51900"
GAME_WG_TUNNEL_ADDRESS = "10.77.0.1/24"
GAME_TUNNEL_NETWORK = ipaddress.ip_network("10.77.0.0/24")
GAME_HOST_IP = "192.168.1.254"
GAME_HOST_PORT = "9999"
LAN_NETWORK = "192.168.1.0/24"
RULE_DESCRIPTION_PREFIX = "P0-GAME:"
# The existing broad WireGuard-interface pass rule that our isolation rules
# must evaluate before. We do not modify this rule; we only ensure our two
# rules carry a lower `sequence` so the firewall evaluates them first.
EXISTING_BROAD_PASS_RULE_UUID = "20718b01"
ISOLATION_RULE_SEQUENCE = 1

BACKUP_DIR = os.path.join(os.path.expanduser("~"), "opnsense-backups")


class OpnsenseApiError(RuntimeError):
    """Raised when an OPNsense API call fails or returns an unexpected shape."""


def get_api_credentials() -> tuple[str, str]:
    api_key = os.getenv("OPNSENSE_API_KEY", "").strip()
    api_secret = os.getenv("OPNSENSE_API_SECRET", "").strip()
    if not api_key or not api_secret:
        raise RuntimeError(
            "OPNSENSE_API_KEY and OPNSENSE_API_SECRET must be set in the environment"
        )
    return api_key, api_secret


def run_api_call(
    api_key: str,
    api_secret: str,
    path: str,
    method: str = "GET",
    body: dict[str, Any] | None = None,
) -> Any:
    """Invoke one OPNsense REST endpoint via curl and parse its JSON body.

    Mirrors the credential/TLS handling in deploy_to_opnsense.py's
    `run_api_call`: HTTP basic auth with the API key/secret, an optional CA
    cert, and `-k` (insecure) when no CA cert is configured.
    """
    url = f"{API_BASE}/{path.lstrip('/')}"
    cmd = [
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "-u",
        f"{api_key}:{api_secret}",
    ]
    ca_cert = os.getenv("OPNSENSE_CA_CERT", "").strip()
    if ca_cert:
        cmd.extend(["--cacert", ca_cert])
    else:
        cmd.append("-k")
    if method != "GET":
        cmd.extend(["-X", method])
    if body is not None:
        cmd.extend(["-H", "Content-Type: application/json", "-d", json.dumps(body)])
    cmd.append(url)

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise OpnsenseApiError(
            f"OPNsense API call failed ({method} {path}): rc={result.returncode} "
            f"stderr={result.stderr.strip()}"
        )
    if not result.stdout.strip():
        raise OpnsenseApiError(f"OPNsense API call returned an empty body ({method} {path})")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise OpnsenseApiError(
            f"OPNsense API call returned non-JSON body ({method} {path}): {exc}"
        ) from exc


def snapshot_config(api_key: str, api_secret: str) -> str:
    """Download the current OPNsense config as an XML backup before any write.

    Returns the local backup file path. The download uses the same curl/auth
    plumbing as run_api_call but writes the raw response body to disk instead
    of parsing it as JSON, since this endpoint returns XML.
    """
    os.makedirs(BACKUP_DIR, exist_ok=True, mode=0o700)
    os.chmod(BACKUP_DIR, 0o700)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_path = os.path.join(BACKUP_DIR, f"config-{stamp}.xml")

    url = f"{API_BASE}/core/backup/download/this"
    cmd = [
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "-u",
        f"{api_key}:{api_secret}",
    ]
    ca_cert = os.getenv("OPNSENSE_CA_CERT", "").strip()
    if ca_cert:
        cmd.extend(["--cacert", ca_cert])
    else:
        cmd.append("-k")
    cmd.extend(["-o", backup_path, url])

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise OpnsenseApiError(
            f"OPNsense config backup failed: rc={result.returncode} stderr={result.stderr.strip()}"
        )
    os.chmod(backup_path, 0o600)
    return backup_path


def find_game_wg_server(api_key: str, api_secret: str) -> dict[str, Any] | None:
    """Return the existing project0-game WG server row, or None if absent."""
    response = run_api_call(api_key, api_secret, "wireguard/server/searchServer", method="GET")
    rows = response.get("rows", []) if isinstance(response, dict) else []
    for row in rows:
        if row.get("name") == GAME_WG_NAME:
            return row
    return None


def compute_next_free_instance(api_key: str, api_secret: str) -> int:
    """Compute the next free WireGuard server instance number.

    Instances 0 and 1 are the existing admin servers (port 51820); this
    reads every existing server's `instance` field via searchServer (whose
    flat `rows` expose `instance` as a plain value) and returns
    max(existing instances) + 1 so the new game tunnel never collides.
    """
    response = run_api_call(api_key, api_secret, "wireguard/server/searchServer", method="GET")
    rows = response.get("rows", []) if isinstance(response, dict) else []
    max_instance = -1
    for row in rows:
        try:
            instance_val = int(row.get("instance", -1))
        except (TypeError, ValueError):
            continue
        max_instance = max(max_instance, instance_val)
    return max_instance + 1


def find_existing_p0_game_rules(api_key: str, api_secret: str) -> dict[str, dict[str, Any]]:
    """Return {description: rule_row} for existing rules with the P0-GAME prefix."""
    response = run_api_call(api_key, api_secret, "firewall/filter/searchRule", method="GET")
    rows = response.get("rows", []) if isinstance(response, dict) else []
    matches = {}
    for row in rows:
        description = row.get("description", "")
        if description.startswith(RULE_DESCRIPTION_PREFIX):
            matches[description] = row
    return matches


def next_free_peer_address(api_key: str, api_secret: str) -> str:
    """Return the next free /32 address in 10.77.0.0/24, starting at .2 (.1 is the server)."""
    response = run_api_call(api_key, api_secret, "wireguard/client/searchClient", method="GET")
    rows = response.get("rows", []) if isinstance(response, dict) else []
    used_hosts: set[int] = set()
    for row in rows:
        tunnel_address = row.get("tunneladdress", "") or ""
        for entry in tunnel_address.split(","):
            entry = entry.strip()
            if not entry:
                continue
            try:
                addr = ipaddress.ip_interface(entry).ip
            except ValueError:
                continue
            if addr in GAME_TUNNEL_NETWORK:
                used_hosts.add(int(addr) - int(GAME_TUNNEL_NETWORK.network_address))

    for host_offset in range(2, GAME_TUNNEL_NETWORK.num_addresses - 1):
        if host_offset not in used_hosts:
            candidate = GAME_TUNNEL_NETWORK.network_address + host_offset
            return f"{candidate}/32"
    raise OpnsenseApiError(f"No free /32 addresses remain in {GAME_TUNNEL_NETWORK}")


def plan_server_change(api_key: str, api_secret: str) -> dict[str, Any]:
    """Compute the intended WG server create/reuse action without writing anything."""
    existing = find_game_wg_server(api_key, api_secret)
    if existing is not None:
        return {"action": "reuse", "uuid": existing.get("uuid"), "row": existing}

    next_instance = compute_next_free_instance(api_key, api_secret)
    body = {
        "server": {
            "name": GAME_WG_NAME,
            "enabled": "1",
            "port": GAME_WG_PORT,
            "tunneladdress": GAME_WG_TUNNEL_ADDRESS,
            "instance": str(next_instance),
            "disableroutes": "1",
        }
    }
    return {"action": "create", "body": body}


def generate_wg_keypair() -> tuple[str, str]:
    """Generate a WireGuard keypair locally via the wg tool.

    OPNsense's addServer API requires server.privkey (it does not auto-generate
    on create), so we mint the keypair here and submit it. Returns
    (privkey, pubkey); the private key is never logged.
    """
    priv = subprocess.run(["wg", "genkey"], capture_output=True, text=True, timeout=10)
    if priv.returncode != 0 or not priv.stdout.strip():
        raise OpnsenseApiError(f"wg genkey failed: rc={priv.returncode} stderr={priv.stderr.strip()}")
    privkey = priv.stdout.strip()
    pub = subprocess.run(["wg", "pubkey"], input=privkey, capture_output=True, text=True, timeout=10)
    if pub.returncode != 0 or not pub.stdout.strip():
        raise OpnsenseApiError(f"wg pubkey failed: rc={pub.returncode} stderr={pub.stderr.strip()}")
    return privkey, pub.stdout.strip()


def ensure_game_wg_server(api_key: str, api_secret: str) -> str:
    """Ensure the project0-game WG server exists; return its uuid."""
    plan = plan_server_change(api_key, api_secret)
    if plan["action"] == "reuse":
        return plan["uuid"]

    privkey, pubkey = generate_wg_keypair()
    body = plan["body"]
    body["server"]["privkey"] = privkey
    body["server"]["pubkey"] = pubkey
    response = run_api_call(
        api_key, api_secret, "wireguard/server/addServer", method="POST", body=body
    )
    if not isinstance(response, dict) or response.get("result") != "saved":
        raise OpnsenseApiError(f"addServer did not report success: {response}")
    uuid = response.get("uuid")
    if not uuid:
        raise OpnsenseApiError(f"addServer response missing uuid: {response}")
    return uuid


def plan_firewall_rules(api_key: str, api_secret: str, server_uuid: str) -> list[dict[str, Any]]:
    """Compute the intended firewall rule creates without writing anything."""
    existing = find_existing_p0_game_rules(api_key, api_secret)
    plans = []

    wan_desc = f"{RULE_DESCRIPTION_PREFIX} WAN UDP {GAME_WG_PORT}"
    if wan_desc not in existing:
        plans.append(
            {
                "action": "create",
                "description": wan_desc,
                "body": {
                    "rule": {
                        "interface": "wan",
                        "direction": "in",
                        "ipprotocol": "inet",
                        "protocol": "UDP",
                        "destination_port": GAME_WG_PORT,
                        "action": "pass",
                        "description": wan_desc,
                        "enabled": "1",
                    }
                },
            }
        )

    allow_desc = f"{RULE_DESCRIPTION_PREFIX} allow game host"
    if allow_desc not in existing:
        plans.append(
            {
                "action": "create",
                "description": allow_desc,
                "body": {
                    "rule": {
                        "interface": "wireguard",
                        "direction": "in",
                        "ipprotocol": "inet",
                        "protocol": "UDP",
                        "source_net": str(GAME_TUNNEL_NETWORK),
                        "destination_net": f"{GAME_HOST_IP}/32",
                        "destination_port": GAME_HOST_PORT,
                        "action": "pass",
                        "description": allow_desc,
                        "enabled": "1",
                        "sequence": str(ISOLATION_RULE_SEQUENCE),
                    }
                },
            }
        )

    deny_desc = f"{RULE_DESCRIPTION_PREFIX} deny LAN"
    if deny_desc not in existing:
        plans.append(
            {
                "action": "create",
                "description": deny_desc,
                "body": {
                    "rule": {
                        "interface": "wireguard",
                        "direction": "in",
                        "ipprotocol": "inet",
                        "source_net": str(GAME_TUNNEL_NETWORK),
                        "destination_net": LAN_NETWORK,
                        "action": "block",
                        "description": deny_desc,
                        "enabled": "1",
                        "sequence": str(ISOLATION_RULE_SEQUENCE + 1),
                    }
                },
            }
        )

    return plans


def ensure_firewall_rules(api_key: str, api_secret: str, server_uuid: str) -> list[str]:
    """Create any missing P0-GAME firewall rules and apply them. Returns created descriptions."""
    plans = plan_firewall_rules(api_key, api_secret, server_uuid)
    created = []
    for plan in plans:
        response = run_api_call(
            api_key, api_secret, "firewall/filter/addRule", method="POST", body=plan["body"]
        )
        if not isinstance(response, dict) or response.get("result") != "saved":
            raise OpnsenseApiError(f"addRule did not report success: {response}")
        created.append(plan["description"])

    if created:
        apply_response = run_api_call(api_key, api_secret, "firewall/filter/apply", method="POST")
        if not isinstance(apply_response, dict) or apply_response.get("status") is None:
            raise OpnsenseApiError(f"firewall/filter/apply did not report status: {apply_response}")
    return created


def reconfigure_wireguard(api_key: str, api_secret: str) -> None:
    response = run_api_call(api_key, api_secret, "wireguard/service/reconfigure", method="POST")
    if not isinstance(response, dict) or response.get("result") != "ok":
        raise OpnsenseApiError(f"wireguard/service/reconfigure did not report ok: {response}")


def get_server_pubkey(api_key: str, api_secret: str, server_uuid: str) -> str:
    response = run_api_call(api_key, api_secret, f"wireguard/server/getServer/{server_uuid}", method="GET")
    server = response.get("server", {}) if isinstance(response, dict) else {}
    pubkey = server.get("pubkey", "")
    if not pubkey:
        raise OpnsenseApiError("Server has no public key yet; run --apply first")
    return pubkey


def cmd_dry_run(api_key: str, api_secret: str) -> int:
    server_plan = plan_server_change(api_key, api_secret)
    if server_plan["action"] == "reuse":
        server_uuid = server_plan["uuid"]
        print(f"[dry-run] WG server '{GAME_WG_NAME}' already exists (uuid={server_uuid}); no change.")
    else:
        server_uuid = "<pending-create>"
        print(f"[dry-run] Would create WG server '{GAME_WG_NAME}':")
        print(f"  {json.dumps(server_plan['body'], indent=2)}")

    rule_plans = plan_firewall_rules(api_key, api_secret, server_uuid)
    if not rule_plans:
        print("[dry-run] All P0-GAME firewall rules already exist; no change.")
    else:
        for plan in rule_plans:
            print(f"[dry-run] Would create firewall rule '{plan['description']}':")
            print(f"  {json.dumps(plan['body'], indent=2)}")

    print("[dry-run] No writes performed.")
    return 0


def cmd_apply(api_key: str, api_secret: str) -> int:
    backup_path = snapshot_config(api_key, api_secret)
    print(f"Config snapshot saved to {backup_path}")

    server_uuid = ensure_game_wg_server(api_key, api_secret)
    print(f"WG server '{GAME_WG_NAME}' ready (uuid={server_uuid})")

    created_rules = ensure_firewall_rules(api_key, api_secret, server_uuid)
    if created_rules:
        print(f"Created firewall rules: {', '.join(created_rules)}")
    else:
        print("All P0-GAME firewall rules already present")

    reconfigure_wireguard(api_key, api_secret)
    print("WireGuard service reconfigured")
    return 0


def cmd_verify(api_key: str, api_secret: str) -> int:
    server = find_game_wg_server(api_key, api_secret)
    if server is None:
        print(f"FAIL: WG server '{GAME_WG_NAME}' does not exist")
        return 1
    print(f"OK: WG server '{GAME_WG_NAME}' exists (uuid={server.get('uuid')})")

    existing_rules = find_existing_p0_game_rules(api_key, api_secret)
    required = [
        f"{RULE_DESCRIPTION_PREFIX} WAN UDP {GAME_WG_PORT}",
        f"{RULE_DESCRIPTION_PREFIX} allow game host",
        f"{RULE_DESCRIPTION_PREFIX} deny LAN",
    ]
    missing = [desc for desc in required if desc not in existing_rules]
    if missing:
        print(f"FAIL: missing firewall rules: {', '.join(missing)}")
        return 1
    for desc in required:
        print(f"OK: firewall rule present: {desc}")

    print("VERIFY PASSED")
    return 0


def cmd_add_peer(api_key: str, api_secret: str, name: str, pubkey: str) -> int:
    server = find_game_wg_server(api_key, api_secret)
    if server is None:
        raise OpnsenseApiError(f"WG server '{GAME_WG_NAME}' does not exist; run --apply first")
    server_uuid = server["uuid"]

    tunnel_address = next_free_peer_address(api_key, api_secret)
    body = {
        "client": {
            "name": name,
            "enabled": "1",
            "pubkey": pubkey,
            "tunneladdress": tunnel_address,
            "keepalive": "25",
            "servers": server_uuid,
        }
    }
    response = run_api_call(api_key, api_secret, "wireguard/client/addClient", method="POST", body=body)
    if not isinstance(response, dict) or response.get("result") != "saved":
        raise OpnsenseApiError(f"addClient did not report success: {response}")
    client_uuid = response.get("uuid")
    if not client_uuid:
        raise OpnsenseApiError(f"addClient response missing uuid: {response}")

    existing_peers = server.get("peers", "")
    peer_list = [p for p in existing_peers.split(",") if p] if isinstance(existing_peers, str) else []
    peer_list.append(client_uuid)
    set_body = {
        "server": {
            **{k: v for k, v in server.items() if k not in ("uuid", "peers")},
            "peers": ",".join(peer_list),
        }
    }
    set_response = run_api_call(
        api_key, api_secret, f"wireguard/server/setServer/{server_uuid}", method="POST", body=set_body
    )
    if not isinstance(set_response, dict) or set_response.get("result") != "saved":
        raise OpnsenseApiError(f"setServer did not report success: {set_response}")

    reconfigure_wireguard(api_key, api_secret)

    print(f"Peer '{name}' added (uuid={client_uuid}, tunneladdress={tunnel_address})")
    return 0


def cmd_print_server_pubkey(api_key: str, api_secret: str) -> int:
    server = find_game_wg_server(api_key, api_secret)
    if server is None:
        raise OpnsenseApiError(f"WG server '{GAME_WG_NAME}' does not exist; run --apply first")
    pubkey = get_server_pubkey(api_key, api_secret, server["uuid"])
    print(pubkey)
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Idempotent OPNsense automation for the isolated Project0 game WireGuard tunnel."
    )
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument("--dry-run", action="store_true", help="Print intended changes; no writes (default).")
    mode_group.add_argument("--apply", action="store_true", help="Snapshot config, then perform writes.")
    mode_group.add_argument("--verify", action="store_true", help="Assert server and rules exist; print summary.")
    mode_group.add_argument(
        "--print-server-pubkey",
        action="store_true",
        help="Print the project0-game server's public key only.",
    )

    subparsers = parser.add_subparsers(dest="subcommand")
    add_peer = subparsers.add_parser("add-peer", help="Enroll a new WireGuard peer.")
    add_peer.add_argument("--name", required=True, help="Peer display name.")
    add_peer.add_argument("--pubkey", required=True, help="Peer WireGuard public key.")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    api_key, api_secret = get_api_credentials()

    if args.subcommand == "add-peer":
        return cmd_add_peer(api_key, api_secret, args.name, args.pubkey)

    if args.apply:
        return cmd_apply(api_key, api_secret)
    if args.verify:
        return cmd_verify(api_key, api_secret)
    if args.print_server_pubkey:
        return cmd_print_server_pubkey(api_key, api_secret)

    return cmd_dry_run(api_key, api_secret)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OpnsenseApiError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
