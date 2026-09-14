"""Injectable OPNsense WireGuard peer-registration client.

`OpnsenseWireguardClient` is the seam `EnrollmentService` depends on; tests
substitute a fake so no real network call is ever made. `RealOpnsenseWireguardClient`
is the only implementation that talks to OPNsense, and it reuses
`infra/opnsense/setup_wireguard_game_tunnel.py`'s proven `run_api_call` curl
helper and `OpnsenseApiError` type rather than re-implementing HTTP/auth.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md).
"""
from __future__ import annotations

import os
import sys
from typing import Protocol

_OPNSENSE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "opnsense")
if _OPNSENSE_DIR not in sys.path:
    sys.path.insert(0, _OPNSENSE_DIR)

import setup_wireguard_game_tunnel as opnsense  # noqa: E402

OpnsenseApiError = opnsense.OpnsenseApiError


class OpnsenseWireguardClient(Protocol):
    """The interface EnrollmentService depends on. Never call this directly in a test."""

    def add_client(self, name: str, public_key: str, tunnel_address: str, keepalive_seconds: int) -> str:
        """Register a peer with OPNsense. Returns the OPNsense client uuid. Raises OpnsenseApiError on failure."""
        ...

    def reconfigure(self) -> None:
        """Apply the WireGuard service reconfiguration. Raises OpnsenseApiError on failure."""
        ...


class RealOpnsenseWireguardClient:
    """The only implementation that performs real network I/O against OPNsense."""

    def __init__(self, api_key: str, api_secret: str) -> None:
        self._api_key = api_key
        self._api_secret = api_secret

    def _server_uuid(self) -> str:
        server = opnsense.find_game_wg_server(self._api_key, self._api_secret)
        if server is None:
            raise OpnsenseApiError(
                f"WG server '{opnsense.GAME_WG_NAME}' does not exist; run setup_wireguard_game_tunnel.py --apply first"
            )
        return server["uuid"]

    def add_client(self, name: str, public_key: str, tunnel_address: str, keepalive_seconds: int) -> str:
        server_uuid = self._server_uuid()
        body = {
            "client": {
                "name": name,
                "enabled": "1",
                "pubkey": public_key,
                "tunneladdress": tunnel_address,
                "keepalive": str(keepalive_seconds),
                "servers": server_uuid,
            }
        }
        response = opnsense.run_api_call(
            self._api_key, self._api_secret, "wireguard/client/addClient", method="POST", body=body
        )
        if not isinstance(response, dict) or response.get("result") != "saved":
            raise OpnsenseApiError(f"addClient did not report success: {response}")
        client_uuid = response.get("uuid")
        if not client_uuid:
            raise OpnsenseApiError(f"addClient response missing uuid: {response}")
        return client_uuid

    def reconfigure(self) -> None:
        opnsense.reconfigure_wireguard(self._api_key, self._api_secret)
