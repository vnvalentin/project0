# Slice 013: Melee strike visual indicator and player facing
GitHub issue: #95

Tracker context: Phase 12 — Authoritative runtime and action input; advances
[IP-015](../FEATURE-LIST.md#ip-015-authoritative-action-input) with the
cosmetic presentation half of Slice 012's authoritative melee strike, per the
melee-combat decision map's ("Not yet specified" section) deferred item on
"exact input bindings, client prediction/presentation, animation, sound, VFX,
and camera feedback for melee actions"
([melee-combat map](../.scratch/melee-combat/map.md)).

## SDD

Goal: give the existing server-authoritative melee strike (Slice 012) a
visible presentation on every observing client — the attacking Player visibly
turns to face its last movement direction, and a bright cyan line extends
2.0 m in front of it for the duration of the strike's `ACTIVE` phase, both for
the local attacker and for every other connected peer watching a
`RemotePlayer` representation — without adding any new authoritative state,
damage, HP, or inventory concept.

Public seams:

- `client/melee_strike_visual.gd` / `client/melee_strike_visual.tscn` — a
  small reusable cosmetic component: a `Node3D` that builds a bright
  cyan/white emissive line mesh extending
  `CombatContracts.generic_sword_archetype().reach_meters` (2.0 m) down its
  parent's local `-Z`, exposing `start_swing()`/`end_swing()` to show/hide it.
  Never reads authoritative state and never decides an outcome — purely a
  caller-driven visibility toggle, matching `client/target_dummy.gd`'s
  existing "render only what the caller already decided" pattern.
- `client/player.gd` — rotates the local Player each physics tick toward its
  current WASD movement vector (`_face_movement_direction`, bounded by the
  new `NetworkConfig.FACING_TURN_RATE`), so `-global_transform.basis.z` tracks
  the last moved direction and holds it when input stops. The existing
  `_start_predicted_attack()` already submitted `-global_transform.basis.z`
  as the intent's `aim_direction`; that value is now meaningful because the
  node actually turns. A `MeleeStrikeVisual` child is shown for the predicted
  `ACTIVE` phase only (`_set_predicted_phase`), corrected the same way the
  existing predicted locomotion slowdown already is on rejection.
- `client/remote_player.gd` — rotates toward its own smoothed-movement
  direction the same bounded way, and mirrors a `WINDUP -> ACTIVE` fixed-tick
  countdown (`_on_melee_swing_started_received` / `_advance_strike_visual`)
  driven by the new `NetworkClient.melee_swing_started_received` signal, so a
  peer other than the local one also shows the strike-line at roughly the
  moment the server's own `ACTIVE` phase begins.
- `server/server_player_state.gd` — new `melee_swing_started(peer_id,
  windup_ticks, active_ticks, facing)` signal, emitted exactly once alongside
  the existing `action_resolved` signal when (and only when) a `MELEE_STRIKE`
  `ActionIntent` is `ACCEPTED` from `IDLE`. Carries only already-public
  archetype timing and the just-accepted facing — no trusted outcome, no hit
  result.
- `server/server_main.gd` — relays `melee_swing_started` to **every**
  connected peer (unlike `action_resolved`, which stays peer-scoped to the
  attacker), via the new `receive_melee_swing_started` RPC.
- `client/network_client.gd` — `receive_melee_swing_started` RPC target and
  `melee_swing_started_received` signal, relaying the broadcast the same
  relay-only way every other RPC target in this file does.
- `shared/network_config.gd` — new `FACING_TURN_RATE` constant: the bounded
  turn speed (radians/second) both `player.gd` and `remote_player.gd` use, so
  facing reads as a smooth turn rather than an instant snap. Client-side
  presentation only; the server never reads this value.
- `tests/unit/test_melee_strike_visual_indicator.gd` — public-seam GUT unit
  tests for movement-facing rotation and its "hold last facing" rule, the
  `MeleeStrikeVisual` component's show/hide behavior, the local Player's
  predicted-`ACTIVE`-phase visual timing and its rejection correction, the new
  `melee_swing_started` signal's accept/reject emission rule, and
  `RemotePlayer`'s mirrored countdown timing and per-peer filtering.

Contract: `melee_swing_started` fires once per accepted swing, to every
connected peer, carrying only the same tuning-derived timing/facing values
already public in `CombatContracts.generic_sword_archetype()` — it grants no
peer a trusted hit, damage, or outcome claim, matching CLAUDE.md's rule that
an authoritative action's early telegraph state may be replicated for client
presentation while the actual hit stays exclusively driven by the existing
`CombatEvent.HIT` broadcast. The strike-line visual is purely a `visible`
toggle on a client-only mesh; it participates in no collision, hit test, or
server round trip. Player/RemotePlayer facing is a client-side rotation only;
the authoritative `facing`/`aim_direction` used for the reach/arc hit test
remains exactly what `server_player_state.gd` already derives from accepted
input/intent (Slice 004/012), unchanged by this slice.

Safety invariant: no damage, HP, hit-outcome, inventory, or weapon-switching
concept is introduced. The visual component cannot be told to represent a hit
that did not occur — it only tracks a phase timer driven by data the server
already validated and accepted. A rejected intent hides the local predicted
visual immediately, matching the existing predicted-phase rejection
correction; a busy/cooldown-rejected intent never emits `melee_swing_started`
at all, so remote observers never see a swing that the server did not accept.

## BDD

### Local Player faces its movement direction

Given a Player receiving WASD input
When it moves in a given planar direction
Then it rotates so `-global_transform.basis.z` tracks that direction, bounded
by `NetworkConfig.FACING_TURN_RATE`, and holds its last facing once input
stops instead of resetting to a default orientation.

### Attack aims where the Player is facing

Given a Player that last moved in some direction (or never moved, keeping its
spawn facing)
When it submits a melee `ActionIntent`
Then the intent's `aim_direction` is exactly `-global_transform.basis.z` at
that moment, matching the server's own `facing`-derived reach/arc hit test.

### Strike-line shows only during the ACTIVE phase

Given a Player predicting or confirmed to be in the melee lifecycle
When the tracked phase is `WINDUP` or `RECOVERY`/`IDLE`
Then the strike-line visual is hidden; when the tracked phase is `ACTIVE`,
the strike-line visual is shown.

### Rejected intent hides the visual immediately

Given a local Player's predicted `ACTIVE` phase with the strike-line visible
When the server's `ActionResolution` for that sequence arrives `REJECTED`
Then the predicted phase resets to `IDLE` and the strike-line is hidden in the
same tick, without waiting out the remaining predicted ticks.

### Every connected peer observes another peer's swing

Given two connected peers, A and B
When peer A's melee `ActionIntent` is `ACCEPTED` by the server
Then peer B's client receives `melee_swing_started` for peer A and times its
`RemotePlayer_<A>` strike-line to appear once the mirrored `WINDUP` countdown
reaches zero and disappear once the mirrored `ACTIVE` window ends; a
`melee_swing_started` naming any other peer id is ignored.

### A busy/cooldown-rejected intent produces no swing broadcast

Given a Player already mid-swing (`WINDUP`/`ACTIVE`) or in `RECOVERY`
When it submits another `ActionIntent`
Then no `melee_swing_started` signal fires for that rejected intent, so no
peer's client ever renders a swing the server did not accept.

## TDD evidence

`tests/unit/test_melee_strike_visual_indicator.gd` covers: the local Player's
movement-facing rotation converging toward the input direction and holding
its last facing when input stops; the `MeleeStrikeVisual` component's
independent `start_swing()`/`end_swing()` toggle; the local Player's predicted
phase showing the visual only during `ACTIVE` and hiding it on transition out;
a rejected `ActionResolution` hiding the visual immediately and resetting the
predicted phase to `IDLE`; `server_player_state.gd`'s `melee_swing_started`
firing exactly once (with the archetype's timing and the accepted facing) for
an accepted intent and not at all for a busy-rejected one; and
`RemotePlayer`'s mirrored `WINDUP -> ACTIVE` countdown timing the strike-line
correctly while ignoring a swing signal for a different peer id.

Existing `tests/unit/test_melee_combat_contracts.gd` (21 tests) and
`tests/integration/test_authoritative_melee_strike.gd` (4 tests) continue to
pass unchanged, confirming the new signal/broadcast plumbing did not alter
Slice 012's authoritative lifecycle, rejection codes, or hit resolution.

## ADR decision

No new ADR. This slice adds only client-side cosmetic presentation and one
new server-to-all-peers broadcast of already-public, already-accepted
timing/facing data. It introduces no new authoritative state, persistence, or
runtime-ownership change beyond what
[ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md) and Slice
012 already establish; the new `melee_swing_started` broadcast matches
CLAUDE.md's existing telegraph-replication rule ("Enemy intent begins as an
authoritative action state replicated early enough for the client to render
its authored telegraph").

## Validation

- Focused unit: `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/unit -gselect=test_melee_strike_visual_indicator -gexit`
  — PASS, 9/9 tests, 23 assertions, exit 0.
- Regression, unit: `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/unit -gselect=test_melee_combat_contracts -gexit` — PASS,
  21/21 tests, 54 assertions, exit 0 (unchanged from Slice 012).
- Regression, integration: `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/integration -gselect=test_authoritative_melee_strike
  -gexit` — PASS, 4/4 tests, 14 assertions, exit 0 (unchanged from Slice 012).
- Full suite: `scripts/run_gut_validation.sh` — PASS, 57/57 tests, 161
  assertions, exit 0; telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`.
- Real-socket regression: `godot --headless --path . -s
  scripts/test_authoritative_melee_strike_e2e.gd` — `ALL PASS`, confirming the
  production `server_main.gd`/`network_client.gd` RPC path (now also carrying
  `receive_melee_swing_started`) still delivers a real `ACCEPTED`
  `ActionResolution` and `CombatEvent.HIT` over an actual ENet connection.
- Real-socket regression: `godot --headless --path . -s
  scripts/test_multi_peer_replication.gd` — `ALL PASS`, confirming two-peer
  connect/replicate/disconnect behavior is unchanged by the new
  `melee_swing_started` signal wiring added to `server_main.gd`'s
  connect/disconnect handlers.
- Known-benign engine print: every run above prints one or more
  `ERROR: Parameter "m" is null. at: mesh_get_surface_count (...)` lines when
  a runtime-created mesh is assigned inside a node's own `_ready()` under
  Godot 4.3's headless dummy renderer. This is the same class of benign,
  non-fatal engine print already documented in
  [Slice 001](001-identity-gate-flat-plane-movement.md) and
  [Slice 002](002-client-connects-to-server.md) for scene-authored meshes; it
  does not affect exit codes, assertions, or gameplay behavior, and does not
  occur in the real Windows/Linux client (a non-headless renderer).

## Explicit non-goals and next boundary

This slice adds no weapon contrast/switching, no HP/damage math, no combat
resolution changes, and no inventory. `TargetDummy` (`client/target_dummy.gd`
and `server/server_main.gd`'s server-owned dummy) is unmodified and remains
visible and functional exactly as Slice 012 left it — this slice adds a
sibling visual on the attacker, not a change to the target's own presentation.
The next authoritative-action or presentation slice must decide how additional
action kinds, weapon archetypes, or a confirmed hit's durable consequence
connect to this presentation layer without turning the cosmetic strike-line
into a second, client-trusted hit signal.
