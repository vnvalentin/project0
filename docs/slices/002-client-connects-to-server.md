# Slice 002: Client connects to headless server and shows connected Player
GitHub issue: #95

Tracker context: Phase 2 — Network connection proof; advances
[P-001](../FEATURE-LIST.md#p-001-server-authoritative-networked-multiplayer)
and surfaces [DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
and [DT-003](../TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result).
Planning ticket: [game-vision issue 07](../.scratch/game-vision/issues/07-connect-client-to-server.md).

## SDD

Goal: A headless Godot server accepts one ENet client connection on
localhost, the client shows a connection status string, and the connected
client's own gameplay scene gains a visible, distinct Player representation
once the server confirms the connection — with no movement synchronization,
prediction, persistence, authentication, or reconnect logic.

Domain boundary: This slice only proves the connection seam. It does not
change `client/player.gd`'s existing client-side movement (ADR 0001 still
governs that Player) and does not give the server authority over the
existing local Player's position.

Public seam:
- `server/server_main.gd` (`_start_server`, `_on_peer_connected`) — the
  headless server entry point, run via `godot --headless -s
  server/server_main.gd`.
- `client/network_client.gd` (`connect_to_server`, `status`,
  `connection_status_changed`, `spawn_local_player_representation`) — the
  client-side autoload (`NetworkClient`) that owns the connection attempt,
  exposes connection status, and spawns the networked Player representation
  when RPC'd by the server.
- `client/connection_status.gd` — a `Label` script in `gameplay.tscn` that
  calls `NetworkClient.connect_to_server()` on scene entry and displays
  `NetworkClient.status`.

Inputs/outputs: The server seam takes no runtime input (port and max-client
count come from `shared/network_config.gd`) and produces ENet server socket
state plus one `peer_connected`/`peer_disconnected` print per event. The
client seam's `connect_to_server(host, port)` takes an address and port
(defaulting to the shared config) and produces `connection_status_changed`
signal emissions (`"connecting"` → `"connected"` → `"connected: player
spawned"`, or a `"failed: ..."` / `"disconnected"` terminal state). On
success, the server RPCs the connecting peer's `NetworkClient` to run
`spawn_local_player_representation()`, which instantiates
`client/networked_player.tscn` as a child named `NetworkedPlayer` under the
current scene.

Non-goals (explicit scope cut, per user direction and
[game-vision issue 07](../.scratch/game-vision/issues/07-connect-client-to-server.md)):
no client prediction, no interpolation, no synchronized/replicated movement,
no reconnect handling, no authentication, no world generation, no map, no
world save, no quests, no Ollama, no SQLite, no Docker deployment, no
production art. The pre-existing local WASD `Player` node and its movement
(`client/player.gd`) are untouched; the networked Player is a second,
visually distinct node (blue capsule vs. the local Player's red capsule) so
this slice does not implicitly claim the two are unified yet.

Safety invariant: The server binds only to `127.0.0.1` (see
`shared/network_config.gd`'s `SERVER_ADDRESS`), accepts unauthenticated
connections (acceptable for a localhost-only proof; not safe beyond this
slice), and neither side writes to disk or calls any external network
service. This slice makes the same "no external calls, no persistence"
guarantee as Slice 001, scoped to localhost ENet traffic only.

## BDD

### Normal path: server starts, client connects, Player becomes visible

Given a headless Godot server process is running
`server/server_main.gd` and listening on `127.0.0.1:9999`
When the client's gameplay scene loads and `NetworkClient.connect_to_server()`
runs
Then the client reaches `NetworkClient.status == "connected"`, the server
emits its `peer_connected` event, and a `NetworkedPlayer` node
(distinct from the local WASD Player) appears in the client's current scene.

### Highest-risk: no server is running

Given no server process is listening on `127.0.0.1:9999`
When the client's gameplay scene loads and attempts to connect
Then `NetworkClient.status` reaches a `"failed: ..."` state via the
`connection_failed` signal, no `NetworkedPlayer` node is spawned, and the
existing local WASD Player and flat plane remain fully usable (the
connection attempt never blocks or breaks local movement).

### Idempotency: duplicate spawn RPCs do not duplicate the Player

Given the client has already spawned its `NetworkedPlayer` node
When `spawn_local_player_representation()` is invoked again (e.g. a
redundant RPC)
Then `network_client.gd` finds the existing `NetworkedPlayer` node by name
and returns without creating a second one.

## TDD evidence

No GDScript test framework is installed yet
([DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
carried forward unchanged from Slice 001 — still an accepted scope cut, now
also covering this slice's script). The public seam is instead exercised by
a headless integration smoke test,
`scripts/test_client_server_connection.gd`, run via `godot --headless -s`.
This test spawns a **real second OS process** running the actual
`server/server_main.gd` production entry point (via `OS.create_process`),
then drives the client-side public seam
(`NetworkClient.connect_to_server`) in the current process against that
real server over a real localhost ENet socket, and asserts on
`NetworkClient.status` and the presence/type of the spawned
`NetworkedPlayer` node. This is not a private-method-only assertion: every
assertion reads state reachable from the documented public seam
(`NetworkClient.status`, the `NetworkedPlayer` node in the scene tree), and
the server is the unmodified production script, not a stub. A same-process,
two-`MultiplayerAPI`-instance design was tried first and rejected: Godot 4.3
does not support a server peer and a client peer coexisting on one
`SceneTree.root.multiplayer` (confirmed empirically — see Validation), so a
real second process is the smallest design that stays faithful to
production topology.

The BDD "no server is running" and "idempotent spawn" scenarios above are
not yet covered by an automated test in this slice (see
[DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)'s
remediation path); they were validated once manually during development
(observed `"failed: connection refused"` when the smoke test's server
process was killed before the client connected, and observed no duplicate
node when `spawn_local_player_representation()` was called twice in a
scratch script) but are not re-checked on every run. Recorded as a known gap
below and in the Technical Debt Tracker rather than left silent.

The smoke test does not assert the server's stdout event count. Server
connection logging is covered by the standalone server validation command and
is observed evidence, while the automated acceptance check remains focused on
the client-visible connection and spawn seam.

## ADR decision

No new ADR. This slice does not change movement authority (still governed by
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md)) and does
not introduce a new architectural, security, persistence, or ownership
boundary beyond what `docs/PROJECT-TRACKER.md`'s Phase 2 exit gate already
describes: "a headless Godot server accepts one ENet client and the client
visibly represents the connected Player on the existing flat plane, with no
movement synchronization or persistence required yet." The RPC-node-path
mechanism (autoloads at matching `/root/<Name>` paths on both sides) is an
ordinary Godot high-level multiplayer implementation detail, not a
standalone architectural decision requiring its own ADR.

## Validation

Run from the repository root (`/data/code/project0`):

- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project (including the new `server/`, `client/network_client.gd`,
  `client/connection_status.gd`, `client/networked_player.tscn`, and
  `shared/network_config.gd`) opens and closes cleanly under the editor
  codepath with no import or parse errors.
- `godot --headless --path . --check-only -s shared/network_config.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s server/server_main.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s client/network_client.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s client/connection_status.gd`:
  FAILS with "Identifier not found: NetworkClient", exit 1. Same
  root cause already documented in Slice 001 for
  `client/identity_gate.gd`/`PlayerIdentity`: `--check-only -s` parses a
  single script without starting a `SceneTree`, so `[autoload]` singletons
  are never registered as global identifiers under that check. Confirmed
  identical by re-running `godot --headless --path . --check-only -s
  client/identity_gate.gd` (also FAILS the same way, unchanged from Slice
  001) as a same-repo control. Corroborated as a non-defect by the runtime
  checks below, where the autoload resolves and the scene runs cleanly.
- `godot --headless --path . --quit-after 5 client/gameplay.tscn`: PASS,
  exit 0, with the same single benign, non-fatal engine print already
  documented in Slice 001 (`ERROR: Parameter "m" is null. at:
  mesh_get_surface_count (...)`, a Godot 4.3 headless dummy-renderer stub
  artifact, not a scene or script defect).
- `godot --headless --path . --quit-after 2 client/identity_gate.tscn`:
  PASS, exit 0 — confirms the identity gate is unaffected.
- `godot --headless --path . -s server/server_main.gd` (run standalone for
  a few seconds, then interrupted): prints `Server listening on
  127.0.0.1:9999` and, while a client is connected, `Peer connected: <id>`
  / `Peer disconnected: <id>` — confirms the server entry path starts,
  binds, and logs connection membership events.
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`:
  **ALL PASS**, exit 0 — rerun as a regression check; all 6 Slice 001
  assertions still pass unchanged.
- `godot --headless --path . -s scripts/test_client_server_connection.gd`:
  **ALL PASS**, exit 0. All 8 assertions passed, run 3 times consecutively
  with no flakiness observed: server process starts; server process is
  still running after startup; `NetworkClient` starts `"disconnected"`
  before connecting; `NetworkClient` reaches a connected status; a visible
  `NetworkedPlayer` node is spawned in the gameplay scene; the spawned node
  is a `Node3D`; `NetworkClient.status` reflects the completed spawn. This
  is the slice's primary acceptance evidence for the BDD normal path.

  ## Client test procedure

  The client can be tested manually on a machine with a Godot window:

  1. From the project root, start the server and leave it running:
    `godot --headless --path . -s server/server_main.gd`
  2. In a second terminal, start the client project with `godot --path . --editor`
    and run the project, or use the Godot editor's Play button.
  3. Enter a display name at the identity gate and select **Enter**.
  4. In the gameplay scene, confirm the status label changes from
    `Server: disconnected` through `Server: connecting` to
    `Server: connected: player spawned`.
  5. Confirm the red local Player and blue networked Player are visible on the
    flat plane. WASD currently moves only the local Player; movement
    synchronization is intentionally not part of this slice.

  To test the failure path, start the client without the server and confirm the
  status settles at `Server: failed: connection refused` while the local plane
  and local Player remain available.

### Defects and design corrections found during this slice's validation

- Initial design assumed `SceneTree.root.multiplayer` would be available
  synchronously inside `_initialize()` in a `-s` headless server script.
  Empirically false: `root.multiplayer` is `null` at that point (confirmed
  by isolated repro). Fixed by deferring server/client startup to
  `call_deferred("_start_server"/"_start")`, matching the same
  `_initialize()` timing constraint already documented for autoloads.
- Initial design used the bare `multiplayer` Node shortcut inside a
  `SceneTree`-extending script (`server/server_main.gd`), which does not
  exist on `SceneTree` (only on `Node`). Fixed by using `root.multiplayer`
  explicitly in the server script; `client/network_client.gd` correctly
  uses the `multiplayer` shortcut because it is itself a `Node` (the
  `NetworkClient` autoload).
- Initial smoke-test design ran both a server `SceneMultiplayer` and the
  client `NetworkClient` autoload's connection in one process sharing one
  `SceneTree.root`. This silently produced wrong status transitions because
  Godot 4.3 has exactly one `MultiplayerAPI` per `SceneTree.root` — a
  server peer and a client peer cannot coexist there. Root-caused via
  isolated repro (see TDD evidence above) and fixed by spawning a real
  second OS process for the server in the smoke test, matching production
  topology instead of working around the constraint.

## Known limitation: no interactive GUI confirmation

All validation above is headless. No person has visually confirmed, in an
interactive Godot window, that the connection status Label text updates on
screen or that the blue `NetworkedPlayer` capsule renders and is visibly
distinct from the red local Player capsule in the fixed 3/4 isometric
camera view. The headless smoke test confirms the `NetworkedPlayer` node
exists in the scene tree with the correct type and material color values,
which is strong but not equivalent to a rendered-frame visual check. Tracked
as [DT-003](../TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result)
rather than left as a silent gap, consistent with Slice 001's identical
"Manual (interactive, GUI) editor run: not performed" note.
