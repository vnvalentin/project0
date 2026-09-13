# Slice 032: In-client wgnetstack netstack bridge (Linux prototype)

Status: delivered (Linux prototype validated end to end; the Godot client
reaches `connected: player spawned` through the bridge against the live
server — see Validation Evidence below)

Tracker context: Phase 13 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
by delivering S2 of the netstack-bridge design: a real `wireguard-go` userspace
netstack bridge proven on Linux, ahead of the Windows DLL validation (S3) and
`.gdextension` packaging (S3). Planning ticket:
[Public Game Access via WireGuard map](../../.scratch/wan-wireguard/map.md),
decisions
[01 — ENet transport netstack bridging](../../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md)
and
[02 — Godot GDExtension WireGuard netstack prototype](../../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md).
Builds on
[Slice 028](028-wireguard-remote-access-infrastructure-foundation.md), which
proved the OPNsense `wg0` tunnel, firewall isolation, and one hand-issued
Windows peer config using a stock OS-level WireGuard client.

## SDD

**Problem.** Slice 028 proved the WireGuard infrastructure end to end, but the
tester still needs a separate, OS-level WireGuard client app to activate the
tunnel before launching Godot. Issue 02's resolved decision calls for an
in-client userspace netstack bridge so a tester only ever runs the game. No
implementation exists yet.

**Outcome.** A standalone Go module, `native/wgnetstack/`, embeds
`golang.zx2c4.com/wireguard`'s netstack device (gVisor-backed, no OS TUN, no
admin rights) and bridges a real loopback UDP socket to the game host through
the tunnel. It is proven, on Linux only, that the existing Godot client's
native `ENetMultiplayerPeer.create_client("127.0.0.1", <port>)` reaches the
live authoritative server at `192.168.1.254:9999` through this bridge, using
the same tester identity Slice 028 already enrolled
(`10.77.0.2/32`, peer public key `VmNN0PMAgZ4tH2RZuF8qJhJu++CWFkrLhbNPMNu2dRU=`,
LAN endpoint `192.168.1.1:51900` for this prototype).

**Boundary — in scope for S2:**

- The `native/wgnetstack/` Go module: netstack device construction, `IpcSet`
  configuration from hex-converted keys, the loopback↔netstack UDP bridge, and
  the two C-exported functions used to drive it from a host process.
- A `cmd/probe` standalone Go harness that runs the bridge without Godot, for
  fast iteration and as the fallback proof path.
- A Linux `libwgnetstack.so` build and its live proof against the real
  OPNsense tunnel and the real game server.
- A Makefile/build script whose Windows cross-compile target is present and
  buildable in shape, but not run or validated in this slice.

**Non-goals (this slice, S2 — deferred to S3/S4):**

- Validating the Windows `wgnetstack.dll` build on a Windows host (S3).
- The Godot `.gdextension` resource, godot-cpp bindings, or any GDScript
  calling into this library (S3). Slice 028's stock OS-level WireGuard client
  remains the only proven Godot-facing path until S3 lands.
- Invite/enrollment automation or key provisioning (S4) — this slice reads a
  key file that Slice 028 already placed by hand
  (`/home/vic/p0-wg-testers/windows-tester.key`).
- Any change to OPNsense config, host firewall rules, or the admin WireGuard
  tunnel — all provisioned and verified unchanged by Slice 028.
- Reconnect/roaming, multiple simultaneous peers through one bridge instance,
  or telemetry beyond basic start/stop logging.

**Public seam.** `native/wgnetstack/` as a Go module producing
`build/libwgnetstack.so` (Linux, `c-shared`) with two C-exported entry points:

```c
int  wgnetstack_start(const char* config_json); // returns loopback port, or -1
void wgnetstack_stop(void);
```

`config_json` carries `client_private_key_path` (a file path, never an inline
key), `client_address` (`10.77.0.2/32`), `mtu` (1420), `server_public_key`,
`server_endpoint` (`host:port`), `persistent_keepalive_interval` (25), and
`game_host` (`host:port`). The library never accepts a raw private key value
over this boundary — only a path it reads at runtime — matching the
Engineering Constitution's rule that the LLM/config layer proposes untrusted
input and the server-owned (here: bridge-owned) process is what actually reads
secrets.

**Invariants.**

- The client private key is read from disk at `wgnetstack_start` time and is
  never hardcoded, logged, or embedded in the binary or its build artifacts.
- The bridge opens a real loopback UDP socket on `127.0.0.1:0` (ephemeral) and
  a real netstack UDP dial to the configured `game_host` — no in-memory/fake
  transport stands in for either hop.
- `AllowedIPs` for the peer stays `0.0.0.0/0` inside the netstack device
  configuration (required so the netstack's own routing table forwards
  arbitrary destinations through the single peer), which is independent of
  and does not change the OPNsense-side split-tunnel `AllowedIPs` issued to
  the tester's `.conf` (`192.168.1.254/32`) — the bridge only ever dials the
  one configured `game_host` regardless of what the tunnel would technically
  permit.
