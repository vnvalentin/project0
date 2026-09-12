# Slice 012: Server-authoritative melee strike and hit registration

Tracker context: Phase 10 — Authoritative runtime and action input; advances
[IP-015](../FEATURE-LIST.md#ip-015-authoritative-action-input).
Planning ticket: [melee-combat issue 05](../.scratch/melee-combat/issues/05-set-first-melee-slice-boundary-and-evidence.md),
which resolves issues
[01](../.scratch/melee-combat/issues/01-define-first-melee-exchange.md),
[02](../.scratch/melee-combat/issues/02-set-melee-action-authority-and-lifetime.md),
[03](../.scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md), and
[04](../.scratch/melee-combat/issues/04-choose-first-target-and-hit-rule.md).

## SDD

Goal: Prove the first authoritative melee interaction end to end — a
connected player presses attack, the server owns a fixed-tick
`WINDUP -> ACTIVE -> RECOVERY -> IDLE` lifecycle for one `MeleeWeaponArchetype`
(the Generic Sword), enforces authoritative locomotion slowdown during
windup/recovery, and resolves a deterministic reach/arc hit test against a
server-owned stationary `TargetDummy`, replicating a `CombatEvent.HIT` back to
clients — without introducing damage, death, inventory, or persistence.

Public seams:

- `shared/combat_contracts.gd` — versioned `ActionIntent`, `ActionResolution`,
  `CombatEvent`, and the single `MeleeWeaponArchetype` ("Generic Sword" /
  `BASIC_SWORD`) data contract, plus two pure deterministic helpers:
  `is_within_reach_and_arc` (vector reach/arc hit test) and
  `locomotion_speed_factor_for_phase` (windup/recovery speed factor lookup).
- `server/server_player_state.gd` — `apply_action_intent`, the authoritative
  phase state machine (`_advance_action_phase`, ticked from
  `_physics_process`), `set_target_dummies`, and the `action_resolved` /
  `combat_event_emitted` signals.
- `server/server_main.gd` — owns server-side `TargetDummy` nodes, wires each
  connected peer's `ServerPlayerState` to them via `set_target_dummies`, and
  relays `combat_event_emitted` to clients over `receive_combat_event`.
- `client/player.gd` — captures attack input (LMB / `attack` action) and
  submits a `MELEE_STRIKE` `ActionIntent` with the Player's current facing.
- `client/network_client.gd` — `submit_action_intent`, and the
  `action_resolution_received` / `combat_event_received` signals relaying the
  server's `ActionResolution` and `CombatEvent` back to the client.
- `client/target_dummy.gd` — renders a local visual reaction when this
  client's target dummy is named in a replicated `CombatEvent.HIT`.
- `tests/unit/test_melee_combat_contracts.gd` — public-seam GUT unit tests for
  the shared contract shapes, the Generic Sword archetype's tuning values, the
  reach/arc hit-test geometry, and `ServerPlayerState.apply_action_intent`'s
  sequence ordering, idempotent replay, and rejection codes.
- `tests/integration/test_authoritative_melee_strike.gd` — public-seam GUT
  integration test driving the real `ServerPlayerState` node's full lifecycle
  and hit confirmation against a real `TargetDummy` node on real
  `_physics_process` ticks.
- `scripts/test_authoritative_melee_strike_e2e.gd` — headless two-process
  smoke test proving the same lifecycle over a real ENet socket, using the
  production `server/server_main.gd` and `client/network_client.gd` RPC path.

Contract: `apply_action_intent` validates sender ownership, action kind, and
current phase before accepting. From `IDLE`, a `MELEE_STRIKE` intent is
`ACCEPTED` and starts `WINDUP` (6 ticks) with the archetype's `0.5x` locomotion
factor; `ACTIVE` (4 ticks) resolves the reach/arc hit test each tick against
every registered target dummy at full locomotion speed; `RECOVERY` (10 ticks)
applies the archetype's `0.8x` locomotion factor before returning to `IDLE`. A
second intent while busy is `REJECTED_BUSY` (or `REJECTED_COOLDOWN` during
`RECOVERY`); an unrecognized `action_kind` is `REJECTED_INVALID_STATE`; a
sequence older than the last processed one is `REJECTED_STALE`; a replayed
sequence returns the identical cached `ActionResolution` object rather than
re-applying any effect; a sender id that does not own the state is ignored
entirely (`apply_action_intent` returns `null`). Exactly one `CombatEvent.HIT`
is emitted per target struck during `ACTIVE`, never more than once per swing.

Safety invariant: no damage, health, death/defeat, inventory, equipment, or
progression state exists in this slice. Weapon selection is fixed to the
single Generic Sword archetype. The hit test targets only server-owned
`TargetDummy` node references passed in by `server_main.gd`; a client cannot
name an arbitrary object to strike. All outcome fields (`ActionResolution`,
`CombatEvent`) are server-computed; `ActionIntent` never carries a trusted
result.

## BDD

### Accepted strike from idle

Given a Player in `IDLE` phase
When it submits a `MELEE_STRIKE` `ActionIntent`
Then the server returns `RESULT_ACCEPTED` with no rejection reason and enters
`WINDUP`.

### Busy and cooldown rejection

Given a Player already in `WINDUP`/`ACTIVE` or in `RECOVERY`
When it submits another `MELEE_STRIKE` `ActionIntent`
Then the server returns `RESULT_REJECTED` with `REJECTED_BUSY` (in-swing) or
`REJECTED_COOLDOWN` (recovery), and neither the in-flight swing nor the phase
timer is affected.

### Deterministic reach/arc hit confirmation

Given a stationary `TargetDummy` within the Generic Sword's 2.0 m reach and
±30° arc of the attacker's facing
When the attacker's `ACTIVE` phase ticks
Then exactly one `CombatEvent.HIT` is emitted naming that target and its
authoritative impact position, and a target outside reach or arc never
produces a hit.

### Authoritative locomotion slowdown

Given a Player in `WINDUP` or `RECOVERY` with forward movement input held
Then the server-integrated per-tick movement distance is scaled by the
archetype's `windup_speed_factor` (`0.5`) or `recovery_speed_factor` (`0.8`)
respectively; `IDLE` and `ACTIVE` move at full speed.

### Duplicate/stale intent idempotency

Given a sequence already processed (accepted or rejected)
When the identical sequence is resubmitted
Then the server returns the same cached `ActionResolution` object and applies
no additional phase transition or hit; a sequence older than the last
processed one is rejected as `REJECTED_STALE` instead of being re-evaluated.

### End-to-end network proof

Given a real client process connected to the real production server over ENet
When the client moves into reach of the server's target dummy and submits a
`MELEE_STRIKE` intent through `NetworkClient.submit_action_intent`
Then the client receives a real `ACCEPTED` `ActionResolution` and, after the
swing's `ACTIVE` phase, a real `CombatEvent.HIT` naming the server's target
dummy — both delivered over the actual RPC/socket path, not an in-process
stub.

## TDD evidence

`tests/unit/test_melee_combat_contracts.gd` covers the shared contract shapes
(`ActionIntent`, `ActionResolution`, `CombatEvent`, `MeleeWeaponArchetype`),
the Generic Sword's exact tuning values, the pure reach/arc hit-test geometry
(within reach and arc, exact reach boundary, beyond reach, outside arc, exact
arc boundary, directly behind, zero-length forward, and zero-distance target),
the phase-based locomotion speed factor, and `ServerPlayerState`'s sequence
ordering, busy/cooldown/stale/invalid-state rejection codes, idempotent
duplicate-sequence replay, wrong-sender-id isolation, and full lifecycle
return to `IDLE`.

`tests/integration/test_authoritative_melee_strike.gd` drives a real
`ServerPlayerState` node and a real `TargetDummy` node through real
`_physics_process` ticks: full lifecycle hit confirmation, out-of-reach miss,
authoritative locomotion slowdown during windup and recovery, and duplicate
mid-swing intent replay producing no second swing or double hit.

`scripts/test_authoritative_melee_strike_e2e.gd` proves the same lifecycle
through the real ENet RPC wiring added to `client/network_client.gd`
(`receive_action_resolution`, `receive_combat_event`) and the real production
`server/server_main.gd`/`server_player_state.gd`, since Godot 4.3 allows only
one `MultiplayerAPI` peer per `SceneTree` and GUT (a single process) cannot
open a second real ENet connection — matching the existing two-process pattern
from `scripts/test_prediction_reconciliation.gd` and
`scripts/test_multi_peer_replication.gd`.

## ADR decision

No new ADR. This slice implements the action-resolution and combat-event
seams already authorized by [ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md)
and CLAUDE.md's `ActionIntent`/`ActionResolution`/`CombatEvent` contracts,
scoped to the single bounded exchange resolved in
`.scratch/melee-combat/issues/01-05`. It introduces no new persistence
mechanism, world-state ownership boundary, or runtime authority change beyond
what ADR 0002 already establishes.

## Validation

- Focused unit: `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/unit -gselect=test_melee_combat_contracts -gexit` — PASS,
  21/21 tests, 54 assertions, exit 0.
- Focused integration: `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/integration -gselect=test_authoritative_melee_strike
  -gexit` — PASS, 4/4 tests, 14 assertions, exit 0.
- Full suite: `scripts/run_gut_validation.sh` — PASS, 48/48 tests, 138
  assertions, exit 0; telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`.
- Real-socket smoke test: `godot --headless --path . -s
  scripts/test_authoritative_melee_strike_e2e.gd` — `ALL PASS`, exit 0;
  proves a real client process receives a real `ACCEPTED` `ActionResolution`
  and a real `CombatEvent.HIT` from the real production server over an actual
  ENet connection.

## Explicit non-goals and next boundary

This slice does not add HP, damage math, death/defeat states, floating combat
text, inventory UI, equipment persistence, weapon switching, PvP player-on-
player combat, moving-target prediction, SQLite persistence, Ollama
integration, or any progression/Kinetic/Meridian/Burnout/magic system from
CLAUDE.md's normative target contract. The next authoritative-action slice
must decide how a confirmed hit connects to a health/damage model and how
combat evidence feeds the (still future) progression-evidence pipeline,
without letting either become a stat-gate on player reasoning.
