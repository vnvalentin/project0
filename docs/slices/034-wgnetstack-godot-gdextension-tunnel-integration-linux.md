# Slice 034: wgnetstack in-client GDExtension + tunnel integration (Linux)
GitHub issue: #95

Status: delivered (Linux in-process GDExtension tunnel validated end to end;
the real Godot client reaches `connected: player spawned` through the
in-process `WgNetstack` tunnel with no external process, and the full GUT
suite stays green at 199/199)

Tracker context: Phase 11 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
by delivering S3a of the netstack-bridge design: wrapping the Slice 032
`native/wgnetstack` Go bridge as a real in-process Godot 4.3 GDExtension and
wiring the client to open the WireGuard tunnel itself, with no separate probe
process, no OS TUN device, and no admin rights. Planning ticket:
[Public Game Access via WireGuard map](../../.scratch/wan-wireguard/map.md),
decisions
[01 — ENet transport netstack bridging](../../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md)
and
[02 — Godot GDExtension WireGuard netstack prototype](../../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md).
Builds directly on
[Slice 032](032-wgnetstack-netstack-bridge-linux-prototype.md), which proved
the bridge logic itself (`native/wgnetstack/bridge`) end to end against the
live server, but only through a standalone `cmd/probe` OS process and the
throwaway `scripts/probe_wgnetstack_client.gd` harness driving a *separate*
probe process — not through Godot loading the library in-process.

## SDD

**Problem.** Slice 032 proved the wgnetstack bridge works, but only as a
second OS process (`build/probe`) that a tester would have to start
separately before launching Godot — exactly the "extra app" burden issue 02
scoped the GDExtension to remove. No `.gdextension` resource or GDScript call
site exists yet; `native/wgnetstack` only exports two C functions
(`wgnetstack_start`/`wgnetstack_stop`) with no Godot-facing wrapper.

**Outcome.** A minimal godot-cpp-based GDExtension,
`native/wgnetstack/gdext/`, registers one `RefCounted`-derived class
`WgNetstack` with `start(config: Dictionary) -> int` and `stop() -> void`,
calling straight through to the existing `bridge.StartActive`/
`bridge.StopActive` Go functions via a thin cgo static-library boundary (no
process spawn, no IPC — the Go runtime lives inside the Godot process's
address space once the shared library is loaded). `client/network_client.gd`
grows a tunnel-mode code path: when enabled, it instantiates `WgNetstack`,
calls `start()` with a config assembled from environment variables/a JSON
file (never a hardcoded key), and on a positive port return connects
`ENetMultiplayerPeer` to `127.0.0.1:<port>` instead of the direct host. LAN
mode (tunnel mode off, the existing default) is unchanged byte-for-byte.

**Boundary — in scope for S3a (this slice, Linux only):**

- `native/wgnetstack/cmd/cgoarchive`: a new Go `main` package built with
  `-buildmode=c-archive` (`CGO_ENABLED=1`), exporting the same
  `wgnetstack_start`/`wgnetstack_stop` C ABI as the existing `cmd/cshared`,
  but as a static archive (`.a` + `.h`) suitable for linking directly into the
  GDExtension's own compiled shared library, so the GDExtension does not need
  to `dlopen` a second library at runtime.
  A `Makefile` target `cgoarchive` builds it.
- `native/wgnetstack/gdext/`: a godot-cpp (4.3 branch) GDExtension source
  tree (`src/wg_netstack.cpp`/`.h`, `src/register_types.cpp`/`.h`,
  `SConstruct`) that links the c-archive above and registers `WgNetstack`.
- `native/wgnetstack/gdext/wgnetstack.gdextension`: the resource Godot loads,
  with a Linux `.so` entry built and validated in this slice, and a Windows
  `.dll` entry path *declared* (for S3b) but not built or validated here.
- `client/network_client.gd`: a new tunnel-mode branch in
  `connect_to_server()` (or a thin seam it calls), reading config from
  env/JSON, instantiating `WgNetstack`, and redirecting the ENet target to
  the loopback bridge port on success. Default OFF — `PROJECT0_TUNNEL` unset
  or not `1` reproduces today's direct-connect behavior exactly.
- A Linux in-process proof: the real Godot client (via the established
  `SceneTree`-script headless harness pattern, matching
  `scripts/probe_wgnetstack_client.gd`) launched with tunnel mode on, loading
  the compiled GDExtension itself and reaching `connected: player spawned`
  against the live server with no separate bridge/probe process running.

**Non-goals (this slice, S3a — deferred):**

- Windows `.dll` build/link/validation on a Windows host (S3b).
- Enrollment/key-provisioning automation, invite codes, or any change to how
  `client_private_key_path` is provisioned on disk (S4) — this slice keeps
  reading the same hand-placed
  `/home/vic/p0-wg-testers/windows-tester.key` Slice 028/032 already used.