- The bridge remembers the loopback peer address from the first datagram it
  receives and forwards subsequent netstack→loopback datagrams only to that
  remembered peer, so a single bridge instance serves exactly one local
  ENet client.
- `wgnetstack_stop` tears down the netstack device and both socket loops
  without leaking goroutines or file descriptors across repeated
  start/stop cycles.

**Failure behavior.** `wgnetstack_start` returns `-1` and logs a reason for: a
missing/unreadable key file, a malformed `config_json`, an invalid base64 key,
or a netstack device construction failure. It MUST NOT return a port for a
half-initialized bridge. Loopback or netstack read errors after a successful
start are logged and end that copy loop without crashing the process; they do
not silently resurrect a new ephemeral port.

**Rollback.** This slice adds a new, self-contained native module and no
slice-028 infra changes. Rollback is deleting `native/wgnetstack/` and its
build output; no OPNsense, host firewall, schema, or Canon state is touched.

## BDD

### Bridge starts and exposes a loopback port

Given a valid `config_json` pointing at a readable private-key file, the
enrolled tester's tunnel address `10.77.0.2/32`, and the live OPNsense
endpoint `192.168.1.1:51900`
When `wgnetstack_start` is called
Then it returns a positive ephemeral loopback port and the netstack WireGuard
device completes a handshake with the OPNsense peer.

### Godot client reaches the live server through the bridge

Given the bridge is running and bound to loopback port `N`
When the existing Godot client is launched with
`PROJECT0_SERVER_HOST=127.0.0.1 PROJECT0_SERVER_PORT=N` against the live
server at `192.168.1.254:9999`
Then the client's ENet connection completes through the tunnel and the client
log reaches its connected/player-spawned state, with no separate OS-level
WireGuard client active.

### Missing or invalid key file fails closed

Given a `config_json` whose `client_private_key_path` does not exist or is not
readable
When `wgnetstack_start` is called
Then it returns `-1`, logs the reason, and leaves no netstack device or
loopback socket running.

### Stop tears down cleanly

Given a running bridge
When `wgnetstack_stop` is called
Then the loopback socket and netstack device are closed and a subsequent
`wgnetstack_start` with the same config succeeds again on a fresh ephemeral
port.

## TDD / validation plan

This is native Go code, not GDScript, so `scripts/run_gut_validation.sh` does
not apply; there is no GDScript/GUT public seam introduced by this slice. The
public seam is the C-exported pair above, exercised directly by the
`cmd/probe` harness (no cgo boundary needed for that harness, since it is a
pure Go `main` importing the same internal package) and, for the cgo boundary
itself, by building and loading `libwgnetstack.so`.

Focused validation command:

```sh
cd native/wgnetstack && go build ./...
cd native/wgnetstack && CGO_ENABLED=1 go build -buildmode=c-shared -o build/libwgnetstack.so ./cmd/cshared
cd native/wgnetstack && go run ./cmd/probe -config <path>
```

Expected pass signal: `go build` exits 0; the probe prints a positive loopback
port and a successful handshake log line.

Acceptance evidence (this slice, Linux only):

- **Bridge evidence**: probe/library run against the live OPNsense endpoint
  `192.168.1.1:51900` and live game host `192.168.1.254:9999`, showing a
  chosen loopback port and a completed WireGuard handshake.
- **Godot evidence (primary)**: the existing Godot client, pointed at
  `127.0.0.1:<port>`, reaches its connected/player-spawned log state against
  the live server through the tunnel.
- **Fallback evidence**: if the headless Godot run is impractical in this
  environment, a full UDP round-trip through the tunnel (a UDP probe sent to
  the loopback port and observed arriving at the game host, or an echoed
  server response observed back at the loopback socket) is captured instead,
  with the limitation stated explicitly rather than claimed as full client
  proof.

No GUT/unit suite regression is expected since no GDScript/shared/server code
changes; `scripts/run_gut_validation.sh` is not re-run for this native-only
addition but remains unaffected since no files under `client/`, `server/`, or
`shared/` are touched.

## Validation Evidence (2026-09-13, Linux prototype, re-run against restarted server)

