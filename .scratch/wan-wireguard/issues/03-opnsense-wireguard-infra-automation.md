# 03 - OPNsense WireGuard Server and LAN-Isolation Infrastructure Automation

Status: resolved
Type: task
Blocked by: none

## Question

How will the OPNsense WireGuard server instance (port 51900 UDP, subnet 10.77.0.0/24), WAN rule, and WG interface LAN-isolation firewall rules (ALLOW 10.77.0.0/24 -> 192.168.1.254:9999 TCP/UDP; DENY WG -> LAN) be scripted idempotently via the OPNsense API in `infra/opnsense/`?

## Answer

Script `infra/opnsense/setup_wireguard_game_tunnel.py` to invoke OPNsense REST APIs (`/api/wireguard/...` and `/api/firewall/...`). The script creates WG server `wg0` on UDP 51900 with subnet `10.77.0.0/24`, adds a WAN pass rule for UDP 51900, adds a WG interface rule allowing `10.77.0.0/24` to `192.168.1.254:9999`, and adds a catch-all deny rule for `10.77.0.0/24` to `192.168.1.0/24`. All changes backup state before execution and apply `reconfigure` instantly.
