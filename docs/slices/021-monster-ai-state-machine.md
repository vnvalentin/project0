# Slice 021: Monster AI state machine with attack telegraph
GitHub issue: #95

Tracker context: Phase 12 — Authoritative runtime and action input; advances
[IP-023](../FEATURE-LIST.md#ip-023-basic-monster-combat).
Planning tickets: [Basic Monsters map](../../.scratch/basic-monsters/map.md),
[issue 02 — Monster state machine with telegraph](../../.scratch/basic-monsters/issues/02-monster-state-machine-with-telegraph.md)
(resolved). Second Basic Monsters slice, building on Slice 020's HP/damage/death
contract.

## SDD

Goal: Implement the authoritative detect → chase → windup → attack → recovery
behavior for one baseline monster, with a real pre-attack telegraph the player
can dodge, reusing the existing melee reach/arc hit test, and emitting
structured telemetry at every transition and attack — as a deterministic,
fully unit-testable object. No spawning, no client rendering, and no
player-damage model in this slice.

Public seams:

- `shared/monster_contracts.gd` — gains the tick/range/speed/reach constants
  (`WINDUP_TICKS`, `ATTACK_ACTIVE_TICKS`, `RECOVERY_TICKS`,
  `DETECTION_RADIUS_METERS`, `CHASE_SPEED_METERS_PER_SEC`,
  `MONSTER_REACH_METERS`, `MONSTER_ARC_DEGREES`), the `PHASE_*` state-name
  constants, and `monster_attack_archetype()` (a `MeleeWeaponArchetype` used
  only for its reach/arc by the shared hit test).
- `server/server_monster_state.gd` (`class_name ServerMonsterState`,
  `RefCounted`) — the state machine. `advance(player_position, delta,
  server_tick)` runs one tick; `receive_damage(amount, attacker_peer_id,
  server_tick)` applies a player hit and drives the death transition. Emits
  `phase_changed`, `attack_resolved`, and `died` telemetry signals. A
  `RefCounted` (not a Node) so its whole lifecycle is unit-testable by calling
  `advance()` directly, with no SceneTree or physics.
- `tests/unit/test_server_monster_state.gd` — drives the machine and watches
  the telemetry signals.

Behavior (per resolved ticket 02):

- **No separate DETECT state**: while `IDLE`, each tick checks the horizontal
  distance to the player against `DETECTION_RADIUS_METERS` and transitions
  straight to `CHASE`.
- **CHASE**: faces and moves toward the player at
  `CHASE_SPEED_METERS_PER_SEC * delta`; if the player leaves detection range it
  returns to `IDLE`; when the player is within reach/arc it locks its facing and
  enters `WINDUP`.
- **WINDUP** (the telegraph): counts `WINDUP_TICKS` ticks without re-tracking
  the player, then transitions to `ATTACK` and resolves the strike once against
  the locked facing via `CombatContracts.is_within_reach_and_arc()`. A player
  who stepped out of reach/arc during the windup is missed — the human's dodge
  window. `attack_resolved(target_id, landed, tick)` is emitted.
- **ATTACK → RECOVERY → IDLE**: `ATTACK` lasts `ATTACK_ACTIVE_TICKS`, `RECOVERY`
  lasts `RECOVERY_TICKS`, then the machine returns to `IDLE` to re-detect.
- **Death**: `receive_damage` applies to Slice 020's `MonsterCombatState`; the
  transition to 0 HP enters the terminal `DEAD` phase and emits `died` once
  (`COMBAT_EVENT_DEATH` is the shared kind the future runtime stamps on the
  replicated event). A dead monster ignores further `advance`/`receive_damage`.

Implementation decisions:

- **Binding windup-fairness invariant**: `WINDUP_TICKS` (10) is deliberately
  `>=` the player sword's `windup_ticks` (6) so the monster's telegraph is at
  least as readable as the player's own attack (CLAUDE.md Combat Reading). A
  regression test asserts this against `generic_sword_archetype()` so a future
  tuning change cannot silently violate it.
- **Reuse, not re-implement, hit detection**: the strike uses the shared
  `is_within_reach_and_arc()` with a monster archetype, so player and monster
  attacks share one tested geometric test.
- **Telemetry-first**: transitions, attack resolutions, and death are signals,
  satisfying the map's standing telemetry requirement and making the machine
  observable; the future server runtime forwards them to logs/sink.
- **No player-damage model**: the player has no HP (a future concern like the
  vessel system), so a landed attack is authoritatively resolved and reported
  but applies no damage yet. The monster is defeatable (Slice 020) but not yet
  dangerous; this is an explicit, bounded non-goal.
- **`RefCounted` + signals + `advance()`**: chosen over a `Node` with
  `_physics_process` so the full cycle is deterministic and unit-testable; the
  runtime slice will own a `Node` that calls `advance()` each physics frame and
  relays the signals.

## BDD

### Detect and chase

Given an idle monster
When a player enters `DETECTION_RADIUS_METERS`
Then the monster chases, moving toward the player each tick, and returns to
idle if the player flees beyond detection range.

### Telegraphed attack

Given the player is within reach
When the monster enters `WINDUP`
Then after `WINDUP_TICKS` it resolves one strike against its locked facing:
a player still in reach/arc is hit; a player who dodged out during the windup
is missed. It then recovers and returns to idle.

### Death

Given a living monster
When it takes `MAX_HP` damage
Then it enters `DEAD`, emits one death event naming the killer, and ignores
further advance/damage.

## TDD evidence

`tests/unit/test_server_monster_state.gd` (10 tests, 21 assertions): idle until
detection; chase moves toward the player; chase → idle on flee; chase → windup
in reach; the windup-fairness regression (`WINDUP_TICKS >= player windup`); a
held-in-reach player is hit after `WINDUP_TICKS` (`attack_resolved` with
`landed == true`); a player who dodges out during the windup is missed
(`landed == false`); the full cycle returns to idle; damage kills and emits one
`died`; and a dead monster ignores further advance/damage (no second `died`, no
further `phase_changed`), verified with GUT signal watching.

## ADR decision

No new ADR. A server-authoritative behavior over the existing combat-event
vocabulary and the Slice 020 contract; no new authority boundary or persistence
beyond `CLAUDE.md`/ADR 0002.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_server_monster_state -gexit`: PASS, 10/10 tests, 21 assertions,
  exit 0.
- `scripts/run_gut_validation.sh`: PASS, 133/133 tests, 366 assertions, exit 0.
- `godot --headless --check-only -s server/server_monster_state.gd` and
  `... shared/monster_contracts.gd`: both exit 0.
- Preempted risk (Jidoka): the state machine initially used a `match` on
  cross-script `const` phase names, whose pattern-constant semantics are
  unreliable in GDScript; rewritten as an explicit `if/elif` chain before the
  first run to guarantee correct dispatch. Validation then passed first time.

## Explicit non-goals and next boundary

This slice adds no monster spawning or server runtime loop (the RefCounted is
not yet driven by any `_physics_process`), no client rendering of the monster or
its telegraph, no wiring of a player's melee resolution to `receive_damage`, and
no player-damage model. The next Basic Monsters slice is spawning monsters from
the town blueprint's spawn points and driving this machine on the server tick,
with the randomized in-area respawn decided in ticket 03.