**Go build.** `wireguard-go` pinned at `golang.zx2c4.com/wireguard@v0.0.0-20231211153847-12269c276173` (the newest pseudo-version whose `go.mod` still declares `go 1.22.2`; `@latest` bumps the `go` directive to `1.23.1`+ and attempts a toolchain switch, so this older pseudo-version was pinned instead, per the slice's Go-1.22.2 constraint). `GOTOOLCHAIN=local` was exported during all `go` commands to guarantee no silent toolchain fetch. `go.mod`'s `go 1.22.2` line was verified unchanged after `go mod tidy`.

```sh
$ cd native/wgnetstack && GOTOOLCHAIN=local go build ./...
EXIT: 0
$ cd native/wgnetstack && GOTOOLCHAIN=local CGO_ENABLED=1 go build -buildmode=c-shared -o build/libwgnetstack.so ./cmd/cshared
EXIT: 0   # produced build/libwgnetstack.so (8.4M) and build/libwgnetstack.h
$ cd native/wgnetstack && GOTOOLCHAIN=local go build -o build/probe ./cmd/probe
EXIT: 0
```

**Bridge evidence (live OPNsense endpoint, live game host).** `build/probe -config build/probe-config.json`, config pointing at `/home/vic/p0-wg-testers/windows-tester.key` (mode 600, read at runtime — never hardcoded or logged), `client_address=10.77.0.2/32`, `server_public_key=VmNN0PMAgZ4tH2RZuF8qJhJu++CWFkrLhbNPMNu2dRU=`, `server_endpoint=192.168.1.1:51900`, `game_host=192.168.1.254:9999`, `persistent_keepalive_interval=25`. Log output:

```text
2026/09/13 15:31:10 wgnetstack: bridge started, loopback port 54716 -> 192.168.1.254:9999 via 192.168.1.1:51900
2026/09/13 15:31:10 probe: bridge listening on 127.0.0.1:54716
```

The bridge ran continuously (no crash, no goroutine/socket errors) across roughly four minutes and multiple client connection attempts below, then was stopped with `SIGTERM` and shut down cleanly:

```text
2026/09/13 15:35:18 probe: stopping bridge
2026/09/13 15:35:18 wgnetstack: bridge stopped
```

**Godot client evidence (primary target, fully achieved on re-run).** The durable game server (`server/server_main.gd`, pid 3743) was restarted on current source — clean boot, monsters spawned, no checksum or convert errors — superseding the earlier run below, which had been unknowingly exercised against a stale, still-running pre-Slice-033 server process (pid 5664). `godot --headless <scene.tscn>` directly on `client/gameplay.tscn` remains impractical for the same pre-existing, slice-independent headless dummy-renderer crash (`ERROR: Parameter "m" is null. at: mesh_get_surface_count`) noted in the original run. The same throwaway harness, `scripts/probe_wgnetstack_client.gd` (`--target-host=`/`--target-port=`, state file polling, matching `scripts/multi_peer_client_harness.gd`'s established pattern), was rebuilt and rerun as its own OS process against a freshly started bridge on loopback port `53592` (`build/probe -config build/probe-config.json`, same tester identity: key path `/home/vic/p0-wg-testers/windows-tester.key`, `client_address=10.77.0.2/32`, `server_public_key=VmNN0PMAgZ4tH2RZuF8qJhJu++CWFkrLhbNPMNu2dRU=`, `server_endpoint=192.168.1.1:51900`, `game_host=192.168.1.254:9999`, `persistent_keepalive_interval=25`):

```text
{"status":"connected: player spawned"}
```

The client reached the full `connected: player spawned` state through the tunnel within the 300-tick (~5s) window — the WireGuard handshake, netstack routing, the ENet connection handshake, and the server's `spawn_own_player_representation` RPC all completed correctly across the bridge. The Godot process log showed a normal sector blueprint receipt (`sector_id=starting_town_hub, outcome=valid, 3037 tiles, 28 structures`) and no errors.

**Isolation re-run confirms stale-server artifact, not a genuine bug.** The identical harness, run directly against the live server (`--target-host=192.168.1.254 --target-port=9999`, no bridge involved at all) against the now-restarted server also reached `{"status":"connected: player spawned"}` cleanly, with no `receive_monster_position` convert error and no RPC checksum failure in the client log. This confirms the earlier "connected but never player spawned" result was not a WireGuard/bridge failure and not a genuine Slice 033 monster-replication type bug: it was the *previously running* server process (pid 5664) still executing stale pre-Slice-033 `network_client.gd`, so its NetworkClient RPC method table did not match the current-source client, producing an "rpc node checksum failed" condition and the misleading `Cannot convert argument 1 from int to String` log line as a method-table-mismatch artifact. `server/server_monster_manager.gd`'s `living_targets()` keys are, and always were, String `spawn_id`s matching the RPC's declared `String target_id` parameter — there was no type defect in the committed monster-replication code. Restarting the server process on current source resolved the mismatch; no code change was required or made.

**Conclusion.** The wgnetstack userspace netstack bridge is fully proven against the live infrastructure: a real loopback UDP socket, a real `wireguard-go` netstack device with a live WireGuard peer, and a real Godot ENet client interoperate end to end through the tunnel, reaching the literal `connected: player spawned` acceptance state with no OS TUN device and no admin rights. The direct (non-bridge) re-run against the same restarted server reaches the identical state, confirming the earlier gap was a stale-server artifact external to this slice, not a transport/bridge defect.

**Cleanup.** The probe bridge process, `build/probe`, `build/probe-config.json`, and all state/log files from both re-run passes were removed after evidence capture. `scripts/probe_wgnetstack_client.gd` was left in place as reusable validation tooling (not part of the delivered public seam). No OPNsense, host firewall, or server state was modified by this validation.

## Non-goals (restated)

- Windows DLL validation on a Windows host (S3).
- `.gdextension` / godot-cpp packaging and GDScript call sites (S3).
- Enrollment/key-provisioning automation (S4).
- Any OPNsense, host-firewall, or admin-tunnel change (all owned by Slice 028
  and left untouched here).