- Revocation/ban lifecycle (S5).
- Any OPNsense, host-firewall, or admin-tunnel change — Slice 028's
  infrastructure is reused unmodified.
- Removing or replacing `native/wgnetstack/cmd/cshared` or `cmd/probe` — both
  stay as-is for standalone/non-Godot validation; this slice only adds the
  new c-archive target and the GDExtension that links it.
- A packaged/exported Godot build; this slice runs the GDExtension from the
  project source tree via the editor/headless binary, matching every prior
  slice's runtime posture in this repository.

**Public seam.** Two seams, both new:

1. The compiled GDExtension library + `wgnetstack.gdextension` resource,
   exposing the `WgNetstack` class to any GDScript in the project:
   `WgNetstack.new().start(config: Dictionary) -> int` (loopback port, or
   `-1` on failure, logged) and `.stop() -> void`.
2. The GDScript integration seam in `client/network_client.gd`: a static,
   testable function that decides tunnel-vs-direct target resolution from
   injected config (mirroring this file's existing static/parent-injected
   seam style, e.g. `render_sector_blueprint`), plus the non-static
   `connect_to_server()` call site that uses it.

**Invariants.**

- The client private key is never hardcoded in GDScript, the `.gdextension`
  resource, the C++ wrapper, or committed config — only a file path, read at
  `start()` time by the existing Go `bridge.Config`/`readPrivateKeyBase64`
  path proven in Slice 032. This slice adds no new place that reads or logs
  key material.
- Tunnel mode is opt-in and OFF by default. No existing LAN-direct behavior,
  test, or default constant changes when `PROJECT0_TUNNEL` is unset.
- The GDExtension performs no process spawn and no second `dlopen` of a
  sibling bridge library — the bridge logic is statically linked into the one
  compiled `.so` godot loads, so "no separate process" is structural, not just
  operationally true in this proof.
- `WgNetstack.start()` returns a positive port only on a fully-up bridge
  (matching Slice 032's `wgnetstack_start` contract exactly — no wrapper-level
  optimism); `-1` on any failure, with the reason logged.
- Config assembly in GDScript treats every field as untrusted external input
  (env var or JSON file) and never fabricates a default private-key path
  pointing outside what the caller explicitly configured.

**Failure behavior.** Same as Slice 032's bridge contract, inherited
unchanged: a missing/unreadable key file, malformed config, invalid key, or
netstack construction failure all surface as `start() == -1` with a logged
reason and no partially-initialized bridge. On the GDScript side, a `-1`
return leaves `NetworkClient` in a `failed: tunnel start error` status and
does not attempt an ENet connection to a nonexistent loopback port.

**Rollback.** Deleting `native/wgnetstack/gdext/`, the new `cmd/cgoarchive`
package, and the `client/network_client.gd` tunnel branch (with
`PROJECT0_TUNNEL` reverted to always-unset behavior) fully reverts this
slice. No server, schema, or persisted state is touched.

## BDD

### GDExtension loads and exposes WgNetstack in Godot

Given the compiled `native/wgnetstack/gdext/build/libwgnetstack_gdext.so` and
its `wgnetstack.gdextension` resource are present in the project
When Godot (editor or headless) loads the project
Then `WgNetstack` is a constructible global class and calling `.start()` with
a valid config in-process returns a positive loopback port with no external
process started.

### Client connects through the in-process tunnel end to end

Given `PROJECT0_TUNNEL=1` and a valid tunnel config (server public key,
server endpoint, game host, client tunnel address, client private key file
path, keepalive) available via env/JSON
When the Godot client starts and reaches its normal connection entry point
Then it instantiates `WgNetstack`, starts the bridge in-process, connects
`ENetMultiplayerPeer` to `127.0.0.1:<returned port>`, and the client log
reaches `connected: player spawned` against the live server, with no
`build/probe` or other external bridge process running during the test.

### Tunnel mode off preserves existing direct-connect behavior

Given `PROJECT0_TUNNEL` is unset (the default)
When the client starts
Then it connects directly to the configured LAN/WAN host exactly as before
this slice, with no `WgNetstack` instantiation and no behavior change.

### Bridge start failure fails closed in the client

Given `PROJECT0_TUNNEL=1` and a config whose key file path does not exist
When the client attempts to start the tunnel
Then `WgNetstack.start()` returns `-1`, the client sets a `failed:` status
and does not attempt an ENet connection to a fabricated port.

## TDD / validation plan

Native Go code is validated the same way Slice 032 validated it (`go build`,
`go vet`); the new pieces this slice adds are (a) a Go c-archive build and
(b) a C++ GDExtension compiled against godot-cpp, neither of which has a GUT
seam, so `scripts/run_gut_validation.sh` is not the primary evidence path
here — same posture Slice 032 recorded. `client/network_client.gd`'s new
static config-resolution seam is unit-testable under GUT and gets a focused
test there; the full in-process tunnel connection is validated at runtime,
matching Slice 032's Godot-evidence pattern.

