# Slice 003: Windows client connects to a configurable Linux server over LAN

Tracker context: Phase 3 — LAN client connection; advances
[P-002](../FEATURE-LIST.md#p-002-lan-client-connection).
Planning ticket: [game-vision issue 08](../.scratch/game-vision/issues/08-lan-client-connection.md).

## SDD

Goal: A Windows Godot client can target the Linux server's LAN address
instead of `127.0.0.1`, while `127.0.0.1` remains the default for both sides
so Slice 001 and Slice 002's automated headless checks keep passing
unchanged. Port 9999 and the existing status/player-spawn flow are
untouched.

Domain boundary: This slice only makes the server's bind address and the
client's target host configurable. It does not add movement synchronization,
prediction, interpolation, authentication, reconnect handling, firewall
automation, Docker deployment, internet exposure, world generation, a map,
saves, quests, Ollama, or SQLite. `client/player.gd`'s local movement
authority (ADR 0001) and Slice 002's connection/spawn seam are unchanged.

Public seam:
- `shared/network_config.gd` (`resolve_server_bind_address()`,
  `resolve_client_target_host()`) — new static resolver functions. Each
  checks, in order: a `--` command-line argument
  (`--server-bind-address=<addr>` / `--server-host=<addr>`), then an
  environment variable (`PROJECT0_SERVER_BIND_ADDRESS` /
  `PROJECT0_SERVER_HOST`), then falls back to the existing `SERVER_ADDRESS`
  constant (`127.0.0.1`). Never returns an empty string.
- `server/server_main.gd` (`_start_server`) — now calls
  `resolve_server_bind_address()` and applies it via
  `ENetMultiplayerPeer.set_bind_ip()` before `create_server()`.
- `client/network_client.gd` (`connect_to_server`) — now resolves its `host`
  parameter via `resolve_client_target_host()` when the caller passes no
  explicit host (an empty string is the "use resolver" sentinel; passing an
  explicit host, as the existing Slice 002 smoke test does, still works
  unchanged).

Inputs/outputs: no change to the wire protocol, port, RPC names, or
`NetworkClient.status` value set. The only new inputs are the two CLI
arg/env var pairs above; the only new output is one additional startup print
from the server when it binds to a non-localhost address (a safety warning,
see below).

Non-goals (explicit scope cut, per user direction and
[game-vision issue 08](../.scratch/game-vision/issues/08-lan-client-connection.md)):
no movement synchronization, prediction, interpolation, authentication,
reconnect logic, firewall automation, Docker deployment, internet exposure,
world generation, map, world save, quests, Ollama, SQLite, or production
art.

Safety invariant: With no CLI arg or environment variable set, the server
binds only to `127.0.0.1` and the client only targets `127.0.0.1` — identical
to Slice 002's behavior, so automated checks and any developer running the
project with no extra flags get the same localhost-only exposure as before.
Binding to a non-localhost address is only possible via a deliberate,
explicit operator action (`--server-bind-address=<LAN IP>` or
`PROJECT0_SERVER_BIND_ADDRESS=<LAN IP>`), and doing so prints a clear runtime
warning naming the bound address and stating that the server accepts
unauthenticated connections from anything that can reach it. An unbindable
address (confirmed empirically with an RFC 5737 TEST-NET-1 address,
`203.0.113.5`) fails closed: `ENetMultiplayerPeer.create_server()` returns a
non-`OK` error, the script `push_error`s and `quit(1)`s, and no "Server
listening" state is ever reached — the server never silently falls back to
binding all interfaces.

## BDD

### Normal path: LAN bind and connect

Given the Linux server is started with
`godot --headless --path . -s server/server_main.gd -- --server-bind-address=<LAN IP>`
and the Windows client is started with
`PROJECT0_SERVER_HOST=<LAN IP>` (or `--server-host=<LAN IP>`) set
When the client's gameplay scene loads and `NetworkClient.connect_to_server()`
runs
Then the client reaches `NetworkClient.status == "connected: player spawned"`
exactly as in Slice 002, now over the LAN address instead of loopback.

### Highest-risk: unbindable or unintended bind address

Given an operator passes a bind address the server's network interfaces
cannot bind to
When `_start_server()` runs
Then `create_server()` returns a non-`OK` error, the server logs the failure
and exits with code 1, and it never reaches or prints a "Server listening"
state — it fails closed rather than silently defaulting to binding every
interface.

### Safety/default: no override preserves localhost-only exposure

Given no CLI argument or environment variable is set on either side
When the server starts and the client connects
Then both resolvers return `127.0.0.1`, matching Slice 002's behavior
exactly, so existing automated checks and any accidental unconfigured run
stay localhost-only.

## TDD evidence

The public seam is exercised by the GUT test
`tests/unit/test_lan_config.gd`, run via
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`.
It asserts, using real second OS processes running
the unmodified production `server/server_main.gd` entry point (and a small
checked-in probe script, `scripts/probe_client_target_host.gd`, for the
client-side resolver — a process's command-line arguments are only visible
to itself, so an in-process check cannot exercise CLI-arg precedence):

1. With no override, both resolvers return `127.0.0.1` (in-process).
2. A real server process started with `--server-bind-address=127.0.0.1`
   prints `Server listening on 127.0.0.1:9999` and exits 0.
3. A real probe process started with `--server-host=192.168.1.50` prints
   `RESOLVED:192.168.1.50` and exits 0.
4. A real server process started with `--server-bind-address=203.0.113.5`
   (an RFC 5737 TEST-NET-1 address, guaranteed unbindable on any real host)
   exits non-zero and never prints "Server listening".

All 8 assertions passed on 3 consecutive runs with no flakiness observed.
Environment-variable precedence was validated manually (not in the automated
suite, to avoid mutating this process's own environment mid-suite) — see
Validation below for the exact commands and observed output.

## ADR decision

No new ADR. This slice adds an ordinary, additive configuration mechanism
(CLI arg / env var with a safe existing default) to the already-accepted
Slice 002 connection seam; it introduces no new architectural, security
model, persistence, or ownership boundary. The safety posture (localhost by
default, explicit and visible opt-in to LAN exposure, fail-closed on an
unbindable address) is documented above and in the run procedure below
rather than in a standalone ADR.

## Two-machine run procedure

**This procedure requires the Linux operator to deliberately choose to
expose the server beyond localhost.** Only do this on a trusted local
network (e.g. a home LAN behind a router/NAT, not a shared or public
network), since this slice adds no authentication.

1. On the Linux machine, find its LAN IP address (e.g. `ip -4 addr show
   scope global`, or `hostname -I`). Example: `192.168.1.50`.
2. On the Linux machine, from the repository root, start the server bound to
   that LAN address:
   ```
   godot --headless --path . -s server/server_main.gd -- --server-bind-address=192.168.1.50
   ```
   or equivalently:
   ```
   PROJECT0_SERVER_BIND_ADDRESS=192.168.1.50 godot --headless --path . -s server/server_main.gd
   ```
   Confirm the printed line reads `Server listening on 192.168.1.50:9999`
   followed by the non-localhost warning. If the bind fails, the printed IP
   is wrong for this machine's interfaces — re-check step 1.
3. On the Windows machine, open the project in the Godot 4.3 editor (or run
   an exported client) and set the same address as the target host, either
   by launching with a command-line argument:
   ```
   godot.exe --path . --server-host=192.168.1.50
   ```
   or by setting the environment variable `PROJECT0_SERVER_HOST=192.168.1.50`
   before launch.
4. Enter a display name at the identity gate and select **Enter**.
5. In the gameplay scene, confirm the status label changes from
   `Server: disconnected` through `Server: connecting` to
   `Server: connected: player spawned`, exactly as in Slice 002's client test
   procedure, now over the LAN link.
6. When done, stop the Linux server process (Ctrl+C or kill it). No firewall
   rule, port-forward, or router configuration is created or required by
   this slice beyond what the operator's OS/network already permits for LAN
   traffic on port 9999; if the Linux host's firewall blocks inbound
   connections on 9999, the operator must open that port themselves — this
   slice does no firewall automation.

## Validation

Run from the repository root (`/data/code/project0`):

- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project (including the updated `shared/network_config.gd`,
  `server/server_main.gd`, `client/network_client.gd`, and the new
  `scripts/test_lan_config.gd` / `scripts/probe_client_target_host.gd`)
  opens and closes cleanly under the editor codepath with no import or parse
  errors.
- `godot --headless --path . --check-only -s shared/network_config.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s server/server_main.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s client/network_client.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s scripts/test_lan_config.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s
  scripts/probe_client_target_host.gd`: PASS, exit 0.
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`
  (Slice 001 regression): **ALL PASS**, exit 0 — all 6 assertions pass
  unchanged.
- `godot --headless --path . -s scripts/test_client_server_connection.gd`
  (Slice 002 regression): **ALL PASS**, exit 0 — all 8 assertions pass
  unchanged, confirming the default localhost connection/spawn flow is
  untouched by the Slice 003 changes.
- `godot --headless --path . -s scripts/test_lan_config.gd`: **ALL PASS**,
  exit 0. All 8 assertions passed, run 3 times consecutively with no
  flakiness observed: both resolvers default to `127.0.0.1` with no
  override; a real server process honors `--server-bind-address=`; a real
  probe process honors `--server-host=`; a real server process fails closed
  (non-zero exit, no "Server listening" print) on an unbindable RFC 5737
  TEST-NET-1 address (`203.0.113.5`).
- Manual end-to-end LAN-shaped verification (this sandbox has no second
  physical machine, so a real local, non-loopback interface IP on this host
  was used to prove the actual bind+connect mechanism rather than only the
  resolver logic): started the real server with
  `PROJECT0_SERVER_BIND_ADDRESS=192.168.1.254 godot --headless --path . -s
  server/server_main.gd`, observed `Server listening on 192.168.1.254:9999`
  followed by the non-localhost warning; then ran the client seam with
  `PROJECT0_SERVER_HOST=192.168.1.254` against a fresh `NetworkClient`,
  observed `NetworkClient.status` reach `"connected"`. This proves
  `set_bind_ip()` + `create_server()` and `create_client()` both work over a
  real non-loopback local address end-to-end, not just that the resolver
  functions return the right string.
- Manual environment-variable precedence check: `PROJECT0_SERVER_BIND_ADDRESS=127.0.0.1
  godot --headless --path . -s server/server_main.gd --quit-after 1`
  printed `Server listening on 127.0.0.1:9999` with no warning (still
  localhost, env var path exercised); confirmed the CLI arg takes precedence
  over the env var by setting both to different values and observing the
  CLI arg's value win (matches `resolve_server_bind_address()`'s documented
  precedence order, read from source rather than re-derived).
- `ENetMultiplayerPeer` API shape was empirically re-verified against the
  installed Godot 4.3.stable engine rather than assumed from memory:
  `create_server()` takes 5 int-only arguments (no bind-address argument;
  passing a 6th or a String argument fails to parse), and binding a specific
  address requires calling `set_bind_ip(ip)` before `create_server()`. This
  contradicts what a naive implementation might assume about the API and is
  the reason `server_main.gd` uses `set_bind_ip()` rather than an extra
  `create_server()` argument.

### Two-machine LAN validation

- Date: 2026-09-12
- Outcome: User verified physical two-machine LAN run connecting Windows client to Linux server over LAN address; connection reached `Server: connected: player spawned`. Closes [DT-004](../TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003).
