# Slice 004: Server-authoritative movement for one connected Player

Tracker context: Phase 4 — Authoritative movement proof; advances
[IP-001](../FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer).
Planning ticket: [game-vision issue 09](../.scratch/game-vision/issues/09-authoritative-player-movement.md).

## SDD

Goal: The one connected client sends directional WASD input intent to the
server; the server owns that connected Player's position and applies a fixed
movement speed on its own tick; the server sends the resulting authoritative
position back to the owning client; the client's blue `NetworkedPlayer`
displays that returned position. No client prediction, reconciliation,
interpolation, remote-player replication, collision authority, anti-cheat
policy, authentication, reconnect, or persistence.

Domain boundary: This slice only moves the existing blue `NetworkedPlayer`
representation introduced in Slice 002, under server authority. It does not
touch the existing red local `Player` node or its client-side movement
(`client/player.gd`, still governed by
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md) — that ADR's
scope is unchanged by this slice). It models exactly one connected Player, per
the decision boundary in
[game-vision issue 09](../.scratch/game-vision/issues/09-authoritative-player-movement.md);
a second concurrent peer's input is not modeled.

Public seam:
- `client/networked_player_input.gd` (attached to `NetworkedPlayer` in
  `client/networked_player.tscn`) — samples the same four directional input
  actions used by `client/player.gd` every `_physics_process` tick and calls
  `NetworkClient.submit_input_intent(Vector2)`.
- `client/network_client.gd`:
  - `submit_input_intent(intent: Vector2)` — public seam called by the client
    each physics tick; RPCs `receive_input_intent_on_server` on this client's
    own `NetworkClient` node (`rpc_id(1, ...)`), which Godot's multiplayer API
    delivers to the server's `NetworkClient` instance at the same
    `/root/NetworkClient` path.
  - `receive_input_intent_on_server(intent: Vector2)` — `@rpc("any_peer",
    "call_remote", "unreliable")`; runs server-side only, identifies the
    caller via `multiplayer.get_remote_sender_id()`, and forwards to the
    server-only `ServerPlayerState` node with a plain in-process call (no
    second RPC hop needed — same process).
  - `receive_authoritative_position(position: Vector3)` — `@rpc("authority",
    "call_remote", "unreliable")`; called by the server on the owning client
    only, sets `NetworkedPlayer.position` directly.
- `server/server_player_state.gd` (new) — a `Node` created by
  `server/server_main.gd` on peer connect, owning `owning_peer_id` and
  `position` for exactly one connected Player.
  - `start_for_peer(peer_id, start_position)` — binds the node to a newly
    connected peer.
  - `apply_input_intent(sender_id, intent)` — plain in-process call from
    `NetworkClient.receive_input_intent_on_server`; verifies `sender_id ==
    owning_peer_id` before storing the intent.
  - `_physics_process(delta)` — integrates `position` at
    `NetworkConfig.AUTHORITATIVE_MOVE_SPEED` (fixed, 5.0 units/second) each
    server tick and RPCs the result back via
    `NetworkClient.receive_authoritative_position`.
- `server/server_main.gd` — `_on_peer_connected` now also creates/starts the
  `ServerPlayerState` node (named `ServerPlayerState`, added under `root`);
  `_on_peer_disconnected` unbinds it from that peer.
- `shared/network_config.gd` — new `AUTHORITATIVE_MOVE_SPEED: float = 5.0`
  constant, the single source of truth for the server's fixed tick speed.

Inputs/outputs: the client never sends a requested position — only a `Vector2`
directional intent, sampled from the same `move_forward`/`move_back`/
`move_left`/`move_right` input actions `client/player.gd` uses. The server
never accepts a client-supplied position; it only ever computes one from
accumulated intent and its own fixed speed and tick `delta`. The only new
wire messages are the two RPCs above (`receive_input_intent_on_server`,
`receive_authoritative_position`); port, connection flow, and Slice 002/003
status strings are unchanged.

