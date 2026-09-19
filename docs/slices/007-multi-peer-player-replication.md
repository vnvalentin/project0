# Slice 007: Two-client Player replication and disconnect cleanup
GitHub issue: #95

Tracker context: Phase 7 — Multi-peer Player replication; advances
[P-016](../FEATURE-LIST.md#p-016-multi-peer-player-replication).
Planning ticket: [game-vision issue 13](../.scratch/game-vision/issues/13-multi-peer-player-replication.md).

## SDD

Goal: Exactly two connected clients each get a distinct, server-owned
authoritative Player state and a distinct visible representation of the
other peer, so Client A sees Client B move and Client B sees Client A move,
through server authority — with each owning client's existing Slice 005
prediction/reconciliation and Slice 004 authoritative-smoothing behavior for
its own Player unchanged. A third concurrent connection attempt is rejected.
Disconnecting one peer removes exactly that peer's representation from the
remaining peer's client without crashing it.

Domain boundary: This slice extends the existing single-peer authoritative
model (Slice 004/005) to exactly two peers. It does not add matchmaking,
authentication, reconnect handling, persistence, world generation, quests,
Ollama, SQLite, Docker, arbitrary player counts, or production anti-cheat —
all explicitly out of scope per
[game-vision issue 13](../.scratch/game-vision/issues/13-multi-peer-player-replication.md).
It does not change which side owns the authoritative position (still the
server, per [ADR 0001](../adr/0001-client-side-authority-for-first-slice.md)
and Slice 004/005) and does not change the existing red predicted
`Player`/blue `NetworkedPlayer` behavior for the owning client.

Public seam:
- `server/server_main.gd`:
  - `_player_states: Dictionary` (peer id → `ServerPlayerState`) replaces the
    single shared `_player_state` node from Slices 004/005, so two connected
    peers never share one node's mutable position/input-sequence state.
  - `_on_peer_connected(peer_id)` — rejects a third concurrent peer
    (`MAX_REPLICATED_PEERS = 2`) by disconnecting it immediately with no
    `ServerPlayerState` created and no spawn RPC sent; for an accepted peer,
    creates that peer's own `ServerPlayerState` at a deterministic,
    slot-based start position (`_start_position_for_slot`), RPCs the new
    peer to spawn its own representation
    (`spawn_own_player_representation`), then RPCs a
    `spawn_remote_player_representation(other_peer_id, position)` call in
    both directions for every other already-connected peer — the new peer
    learns about each existing peer, and each existing peer learns about the
    new one. No representation node is ever shared between two peers; each
    RPC names the specific peer id it is about.
  - `_on_peer_disconnected(peer_id)` — frees that peer's `ServerPlayerState`
    entirely (previously just unbound a shared instance) and RPCs
    `despawn_remote_player_representation(peer_id)` to every remaining peer.
  - `_on_player_state_position_updated(peer_id, position)` — connected to
    each `ServerPlayerState.position_updated` signal; relays that peer's
    latest authoritative position to every *other* connected peer via
    `receive_remote_player_position`, never back to the owning peer (which
    already gets its own position plus sequence-ack via the unchanged
    `receive_authoritative_position` path).
- `server/server_player_state.gd`:
  - New `position_updated(peer_id, updated_position)` signal, emitted once
    per physics tick alongside the existing owning-peer RPC, so
    `server_main.gd` can broadcast replication without this node knowing
    about other peers. No other behavior changed — per-peer position
    integration, input-sequence verification, and the owning-peer RPC are
    identical to Slice 005.
- `client/network_client.gd`:
  - `spawn_own_player_representation()` — renamed from Slice 002/004's
    `spawn_local_player_representation()` to contrast explicitly with the
    new remote-spawn RPC below; behavior unchanged.
  - `spawn_remote_player_representation(peer_id, start_position)` —
    `@rpc("authority", "call_remote", "reliable")`; instantiates
    `client/remote_player.tscn` as a child named `RemotePlayer_<peer_id>`
    under a dedicated `RemotePlayers` container in the gameplay scene,
    seeded at `start_position`. Idempotent by node-name check, matching the
    existing `spawn_own_player_representation` pattern.
  - `despawn_remote_player_representation(peer_id)` —
    `@rpc("authority", "call_remote", "reliable")`; frees only that peer's
    `RemotePlayer_<peer_id>` node if present; a no-op if already gone.
  - `receive_remote_player_position(peer_id, position)` —
    `@rpc("authority", "call_remote", "unreliable")`; relays via the new
    `remote_player_position_received(peer_id, position)` signal. Carries no
    sequence number — this is one-way rendering data for another peer, never
    this client's own prediction/reconciliation input.
  - `receive_input_intent_on_server` now looks up the sender's own
    `ServerPlayerState_<sender_id>` node (Slice 007 naming) instead of one
    shared `ServerPlayerState` name.
- `client/remote_player.gd` (new) + `client/remote_player.tscn` (new) — one
  instance per remote peer id, never shared between two peers. Smooths
  toward each incoming `remote_player_position_received` snapshot the same
  bounded way the owning client's own blue `NetworkedPlayer` does
  (`NetworkConfig.NETWORKED_PLAYER_SMOOTH_SPEED`/`NETWORKED_PLAYER_SNAP_DISTANCE`,
  unchanged constants, reused rather than duplicated). Rendered as a yellow
  capsule, visually distinct from the local red `Player` and the owning
  client's own blue `NetworkedPlayer`.
- `client/gameplay.tscn` — legend extended with a third row ("Yellow: Other
  peer"); the existing blue-row label reworded to "Blue: You
  (server-authoritative)" for clarity now that blue and yellow are both
  server-driven but represent different peers. No gameplay node changed.

Inputs/outputs: two new reliable RPCs
(`spawn_remote_player_representation`, `despawn_remote_player_representation`)
and one new unreliable RPC (`receive_remote_player_position`) are added; the
existing `receive_input_intent_on_server`/`receive_authoritative_position`
wire shapes from Slice 004/005 are unchanged. The client still never sends a
position, only intent; the server still never accepts one. A peer only ever
receives `receive_remote_player_position` calls for *other* peers, never for
itself.

Non-goals (explicit scope cut, per
[game-vision issue 13](../.scratch/game-vision/issues/13-multi-peer-player-replication.md)):
matchmaking, authentication, reconnect handling, persistence, world
generation, quests, Ollama, SQLite, Docker, arbitrary player counts (hard
capped at 2 via `MAX_REPLICATED_PEERS`), and production anti-cheat. Existing
LAN host configuration (Slice 003), the Compatibility/`gl_compatibility`
renderer, the portable Windows package (Slice 006), and server authority are
all unchanged.

Safety invariant: Unchanged localhost-by-default/no-external-calls/no-disk-
write posture from Slices 002–005. `ServerPlayerState.apply_input_intent`'s
existing `sender_id == owning_peer_id` and `sequence >
_last_processed_sequence` guards are unaffected by having multiple
`ServerPlayerState` instances — each instance still only accepts input from
its own bound peer. A third connection attempt is rejected (fail closed) at
the server rather than silently accepted with undefined behavior, since this
slice's proof and its test are scoped to exactly two peers
(`MAX_REPLICATED_PEERS`). This is a scoped concurrency cap for this proof,
not a production capacity or anti-cheat policy.

## BDD

### Normal path: two peers connect and replicate each other's movement

Given a headless server is running and two clients (A and B) connect
When Client A holds a directional input
Then Client A's own red/blue Players move exactly as in Slices 004/005, and
Client B's `RemotePlayer_<A's peer id>` node moves to match Client A's
server-authoritative position — and the same holds symmetrically for
Client B's input reaching Client A's `RemotePlayer_<B's peer id>` node.

### Highest-risk: disconnect cleanup does not crash the remaining peer

Given Client A and Client B are both connected, each seeing the other's
`RemotePlayer` representation
When Client A disconnects (including an abrupt process kill with no
graceful ENet disconnect packet)
Then the server frees Client A's `ServerPlayerState` and RPCs Client B to
despawn `RemotePlayer_<A's peer id>`; Client B's process keeps running,
remains connected, and its own Player/NetworkedPlayer are unaffected.

### Safety: a third connection attempt is rejected, not silently accepted

Given two peers are already connected (`MAX_REPLICATED_PEERS` reached)
When a third client attempts to connect
Then the server disconnects that third peer immediately in
`_on_peer_connected`, before creating a `ServerPlayerState` or sending any
spawn RPC for it, rather than silently accepting a third peer with undefined
replication behavior.

### Regression: Slices 001–005 are unaffected

Given the existing Slice 001–005 smoke tests
When they are re-run after this slice's changes
Then all pass unchanged, proving the per-peer `ServerPlayerState` refactor
and the renamed `spawn_own_player_representation` RPC preserve single-peer
authoritative movement, prediction, and reconciliation exactly as before.

## TDD evidence

No GDScript test framework is installed yet
([DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
unchanged from Slices 001–006). The public seam is exercised by a new
headless integration smoke test, `scripts/test_multi_peer_replication.gd`,
which spawns **three real OS processes**: the unmodified production
`server/server_main.gd`, and two instances of a new test-only harness,
`scripts/multi_peer_client_harness.gd`. Godot 4.3 allows only one
`MultiplayerAPI` peer per `SceneTree.root` (the same constraint documented in
Slice 002), so two concurrently connected clients cannot run in the
orchestrator's own process, and the orchestrator itself cannot also be one of
the two clients while independently polling both.

The harness is a faithful client instance, not a stub: it loads the real
`client/gameplay.tscn`, connects via the real
`NetworkClient.connect_to_server()`, and drives input via
`Input.action_press()` on the same production input path
`client/networked_player_input.gd`/`client/player.gd` read — the same
pattern already validated in `scripts/test_authoritative_movement.gd` and
`scripts/test_prediction_reconciliation.gd`. Because Godot does not expose
live stdout streaming from a process started with `OS.create_process()`, the
harness periodically writes its own observable public-seam state
(`NetworkClient.status`, its own `Player`/`NetworkedPlayer` positions, and
every currently-spawned `RemotePlayer_<peer_id>` node's position) to a JSON
state file; the orchestrator polls that file rather than reaching into any
process-internal state. Every assertion in the orchestrator reads only
values a real client also exposes at its public seam.

The orchestrator proves, in order:
1. The server process starts and stays running.
2. Both client harness processes start, connect, and each reaches
   `"connected: player spawned"` with its own distinct red
   `Player`/blue `NetworkedPlayer` representations present.
3. Each client sees exactly one `RemotePlayer` node for the other peer (not
   zero, not more than one).
4. Movement from Client B (holding `move_right`) changes Client A's view of
   B's `RemotePlayer` position by a real distance from its pre-movement
   baseline, and symmetrically for movement from Client A (holding
   `move_back`) reaching Client B's view of A.
5. Killing Client A's process (`OS.kill()`, an abrupt disconnect with no
   graceful ENet packet) eventually results in Client B's `RemotePlayer`
   for A being removed, and Client B's own process is still running
   afterward.

Two real issues were found and fixed while writing this test, both in the
test's own assertion design rather than in the production replication code:
- The first "movement reaches the other peer" attempt compared each remote
  peer's *absolute* rendered coordinate against a fixed axis threshold. This
  produced a false failure: each peer's actual start position depends on
  connection order (`server_main.gd`'s `_start_position_for_slot` assigns
  `(3,1,3)` or `(-3,1,-3)` depending on which peer connects first, not a
  fixed origin), so a peer's absolute Z or X coordinate after moving could
  still be numerically small even after real movement. Root-caused by
  printing the raw state dictionaries and noticing Client A's own predicted
  `Player` position included a nonzero X component inherited from its
  server-assigned start slot. Fixed by recording each remote peer's
  position immediately after both peers are confirmed connected as a
  baseline, then asserting on **distance moved from that baseline** instead
  of an absolute-coordinate threshold — correct regardless of which peer
  claims which start slot.
- The disconnect-cleanup wait initially polled a fixed number of
  `process_frame` iterations (300). This was flaky: a headless `SceneTree`
  with nothing to render can iterate `process_frame` far faster than real
  time, while ENet's server-side detection of an abruptly killed peer (no
  graceful disconnect packet, since `OS.kill()` is a `SIGKILL`) depends on a
  real wall-clock peer-timeout heartbeat, not an engine frame count. Fixed
  by switching that specific wait to poll against a real wall-clock deadline
  (`Time.get_ticks_msec()`) instead of a frame count, so the wait reliably
  outlasts ENet's own timeout instead of racing it. The two-way-movement
  waits earlier in the same test do not need this fix, since they wait on
  the server's own tick cadence via `physics_frame`, which does correspond
  to real simulation progress.

## ADR decision

No new ADR. This slice does not change which side owns the authoritative
position (still the server, unchanged from
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md) and Slice
004/005); it implements exactly the Phase 11 exit gate already described in
`docs/PROJECT-TRACKER.md` ("Two clients connect to one server, see distinct
Players, observe each other's authoritative movement, and clean up a
disconnected Player") and the decision boundary already recorded in
[game-vision issue 13](../.scratch/game-vision/issues/13-multi-peer-player-replication.md).
Moving from one shared `ServerPlayerState`/`NetworkedPlayer` to a
Dictionary-keyed-by-peer-id server state and a distinct
`RemotePlayer_<peer_id>` client node per remote peer is an ordinary Godot
high-level multiplayer implementation detail extending the same RPC-node-path
pattern Slice 002 already established, not a standalone architectural
decision.

## Validation

Run from the repository root (`/data/code/project0`):

- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project (including the updated `server/server_main.gd`,
  `server/server_player_state.gd`, `client/network_client.gd`,
  `client/gameplay.tscn`, and the new `client/remote_player.gd`,
  `client/remote_player.tscn`, `scripts/multi_peer_client_harness.gd`,
  `scripts/test_multi_peer_replication.gd`) opens and closes cleanly under
  the editor codepath with no import or parse errors.
- `godot --headless --path . --check-only -s shared/network_config.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s server/server_main.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s server/server_player_state.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s client/network_client.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s scripts/multi_peer_client_harness.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s scripts/test_multi_peer_replication.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s client/remote_player.gd`: FAILS
  with "Identifier not found: NetworkClient", exit 1. Same documented
  non-defect as `client/player.gd`/`client/networked_player_input.gd` since
  Slice 001–005: `--check-only -s` parses a single script without starting a
  `SceneTree`, so `[autoload]` singletons are never registered as global
  identifiers under that check. Confirmed identical by re-running the same
  check against `client/networked_player_input.gd` (also fails the same way,
  unchanged from Slice 004) as a same-repo control. Corroborated as a
  non-defect by the editor check above and the runtime checks below, where
  the autoload resolves and the scene runs cleanly.
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`
  (Slice 001 regression): **ALL PASS**, exit 0, 6 assertions.
- `godot --headless --path . -s scripts/test_client_server_connection.gd`
  (Slice 002 regression): **ALL PASS**, exit 0, 7 assertions.
- `godot --headless --path . -s scripts/test_lan_config.gd` (Slice 003
  regression): **ALL PASS**, exit 0, 8 assertions.
- `godot --headless --path . -s scripts/test_authoritative_movement.gd`
  (Slice 004 regression): **ALL PASS**, exit 0, 7 assertions.
- `godot --headless --path . -s scripts/test_prediction_reconciliation.gd`
  (Slice 005 regression): **ALL PASS**, exit 0, 14 assertions.
- `godot --headless --path . -s scripts/test_multi_peer_replication.gd`
  (new Slice 007 smoke test): **ALL PASS**, exit 0, 15 assertions, run 3
  times consecutively with no flakiness observed after the two fixes
  described in the TDD evidence section above: server process starts and
  stays running; both client harness processes start; both clients connect
  and spawn their own distinct Player representations; each client sees
  exactly one remote-peer representation; movement from Client B reaches
  Client A's view of B; movement from Client A reaches Client B's view of A;
  killing Client A's process removes its `RemotePlayer` from Client B;
  Client B's process keeps running and remains connected afterward. This is
  the slice's primary acceptance evidence for the BDD normal path and
  highest-risk disconnect scenario.

### Client test procedure

The client can be tested manually on two machines (or two windows on one
machine) with a Godot window, extending Slice 005's procedure:

1. From the project root, start the server and leave it running:
   `godot --headless --path . -s server/server_main.gd`
2. Start two separate client instances (two terminals/windows), each running
   `godot --path . --editor` and pressing Play, or two launches of the
   packaged Windows client pointed at the same server via `--server-host=`.
3. Enter a display name at each client's identity gate and select **Enter**.
4. Confirm each client's status label reaches `Server: connected: player
   spawned`.
5. Confirm each client shows three capsules: its own red predicted `Player`,
   its own blue server-driven `NetworkedPlayer`, and one yellow
   `RemotePlayer` representing the other client's peer.
6. Hold WASD on one client and confirm the yellow `RemotePlayer` on the
   *other* client's screen moves to follow it (with a small network
   round-trip delay, smoothed the same way the blue `NetworkedPlayer`
   smooths). Repeat from the other client.
7. Close one client and confirm its yellow `RemotePlayer` disappears from
   the remaining client's screen without that client crashing or losing its
   own connection.

### Interactive GUI & Two-Machine LAN Validation

- Date: 2026-09-12
- Outcome: User verified interactive GUI rendering and physical two-machine LAN run with multiple peers. Confirmed yellow `RemotePlayer` capsule rendering, peer movement replication, and clean despawn on disconnect. Closes [DT-003](../TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result) and [DT-004](../TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003).
