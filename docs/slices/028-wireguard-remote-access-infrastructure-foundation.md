# Slice 028: WireGuard remote-access infrastructure foundation
GitHub issue: #95

Status: awaiting evidence (records-first handoff; live OPNsense/host execution
owned by Copilot in a follow-up)

Tracker context: Phase 11 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
by delivering the first bounded implementation slice against its design-complete
basis. Planning ticket: [Public Game Access via WireGuard
map](../../.scratch/wan-wireguard/map.md), decisions
[03 — OPNsense infra automation](../../.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md)
and
[05 — host firewall lockdown](../../.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md).

## SDD

**Problem.** The authoritative game server at `192.168.1.254:9999` is only
reachable on the LAN today. Public play needs a remote-access path that does
not route through a cloud relay, does not grant a client OS admin/TUN
privileges, and — critically — does not hand a remote peer broader network
reach than the single game host it needs. Issue 03 and issue 05 are both
`resolved` design decisions with no implementation slice against them yet.

**Outcome.** A dedicated, isolated OPNsense WireGuard instance exists
(interface `wg0`, UDP `51900`, tunnel subnet `10.77.0.0/24`) that is
split-tunneled to `192.168.1.254:9999` only. Server-side firewall rules pass
`10.77.0.0/24 -> 192.168.1.254:9999` and default-deny
`10.77.0.0/24 -> 192.168.1.0/24` for everything else. The game host itself
independently locks down UDP `9999` to accept only from `10.77.0.0/24`,
dropping direct LAN/WAN hits, so tunnel bypass fails even if the OPNsense rule
set were ever misconfigured (defense in depth, not a single point of trust).
One Windows tester peer is enrolled by hand (no enrollment service yet) and
proves the Godot client connects end to end through the tunnel.

**Boundary.** This slice is infrastructure-provisioning only:

- OPNsense WireGuard server instance creation and its firewall rule set.
- The game host's own firewall lockdown for port 9999.
- One manually-issued Windows peer configuration.

It is explicitly **not**: the `wgnetstack` GDExtension (issue 02), the invite
enrollment service (issue 04), or revocation/ban automation (issue 06). Those
remain separately scoped, future slices against the same map.

**Public seams** (future files, authored in a follow-up handoff — not created
by this records-first slice):

- `infra/opnsense/setup_wireguard_game_tunnel.py` — idempotent OPNsense REST
  API automation: create/verify `wg0` (UDP 51900, `10.77.0.0/24`), the WAN pass
  rule for UDP 51900, the WG-interface pass rule
  `10.77.0.0/24 -> 192.168.1.254:9999`, and the WG-interface default-deny rule
  `10.77.0.0/24 -> 192.168.1.0/24`. Backs up OPNsense state before changing it
  and applies `reconfigure` so changes take effect immediately.
- `ci/host-firewall-helper.sh` — host-side lockdown on `192.168.1.254`:
  `iptables -A INPUT -p udp --dport 9999 -s 10.77.0.0/24 -j ACCEPT` followed by
  `iptables -A INPUT -p udp --dport 9999 -j DROP`.

**Invariants.**

- The existing admin WireGuard server (UDP `51820`, `10.14.0.0/24`) MUST remain
  undisturbed — this slice provisions a second, isolated instance, not a
  reconfiguration of the admin tunnel.
- Split-tunnel only: the issued peer config's `AllowedIPs` is
  `192.168.1.254/32`, never a full-tunnel `0.0.0.0/0`.
- Default-deny is server-owned (OPNsense) and independently re-asserted at the
  host (iptables), so no single misconfigured layer exposes the LAN or bypasses
  the tunnel requirement.
- No DNS dependency for this slice — the raw WAN IP `192.69.180.236` is
  acceptable; `game.valentin.vip` is not required here.

**Failure behavior.** A failed OPNsense API call or a failed iptables rule
application MUST leave no partial rule state that silently passes traffic
(fail closed); the automation script backs up state first so a bad apply can
be rolled back. This is infrastructure config, not a live gameplay code path,
so there is no server-authoritative action-resolution contract in play here.

**Rollback.** Re-run the OPNsense script's inverse/teardown path (or restore
the pre-change OPNsense backup) to remove `wg0`, its three firewall rules, and
the issued peer; remove the two host iptables rules on `192.168.1.254`. No
schema, persistence, or Canon state is touched, so rollback is a pure
infrastructure revert with no data migration.

## BDD

