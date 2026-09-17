# Slice 005: Predicted local movement with authoritative reconciliation
GitHub issue: #95

Tracker context: Phase 5 — Prediction and reconciliation proof; advances
[IP-001](../FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer).
Planning ticket: [game-vision issue 11](../.scratch/game-vision/issues/11-prediction-reconciliation.md).

## SDD

Goal: The red local `Player` continues to respond to local WASD input
immediately, with no wait on the network (unchanged feel from Slices
001–004). Each input sample it sends to the server is now tagged with a
monotonically increasing sequence number. The server (unchanged authority)
returns, alongside the authoritative position, the sequence number of the
latest input it has processed. The red `Player` uses that acknowledgement to
discard already-processed local input and replay only the still-unacknowledged
input on top of the authoritative position, so a correction never discards
input the server has not seen yet, and never re-applies input the server
already accounted for. The blue `NetworkedPlayer` — this same peer's
server-driven representation, introduced in Slice 002/004 — now moves toward
each incoming authoritative snapshot at a bounded speed instead of snapping to
it outright, so ordinary network jitter does not read as a visible teleport;
an extreme delta (larger than a configured snap distance) still snaps in one
frame rather than producing a long visible slide.

Domain boundary: This slice models exactly one connected Player, unchanged
from Slice 004 — no second peer's input or remote-player replication is
modeled. It does not change which side owns the authoritative position: the
server (`server/server_player_state.gd`) still computes and owns `position`
from accumulated intent and its own fixed tick speed; the client never sends a
position, and the red `Player`'s locally predicted position is always treated
as provisional, corrected on every authoritative snapshot. No persistence,
authentication, reconnect handling, or collision authority are added.

