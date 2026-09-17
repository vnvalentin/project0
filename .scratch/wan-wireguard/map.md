# Public Game Access via OPNsense-Native WireGuard

## Destination

Public game access for Project0 via OPNsense-native WireGuard (embedded userspace netstack GDExtension client in Godot 4.3, HTTPS invite-code enrollment service, OPNsense WireGuard API peer management, LAN-isolated firewall rules, split-tunneling `192.168.1.254:9999` on public IP `192.69.180.236` / `game.valentin.vip`).

## What Good Looks Like

- [x] The client can reach the game server through an embedded userspace WireGuard netstack without OS admin rights or a separate VPN app.
- [x] OPNsense WireGuard infrastructure and LAN isolation rules are automated and default-deny outside the game host path.
- [x] Enrollment can create least-privilege peers and return usable split-tunnel client config.
- [x] Peer revocation/ban lifecycle removes access and reclaims peer identity cleanly.
- [ ] Remaining public-edge hardening decisions, such as GeoIP/rate-limit posture, are either implemented or explicitly accepted as residual risk.

## Notes

- Domain: Networking, OPNsense, Godot GDExtension, WireGuard userspace netstack, Security & Access Control.
- Specifications: SDD-GAME-WG-001.
- Skills: `codebase-design`, `research`, `prototype`, `grilling`.
- Target environment: Server at `192.168.1.254:9999`, Public WAN IP `192.69.180.236` / `game.valentin.vip`, OPNsense router.
- Constraints: No VPS allowed; no OS admin/TUN driver on client; split-tunnel only (`192.168.1.254/32`); default deny WG->LAN.

## Decisions so far

- [01 - ENet Transport Netstack Bridging Architecture](issues/01-enet-transport-netstack-bridging.md): Adopt in-process local loopback UDP socket bridge (`127.0.0.1:<port>` -> `wireguard-go` netstack dialer). Allows native Godot `ENetMultiplayerPeer` without engine edits or OS admin rights.
- [02 - Godot GDExtension WireGuard Netstack Prototype](issues/02-godot-gdextension-wireguard-netstack.md): Compile `wireguard-go` netstack into a C-shared library GDExtension (`wgnetstack`). Ephemeral loopback port bridging runs in unprivileged userspace on Windows and Linux x64.
- [03 - OPNsense WireGuard Server and LAN-Isolation Infrastructure Automation](issues/03-opnsense-wireguard-infra-automation.md): Script `infra/opnsense/setup_wireguard_game_tunnel.py` to configure WG server `wg0` (UDP 51900, `10.77.0.0/24`), WAN pass rule, and WG->game-host pass rule (`10.77.0.0/24` -> `192.168.1.254:9999`) with default deny WG->LAN.
- [04 - Enrollment Service Invite System & OPNsense Peer API Integration](issues/04-enrollment-service-invite-system.md): Deploy FastAPI enrollment container at `https://enroll.valentin.vip`. Single-use invite code creates account, allocates `/32` IP from `10.77.0.0/24`, registers peer via OPNsense API, and returns peer config.
- [05 - Host Firewall Game Port Lockdown Script](issues/05-host-firewall-lockdown-script.md): Configure host `192.168.1.254` firewall (`iptables` / `ci/host-firewall-helper.sh`) to allow UDP 9999 only from `10.77.0.0/24` and drop all direct LAN/WAN attempts.
- [06 - Peer Revocation and Ban Lifecycle Protocol](issues/06-revocation-and-ban-lifecycle.md): Ban workflow revokes account, deletes peer via OPNsense API `/api/wireguard/client/delClient/<uuid>`, reclaims `/32` IP, and forces tunnel teardown within 1 keepalive interval.

## Not yet specified

- GeoIP allowlist region filtering for OPNsense WAN port 51900.
- Production rate-limiting / fail2ban rules for enrollment endpoint.
- Web/mobile export alternative (deferred since target is native desktop Windows/Linux).

## Out of scope

- VPS or cloud relay hosting (explicitly ruled out per SDD-GAME-WG-001; home-hosted behind OPNsense).
- Volumetric WAN DDoS mitigation beyond OPNsense rate-limiting / GeoIP (accepted residual risk per §7).
- Full-tunnel VPN capturing player internet traffic (split-tunnel game host /32 only).
- Web (HTML5) client export embedding WireGuard (sandbox prohibits raw sockets).