### External peer completes a handshake

Given the OPNsense `wg0` WireGuard instance on UDP `51900` with subnet
`10.77.0.0/24`, and a peer enrolled with a valid keypair
When the enrolled Windows peer initiates a WireGuard connection to
`192.69.180.236:51900`
Then the peer completes a WireGuard handshake and is assigned an address inside
`10.77.0.0/24`.

### Split-tunnel isolation holds from inside the tunnel

Given an active tunnel session on `10.77.0.0/24`
When the peer sends traffic to `192.168.1.254:9999`
Then it is passed and reaches the game host; when the peer sends traffic to
any other `192.168.1.0/24` LAN host
Then it is default-denied by the OPNsense WG-interface rule and does not reach
the LAN.

### Host firewall drops untunneled direct hits

Given the host lockdown on `192.168.1.254` (accept UDP 9999 only from
`10.77.0.0/24`, drop otherwise)
When a packet addressed to UDP 9999 arrives from a source outside
`10.77.0.0/24` (direct LAN or WAN, bypassing the tunnel)
Then the host firewall drops it, independent of whatever the OPNsense rule set
currently allows.

### Windows tester peer connects the Godot client

Given one Windows peer `.conf` issued with `AllowedIPs=192.168.1.254/32` and
the OPNsense/host rules applied
When the tester activates the WireGuard tunnel and launches the Godot client
pointed at `192.168.1.254:9999`
Then the client reaches the authoritative game server over the tunnel and play
is observable, while the tester's other LAN/internet traffic is unaffected
(split tunnel, not full tunnel).

### Existing admin tunnel is undisturbed

Given the pre-existing admin WireGuard server (UDP `51820`, `10.14.0.0/24`)
When the new `wg0` instance and its firewall rules are provisioned
Then the admin tunnel's interface, port, subnet, peers, and rules are
unchanged and continue to function.

## TDD / validation plan

This slice is infrastructure provisioning against live OPNsense and host
firewall state, not application/game code — there is no GDScript/GUT public
seam here. The validation evidence is operational, collected by whoever
executes the infra scripts (Copilot, in the owning follow-up), and recorded
back into this slice record once available:

- **Handshake evidence**: OPNsense WireGuard status (`wg show wg0` equivalent,
  or the OPNsense UI/API status endpoint) shows the enrolled peer with a
  recent handshake timestamp and an assigned `10.77.0.0/24` address.
- **Split-tunnel isolation evidence**: from inside the active tunnel, a probe
  to `192.168.1.254:9999` succeeds and a probe to at least one other
  `192.168.1.0/24` host/port is observed denied (connection refused/timeout
  consistent with the default-deny rule, captured from OPNsense firewall
  logs showing the block on the WG interface).
- **Host lockdown evidence**: `iptables -L INPUT -n -v` on `192.168.1.254`
  shows the accept-then-drop pair for UDP 9999 in the correct order, and a
  direct (untunneled) probe to `192.168.1.254:9999` from a LAN/WAN source is
  observed dropped.
- **Windows peer evidence**: the issued `.conf`'s `AllowedIPs=192.168.1.254/32`,
  a successful tunnel activation, and the Godot client visibly connecting to
  and playing on the server through the tunnel.
- **Non-interference evidence**: the admin tunnel's own `wg show` (port 51820 /
  `10.14.0.0/24`) is unchanged before and after.

Once `infra/opnsense/setup_wireguard_game_tunnel.py` and
`ci/host-firewall-helper.sh` are authored (follow-up handoff), their focused
validation adds: an idempotent dry-run/apply test (second run makes no further
changes), and — where a pytest harness exists for OPNsense API automation —
unit coverage of the request payloads and rollback-on-failure path. That
follow-up is expected to also produce `scripts/run_gut_validation.sh`-style
evidence for any new shared/server code; this slice introduces none.

## Validation Evidence (2026-09-13, live OPNsense/host bring-up by Copilot)

This section records verified operational evidence from the first live
execution of `infra/opnsense/setup_wireguard_game_tunnel.py --apply` and
`ci/host-firewall-helper.sh`. Status remains **awaiting evidence** — see Open
items below for the remaining blocker to done.