Public seam:
- `client/player.gd` (red predicted `Player`, extended):
  - `_physics_process(delta)` — unchanged responsiveness: still samples input
    and moves the node immediately every tick via the existing
    `get_planar_input()`/movement math, now also assigning the sample a
    sequence number (`_next_sequence`, incremented per tick), recording it in
    `_pending_inputs`, and calling
    `NetworkClient.submit_input_intent(intent, sequence)`.
  - `_on_authoritative_position_received(authoritative_position, last_processed_sequence)`
    — connected to `NetworkClient.authoritative_position_received` in
    `_ready()`. Discards every pending input with `sequence <=
    last_processed_sequence`, snaps `position` to `authoritative_position`,
    then replays the remaining unacknowledged inputs in order using the same
    movement math (`_apply_intent` + `move_and_slide()`), each with its
    originally recorded per-tick `delta`, so replay reproduces what the
    server will eventually compute for those same samples.
  - `_apply_intent(planar_input, delta)` — the shared movement math factored
    out of `_physics_process` so both the live tick and reconciliation replay
    use the exact same normalization and speed as
    `NetworkConfig.AUTHORITATIVE_MOVE_SPEED`-driven server integration
    (`move_speed` is still 5.0, matching the server constant, so replay tracks
    the server's own math rather than approximating it).
- `client/network_client.gd` (extended):
  - `submit_input_intent(intent: Vector2, sequence: int)` — now also RPCs the
    sequence number to the server.
  - `receive_input_intent_on_server(intent: Vector2, sequence: int)` —
    `@rpc("any_peer", "call_remote", "unreliable")`, forwards both to
    `ServerPlayerState.apply_input_intent`.
  - `receive_authoritative_position(position: Vector3, last_processed_sequence: int)`
    — `@rpc("authority", "call_remote", "unreliable")`; now relays both values
    via the widened `authoritative_position_received(position,
    last_processed_sequence)` signal instead of setting `NetworkedPlayer`'s
    position directly. This autoload only relays what the server sends —
    reconciliation (red) and smoothing (blue) each live in their own node
    script, not in this shared relay.
- `server/server_player_state.gd` (extended):
  - `apply_input_intent(sender_id, intent, sequence)` — now also verifies
    `sequence > _last_processed_sequence` before applying, so an
    out-of-order/stale unreliable-RPC delivery cannot regress the server's
    idea of the latest input; stores the accepted `sequence` in
    `_last_processed_sequence`.
  - `_physics_process(delta)` — unchanged integration math; now RPCs
    `_last_processed_sequence` alongside `position` in every
    `receive_authoritative_position` call.
- `client/networked_player_input.gd` (blue `NetworkedPlayer`, changed role):
  - No longer sends input intent itself (the red `Player`'s own
    `NetworkClient.submit_input_intent` call already reports this one peer's
    intent as part of its predict-then-reconcile loop; sending it twice would
    double-submit the same sequence space from two callers).
  - `_ready()` connects to `NetworkClient.authoritative_position_received` and
    records the incoming position as `_target_position`.
  - `_physics_process(delta)` moves this node toward `_target_position` at
    `NetworkConfig.NETWORKED_PLAYER_SMOOTH_SPEED` via `move_toward()`, unless
    the distance exceeds `NetworkConfig.NETWORKED_PLAYER_SNAP_DISTANCE`, in
    which case it snaps directly (bounding the worst case to one frame instead
    of a long visible slide).
- `shared/network_config.gd` — two new constants:
  `NETWORKED_PLAYER_SMOOTH_SPEED: float = 10.0` (units/second the blue
  representation may close distance toward a snapshot) and
  `NETWORKED_PLAYER_SNAP_DISTANCE: float = 15.0` (beyond this distance, snap
  instead of smoothing).

Inputs/outputs: the two RPCs added in Slice 004
(`receive_input_intent_on_server`, `receive_authoritative_position`) are
extended with one additional argument each (`sequence: int`, then
`last_processed_sequence: int`); no new RPC endpoints are introduced. The
client still never sends a position; the server still never accepts one.
Sequence numbers only ever identify which input sample an acknowledgement
covers — they carry no position or movement data themselves and cannot be
used to move a Player node directly.

Non-goals (explicit scope cut, per
[game-vision issue 11](../.scratch/game-vision/issues/11-prediction-reconciliation.md)):
no remote-player replication (still exactly one connected Player), no
persistence, no authentication, no reconnect handling, no collision authority,
no production anti-cheat policy, no world generation, no map, no saves, no
quests, no Ollama, no SQLite, no Docker, no broader multiplayer architecture
change. Interpolation for the blue representation is a simple bounded
`move_toward()`, not a buffered/delayed interpolation scheme — sufficient to
prove "smooth, no unbounded jump" per the acceptance evidence in issue 11
without over-building this slice.

Safety invariant: Unchanged from Slice 004 — localhost by default, no
external network calls beyond the existing ENet socket, no disk writes. The
server's existing sender-identity check (`sender_id == owning_peer_id`) is
unchanged; Slice 005 adds a second, independent guard
(`sequence > _last_processed_sequence`) so a stale or reordered unreliable
intent RPC cannot regress the server's applied input even if it did pass the
sender check. Both guards fail closed (discard the sample) rather than fail
open.

## BDD

### Normal path: local input is immediately responsive and later acknowledged in order

Given a connected client with a spawned `NetworkedPlayer` and its own red
`Player`
When the player holds a directional input
Then the red `Player` moves within the same or very next physics tick with no
wait on any server round trip, each sent input intent carries a strictly
increasing sequence number, and the server's authoritative snapshots
acknowledge those sequence numbers in non-decreasing order.

### Highest-risk: a forced authoritative correction converges the predicted Player without losing or duplicating input

Given the red `Player` has predicted ahead of the last authoritative snapshot
the server has acknowledged
When an authoritative snapshot arrives whose position disagrees with the
current prediction
Then the red `Player` discards every acknowledged pending input, snaps to the
authoritative position, and replays only the remaining unacknowledged inputs
— it never re-applies an already-acknowledged input on top of the new
snapshot, and never drops an input the server has not yet acknowledged.

### Safety: a stale or out-of-order input sample cannot regress the server's applied input

Given `ServerPlayerState._last_processed_sequence` already reflects a given
sequence number
When `apply_input_intent` is called with a `sequence` that is not strictly
greater than `_last_processed_sequence` (a stale or reordered unreliable
delivery)
Then the sample is discarded and `_input_intent`/`_last_processed_sequence`
are not updated from it.

### Regression: the blue NetworkedPlayer approaches snapshots smoothly, not instantly, and Slices 001–004 are unaffected

Given the blue `NetworkedPlayer` is at some position and a new, ordinary
(bounded-distance) authoritative snapshot arrives
When the next physics tick runs
Then the `NetworkedPlayer` has moved only part of the way toward the new
snapshot (not jumped to it outright) and continues to converge toward it over
subsequent ticks; and Slice 001's identity-gate/movement suite, Slice 002's
connection suite, Slice 003's LAN-config suite, and Slice 004's
authoritative-movement suite all still pass unchanged.

## TDD evidence

No GDScript test framework is installed yet
([DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
unchanged from Slices 001–004). The public seam is exercised by a new headless
integration smoke test, `scripts/test_prediction_reconciliation.gd`, following
the same real-second-OS-process pattern as
`scripts/test_client_server_connection.gd` and
`scripts/test_authoritative_movement.gd`: it spawns a real second process
running the unmodified production `server/server_main.gd`, connects the
client's real `NetworkClient` autoload against it over a real localhost ENet
socket, loads the real `client/gameplay.tscn` (including the real `Player` and
`NetworkedPlayer` instances), and drives input through the production input
path (`Input.action_press("move_back")`). Every assertion reads state
reachable from the documented public seam (`Player._next_sequence`,
`Player._pending_inputs.size()`, `Player.position`,
`NetworkClient.receive_authoritative_position()`, `NetworkedPlayer.position`),
not private engine internals.

The test proves, in order:
1. **Immediate local responsiveness** — the red `Player` moves within a
   couple of physics ticks of a held input, well before a real ~30-tick
   localhost server round trip could complete.
2. **Ordered sequence acknowledgement** — `Player._next_sequence` increments
   with each sent sample, and after enough ticks elapse, fewer inputs remain
   pending than were sent, proving the server acknowledged at least one
   sequence in order.
3. **Forced correction convergence** — the test calls
   `network_client.receive_authoritative_position()` directly (the exact
   method the production server RPC dispatches to) with a deliberately
   displaced position and a `last_processed_sequence` covering every sample
   sent so far, then asserts `Player.position` equals that forced position
   immediately (no replay left to run, since every pending input was already
   acknowledged) — proving reconciliation converges the prediction to the
   authoritative snapshot.
4. **Bounded blue smoothing** — after stopping the real server process (so
   its own genuine per-tick snapshots cannot race with and overwrite the
   test's injected one), the test sends the blue `NetworkedPlayer` an
   ordinary-distance snapshot and asserts it is *not* at the target after one
   tick (proving it did not teleport) but does converge to within 0.05 units
   of it within 60 ticks (proving it does not drift unboundedly either).

Two real races were found and fixed while writing this test, both isolation
issues in the test itself rather than defects in the production code:
- Asserting the forced red-Player correction after an `await process_frame`
  was flaky, because the real server connection was still live and its own
  genuine (much smaller) authoritative snapshot could arrive and overwrite
  the test's deliberately-displaced one before the check ran.
  `receive_authoritative_position()` is synchronous (position is set before
  the call returns), so the fix was to assert immediately after the direct
  call with no intervening awaited frame.
- The blue-smoothing convergence check was flaky even after killing the real
  server process, because `OS.kill()` ends the process but does not recall
  UDP packets it had already sent; one such stray in-flight snapshot could
  still land after the test's injected one and reset `_target_position`
  before the convergence loop finished observing it. Root-caused with
  temporary debug prints (removed before landing) showing the
  `NetworkedPlayer` freezing at exactly the pre-injection distance on some
  runs, consistent with one extra real snapshot landing and then no further
  updates arriving from the now-dead server. Fixed by draining 10 physics
  ticks after `OS.kill()` before sending the injected snapshot.
- The single-tick immediate-responsiveness check was also flaky on its own
  (unrelated to networking): whether `Input.action_press()` lands before or
  after the current physics frame already polled input is a real, harmless
  Godot scheduling race. Fixed by allowing up to a couple of ticks (still far
  fewer than the ~30-tick round-trip window used elsewhere in the same test)
  before asserting movement, which keeps "immediate, no network wait"
  meaningful without being sensitive to that scheduling race.

## ADR decision

No new ADR. This slice does not change which side owns the authoritative
position — the server remains sole owner, exactly as
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md) already
scoped and Slice 004 already implemented; it implements exactly the Phase 5
exit gate already described in `docs/PROJECT-TRACKER.md` ("The client
responds immediately to local input, acknowledges ordered server snapshots,
reconciles prediction drift, and smoothly renders authoritative movement
without remote-player replication or persistence") and the decision boundary
already recorded in
[game-vision issue 11](../.scratch/game-vision/issues/11-prediction-reconciliation.md).
Sequence-number bookkeeping and bounded `move_toward()` smoothing are ordinary
client-side prediction/reconciliation implementation details, not a
standalone architectural or authority decision.

## Validation

Run from the repository root (`/data/code/project0`):

- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project (including the updated `client/player.gd`,
  `client/network_client.gd`, `client/networked_player_input.gd`,
  `server/server_player_state.gd`, `shared/network_config.gd`, and the new
  `scripts/test_prediction_reconciliation.gd`) opens and closes cleanly under
  the editor codepath with no import or parse errors.
- `godot --headless --path . --check-only -s shared/network_config.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s server/server_player_state.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s server/server_main.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s client/network_client.gd`: PASS,
  exit 0.
- `godot --headless --path . --check-only -s client/player.gd`: FAILS with
  "Identifier not found: NetworkClient", exit 1. Same documented non-defect as
  Slices 001–004: `--check-only -s` parses a single script without starting a
  `SceneTree`, so `[autoload]` singletons are never registered as global
  identifiers under that check. Confirmed identical by re-running `godot
  --headless --path . --check-only -s client/connection_status.gd` (also
  FAILS the same way, unchanged since Slice 002) as a same-repo control.
  Corroborated as a non-defect by the editor check above and the runtime
  checks below, where the autoload resolves and the scene runs cleanly.
- `godot --headless --path . --check-only -s client/networked_player_input.gd`:
  Same documented non-defect as above (FAILS with the identical
  "Identifier not found: NetworkClient" under `--check-only -s`); confirmed
  non-defect the same way.
- `godot --headless --path . --check-only -s scripts/test_prediction_reconciliation.gd`:
  PASS, exit 0.
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`
  (Slice 001 regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_client_server_connection.gd`
  (Slice 002 regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_lan_config.gd` (Slice 003
  regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_authoritative_movement.gd`
  (Slice 004 regression): **ALL PASS**, exit 0 — still passes with the blue
  `NetworkedPlayer` now smoothing instead of snapping, because the test's
  30-tick hold + 30-tick settle window is generous relative to
  `NETWORKED_PLAYER_SMOOTH_SPEED`.
- `godot --headless --path . -s scripts/test_prediction_reconciliation.gd`
  (new Slice 005 smoke test): **ALL PASS**, exit 0, run 3 times consecutively
  with no flakiness observed after the fixes described in the TDD evidence
  section above. All 11 assertions passed each run: server starts and stays
  running; client connects and both the red `Player` and blue
  `NetworkedPlayer` exist; the red `Player` moves within a couple of physics
  ticks of held input, well before a server round trip could complete;
  `Player._next_sequence` increments (monotonically increasing sequence
  numbers); fewer inputs remain pending than were sent (ordered
  acknowledgement); the predicted position advanced before any correction; a
  forced authoritative correction converges the red `Player` exactly to the
  server snapshot; the blue `NetworkedPlayer` does not teleport to an
  ordinary-distance snapshot on the very first tick; it moves only partway on
  that first tick; and it converges to within 0.05 units of the snapshot
  within 60 ticks. This is the slice's primary acceptance evidence for the
  BDD normal path, highest-risk reconciliation scenario, and blue-smoothing
  regression scenario.

### Client test procedure

The client can be tested manually on a machine with a Godot window, extending
Slice 004's procedure:

1. From the project root, start the server and leave it running:
   `godot --headless --path . -s server/server_main.gd`
2. In a second terminal, start the client project with `godot --path .
   --editor` and run the project, or use the Godot editor's Play button.
3. Enter a display name at the identity gate and select **Enter**.
4. Confirm the status label reaches `Server: connected: player spawned` and
   both the red local Player and blue networked Player are visible.
5. Hold W/A/S/D. The red local Player should move exactly as responsively as
   in Slices 001–004 (no perceptible input lag). The blue `NetworkedPlayer`
   should now visibly trail the red Player's predicted position by a small,
   smoothly-closing gap (reflecting real network round-trip delay) rather
   than the Slice 004 behavior of jumping directly to each authoritative
   update. Release input and confirm the red Player settles without drifting
   or jittering once the server's snapshots catch up to the last sent input.

### Interactive GUI & Two-Machine LAN Validation

- Date: 2026-09-12
- Outcome: User verified interactive GUI rendering and physical two-machine LAN run. Confirmed local prediction responsiveness, server acknowledgement, position reconciliation, and smooth blue `NetworkedPlayer` tracking under WASD input. Closes [DT-003](../TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result) and [DT-004](../TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003).
unverified until DT-004's physical two-machine run is performed.