Focused validation commands:

```sh
cd native/wgnetstack && GOTOOLCHAIN=local go build ./...
cd native/wgnetstack && GOTOOLCHAIN=local CGO_ENABLED=1 go build -buildmode=c-archive -o build/libwgnetstack.a ./cmd/cgoarchive
godot --headless --dump-gdextension-interface --dump-extension-api   # only if godot-cpp headers need refreshing
cd native/wgnetstack/gdext && scons target=template_debug platform=linux   # or the chosen godot-cpp build invocation
scripts/run_gut_validation.sh   # existing GDScript suite, unaffected but re-run to confirm no regression
godot --headless --path . -s scripts/probe_wgnetstack_client.gd -- --target-host=... (superseded by the in-process run below)
```

Expected pass signal: both Go builds exit 0; the GDExtension `.so` compiles
with exit 0; `scripts/run_gut_validation.sh` stays green
(`build/validation/validation-summary.json` status `passed`); the in-process
Godot run reaches `{"status":"connected: player spawned"}` with `ps`/process
inspection showing no separate bridge process during that run.

Acceptance evidence (this slice, Linux only): the real Godot client, launched
headless via the established SceneTree-script harness pattern (mirroring
`scripts/probe_wgnetstack_client.gd`, adapted to enable tunnel mode instead
of pointing at an externally-started probe), loads the GDExtension, starts
the bridge in-process, and reaches `connected: player spawned` against the
live server at `192.168.1.254:9999` through the tunnel — with the live
values from Slice 028/032 (`server_public_key=VmNN0PMAgZ4tH2RZuF8qJhJu++CWFkrLhbNPMNu2dRU=`,
`server_endpoint=192.168.1.1:51900`, `game_host=192.168.1.254:9999`,
`client_address=10.77.0.2/32`,
`client_private_key_path=/home/vic/p0-wg-testers/windows-tester.key`,
`persistent_keepalive_interval=25`) and no external probe/bridge process in
the path.

## Validation Evidence (2026-09-13, Linux)

**Build (godot-cpp GDExtension + Go c-archive).** `make -C native/wgnetstack
cgoarchive` produced `build/libwgnetstack.a` (+ header); godot-cpp (4.3) and
the wrapper compiled via `scons` to
`native/wgnetstack/gdext/build/libwgnetstack_gdext.linux.template_debug.x86_64.so`
and the matching `template_release` — all with exit 0.

**GDExtension loads in Godot.** `addons/wgnetstack/wgnetstack.gdextension`
(entry symbol `wgnetstack_gdext_library_init`, `compatibility_minimum = 4.3`)
registers the class: `ClassDB.class_exists("WgNetstack") == true`, and an
instance exposes `start`/`stop` (`has_method` both true).

**Client seam wired (default-off, robust when absent).**
`client/network_client.gd`'s `connect_to_server()` gained `_maybe_start_tunnel()`:
when `PROJECT0_TUNNEL=1` it instantiates `WgNetstack` (via `ClassDB.instantiate`
so the script still loads where the extension is absent), builds the config
from `PROJECT0_TUNNEL_*` env (private key by file path only, never read/logged),
calls `start()`, and connects `create_client("127.0.0.1", <loopback port>)`;
otherwise the direct path is unchanged.

**In-process acceptance MET.** With `PROJECT0_TUNNEL=1` and the live values,
the real client reached `{"status":"connected: player spawned"}`. The process
log showed the tunnel opening *inside* the Godot process:
`wgnetstack tunnel up on 127.0.0.1:51713 -> 192.168.1.254:9999 via 192.168.1.1:51900`
— no external `build/probe` process in the path.

**Regression clean.** With tunnel mode off, the same harness still reaches
`connected: player spawned` (direct path unchanged); `scripts/run_gut_validation.sh`
exited 0 with 26 scripts / 199 tests / 199 passing.

**Ownership note.** Claude authored the godot-cpp GDExtension
(`native/wgnetstack/gdext/src/*`, `SConstruct`, `cmd/cgoarchive`) and this
record records-first, and completed the full native build before hitting a
session limit. Per user authorization, Copilot then added
`addons/wgnetstack/wgnetstack.gdextension`, the `network_client.gd` tunnel
seam, `native/wgnetstack/gdext/.gitignore`, and ran the in-process proof and
regression.

**Follow-ups (not blockers).** `~WgNetstack()` does not call `stop()`; the
bridge is torn down on process exit (or replaced on the next `StartActive`),
so an explicit stop-on-disconnect is a later refinement. Build outputs and
the vendored `godot-cpp`/`.venv` are gitignored and regenerated via
`make cgoarchive` + `scons`.

## Non-goals (restated)

- Windows DLL build/link/validation (S3b).
- Enrollment/key-provisioning automation (S4).
- Revocation/ban lifecycle (S5).
- Any OPNsense/host-firewall/admin-tunnel change.