**OPNsense WireGuard server provisioned.** `--apply` created WG server
`project0-game` (uuid `1ade6d1a-3715-495d-b551-a6043ae3050f`, instance `2`,
UDP `51900`, tunnel `10.77.0.1/24`, `disableroutes`, enabled); server public
key `VmNN0PMAgZ4tH2RZuF8qJhJu++CWFkrLhbNPMNu2dRU=`. A full OPNsense config
snapshot was taken to `~/opnsense-backups/` before any writes, giving a
rollback point per the Rollback section above. The pre-existing admin WG
servers (instances 0 and 1, port `51820`, `10.14.0.0/24`) were left untouched,
confirming the "existing admin tunnel is undisturbed" BDD scenario.

**Firewall rule order verified correct.** Three `P0-GAME` rules were created
on the wireguard group interface and evaluate in the required order ahead of
the pre-existing broad OKAMI WireGuard full-tunnel pass:

1. `sort_order 300010.0000001` — allow `10.77.0.0/24` to
   `192.168.1.254:9999`
2. `sort_order 300010.0000002` — block `10.77.0.0/24` to `192.168.1.0/24`
3. (pre-existing) `sort_order 300010.0000324` — OKAMI WireGuard full-tunnel
   pass, evaluated after both P0-GAME rules

This satisfies the split-tunnel isolation BDD scenario's rule-ordering
requirement.

**Handshake proven.** A self-test from the host (`192.168.1.254`) using a
tester key against the LAN endpoint `192.168.1.1:51900` completed a
WireGuard handshake: `wg show` reported latest handshake 2 seconds ago,
transfer 508 B received / 564 B sent. Ping to the server tunnel IP
`10.77.0.1` returned 3/3. This satisfies the "external peer completes a
handshake" BDD scenario's handshake mechanics, from the host side.

**Peer enrolled.** Client `windows-tester`, tunnel address `10.77.0.2/32`,
uuid `4747fafd-8d3b-4d03-bab6-8bad487653b2`, enabled. A split-tunnel client
config (`Endpoint 192.69.180.236:51900`, `AllowedIPs 192.168.1.254/32`,
`PersistentKeepalive 25`) was generated to an operator-only `600` file; the
private key was never printed or committed, consistent with the split-tunnel
invariant above.

**Host firewall applied and made persistent.** `ci/host-firewall-helper.sh
apply --allow-lan` was applied on `192.168.1.254`, producing a `P0_GAME`
iptables chain: accept loopback `127.0.0.0/8`, accept udp/9999 from
`10.77.0.0/24`, accept udp/9999 from `192.168.1.0/24`, drop other udp/9999.
This was made reboot-persistent via `scripts/project0-host-firewall.service`
(systemd oneshot; active and enabled). The game server remained active/bound
throughout the change.

**Seam fixes applied during live bring-up** (already committed to the
scripts by Copilot with user authorization, not by this record):

- `compute_next_free_instance` and `next_free_peer_address` now read the flat
  `searchServer`/`searchClient` endpoints, fixing an instance-collision bug.
- `addServer` now submits a locally-generated WireGuard keypair, since
  OPNsense requires `server.privkey`.
- The host firewall helper always accepts loopback first.
- All 12 pytest cases pass.

**Open / remaining acceptance evidence (blocker to done).** The WAN path
`192.69.180.236:51900` end-to-end from a real external Windows machine, plus
an in-client Godot game connection over that path, is still pending the
actual tester — this is the "Windows tester peer connects the Godot client"
BDD scenario and remains unproven. A functional deny-LAN isolation test
(tunnel to a non-game LAN host must be blocked) is available on request;
only rule ordering has been proven so far, not an observed live packet
denial. Do not mark this slice done until the WAN-path/tester evidence lands.

## Non-goals (this slice)

- No `wgnetstack` GDExtension or in-process userspace netstack bridge (issue
  02) — the Windows tester uses a standard OS-level WireGuard client for this
  slice's proof, not the future embedded client.
- No enrollment service (issue 04) — the one tester peer is issued by hand.
- No revocation/ban automation (issue 06).
- No DNS change — `game.valentin.vip` is not required; the raw WAN IP
  `192.69.180.236` is acceptable for this slice.
- No change to the existing admin WireGuard server (UDP 51820 /
  `10.14.0.0/24`), which must remain undisturbed.
- No `infra/opnsense/setup_wireguard_game_tunnel.py` or
  `ci/host-firewall-helper.sh` code yet — this is a records-first slice; the
  scripts and any accompanying pytest are authored in a follow-up handoff.
- No live OPNsense/host network commands executed as part of producing this
  record — live execution and validation-evidence collection are owned by
  Copilot in that follow-up.