Non-goals (explicit scope cut, per user direction and
[game-vision issue 09](../.scratch/game-vision/issues/09-authoritative-player-movement.md)):
no client prediction, no reconciliation, no interpolation, no remote-player
replication (still exactly one connected Player), no collision authority, no
anti-cheat policy, no authentication, no reconnect handling, no persistence,
no world generation, no map, no saves, no quests, no Ollama, no SQLite, no
Docker deployment, no production art. The existing red local `Player` node and
`client/player.gd` are unmodified.

Safety invariant: Same as Slice 002/003 — localhost by default, no external
network calls beyond the ENet socket, no disk writes. The server verifies the
RPC sender against `owning_peer_id` before applying intent
(`apply_input_intent`), so a second peer cannot move the first peer's Player
by forging an intent RPC while the first peer is connected; this is a scoped
sender check, not a general anti-cheat policy (explicitly out of scope above).

## BDD

### Normal path: input intent moves the authoritative position

Given a connected client with a spawned `NetworkedPlayer`
When the player holds a directional input (e.g. `move_back`)
Then `client/networked_player_input.gd` reports that intent to the server
every physics tick, the server's `ServerPlayerState` integrates `position` at
`AUTHORITATIVE_MOVE_SPEED` along that direction, and the server's returned
position moves the client's `NetworkedPlayer` node accordingly — with no
movement applied to the existing red local `Player`.

### Highest-risk: a stale or unbound sender cannot move another peer's Player

Given `ServerPlayerState.owning_peer_id` is bound to peer A (or unbound, after
peer A disconnects)
When `apply_input_intent` is called with a `sender_id` that does not match
`owning_peer_id`
Then the intent is discarded and `position` is not updated from it.

### Regression: the local red Player is unaffected

Given the existing Slice 001 local `Player` node and its client-side movement
When Slice 004's server-authoritative RPCs run
Then `client/player.gd` is unmodified and Slice 001's regression suite
(`scripts/test_identity_gate_and_movement.gd`) passes unchanged.

## TDD evidence

No GDScript test framework is installed yet
([DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
unchanged from Slices 001–003). The public seam is exercised by a new headless
integration smoke test, `scripts/test_authoritative_movement.gd`, following the
same real-second-OS-process pattern as
`scripts/test_client_server_connection.gd` and `scripts/test_lan_config.gd`:
it spawns a real second process running the unmodified production
`server/server_main.gd`, connects the client's real `NetworkClient` autoload
against it over a real localhost ENet socket, loads the real
`client/gameplay.tscn` (including the real `NetworkedPlayer` instance and its
`client/networked_player_input.gd` script), and drives input through the
production input path: `Input.action_press("move_back")` /
`Input.action_release("move_back")`, the same `Input` singleton
`client/player.gd` and `client/networked_player_input.gd` both read. This is
not a private-method-only assertion: every assertion reads state reachable
from the documented public seam (`NetworkClient.status`, the `NetworkedPlayer`
node's `position` in the scene tree).

An initial version of this test called `NetworkClient.submit_input_intent()`
directly instead of using `Input.action_press()`. That version was a false
negative: it raced against `networked_player_input.gd`'s own concurrent
per-tick polling of the (real, unpressed) `Input` actions, which kept
overwriting the test's injected intent with zero on alternating ticks,
starving the server's integration almost to zero movement. Root-caused via
temporary debug instrumentation (removed before landing) that showed the RPC
chain delivering correctly in both directions and the server's position
integrating correctly, but the *intent value itself* flapping between the
test's value and the polling node's zero. Fixed by having the test press the
real input action instead of calling the internal seam directly, which
removes the second writer entirely and also exercises more of the real
production path.

## ADR decision

No new ADR. This slice does not change movement authority for the existing red
local Player (still governed by
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md)); it
implements exactly the Phase 4 exit gate already described in
`docs/PROJECT-TRACKER.md` ("One connected client sends WASD intent, the server
owns and updates that Player position, and the client displays the returned
authoritative position without prediction or interpolation") and the decision
boundary already recorded in
[game-vision issue 09](../.scratch/game-vision/issues/09-authoritative-player-movement.md).
The RPC-node-path mechanism (routing the client→server hop through the
symmetric `NetworkClient` autoload, which forwards to the server-only
`ServerPlayerState` node via a plain in-process call) is an ordinary Godot
high-level multiplayer implementation detail — the same pattern Slice 002
already established for `spawn_local_player_representation` — not a
standalone architectural decision requiring its own ADR.

## Validation

Run from the repository root (`/data/code/project0`):

- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project (including the new `server/server_player_state.gd`,
  `client/networked_player_input.gd`,
  `scripts/test_authoritative_movement.gd`, and the updated
  `shared/network_config.gd`, `server/server_main.gd`,
  `client/network_client.gd`, `client/networked_player.tscn`) opens and closes
  cleanly under the editor codepath with no import or parse errors.
- `godot --headless --path . --check-only -s shared/network_config.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s server/server_main.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s server/server_player_state.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s client/network_client.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s client/networked_player_input.gd`:
  FAILS with "Identifier not found: NetworkClient", exit 1. Same root cause
  already documented in Slices 001–002 for `client/identity_gate.gd` and
  `client/connection_status.gd`: `--check-only -s` parses a single script
  without starting a `SceneTree`, so `[autoload]` singletons are never
  registered as global identifiers under that check. Confirmed identical by
  re-running `godot --headless --path . --check-only -s
  client/connection_status.gd` (also FAILS the same way, unchanged from
  Slice 002) as a same-repo control. Corroborated as a non-defect by the
  runtime checks below, where the autoload resolves and the scene runs
  cleanly.
- `godot --headless --path . --check-only -s client/player.gd`: PASS, exit 0
  — confirms the existing red local Player script is unmodified and still
  parses cleanly.
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`
  (Slice 001 regression): **ALL PASS**, exit 0 — all 6 assertions pass
  unchanged.
- `godot --headless --path . -s scripts/test_client_server_connection.gd`
  (Slice 002 regression): **ALL PASS**, exit 0 — all 8 assertions pass
  unchanged.
- `godot --headless --path . -s scripts/test_lan_config.gd` (Slice 003
  regression): **ALL PASS**, exit 0 — all 8 assertions pass unchanged.
- `godot --headless --path . -s scripts/test_authoritative_movement.gd`:
  **ALL PASS**, exit 0. All 7 assertions passed, run 3 times consecutively
  with no flakiness observed: server process starts; server process is still
  running after startup; the client connects and its `NetworkedPlayer` is
  spawned; the `NetworkedPlayer` exists before input is sent; the
  `NetworkedPlayer`'s position changed after the server received input
  intent; it moved only along the intended +Z axis (not an arbitrary
  client-set value); it moved in the +Z direction matching the held
  `move_back` input. This is the slice's primary acceptance evidence for the
  BDD normal path.

### Client test procedure

The client can be tested manually on a machine with a Godot window, extending
Slice 002/003's procedure:

1. From the project root, start the server and leave it running:
   `godot --headless --path . -s server/server_main.gd`
2. In a second terminal, start the client project with `godot --path .
   --editor` and run the project, or use the Godot editor's Play button.
3. Enter a display name at the identity gate and select **Enter**.
4. Confirm the status label reaches `Server: connected: player spawned` and
   both the red local Player and blue networked Player are visible.
5. Hold W/A/S/D. The red local Player continues to move exactly as in Slice
   001 (unchanged, client-side only). The blue `NetworkedPlayer` should also
   move, following the same fixed speed, driven by the server's authoritative
   tick rather than local prediction — expect a small, real network round-trip
   delay before it starts moving and after input is released, since there is
   no prediction or interpolation in this slice.

### Interactive GUI & Two-Machine LAN Validation

- Date: 2026-09-12
- Outcome: User verified interactive GUI rendering and physical two-machine LAN run. Confirmed blue `NetworkedPlayer` moves authoritatively under WASD input alongside the red local Player. Closes [DT-003](../TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result) and [DT-004](../TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003).

This slice's server-authoritative movement logic has not been exercised over
a real physical LAN link between a Windows client and a Linux server, matching
the same unresolved gap already tracked as
[DT-004](../TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
for Slice 003. All validation in this slice ran on a single Linux host
(localhost ENet sockets between two real OS processes). The RPC and tick logic
added here do not depend on LAN vs. localhost transport, so no new debt item is
opened for this slice specifically; DT-004 already covers the outstanding
physical two-machine run for the current network stack as a whole.
