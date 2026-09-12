# Slice 022: Monster spawning and respawn (outside town)

Tracker context: Phase 10 — Authoritative runtime and action input; advances
[IP-023](../FEATURE-LIST.md#ip-023-basic-monster-combat).
Planning tickets: [Basic Monsters map](../../.scratch/basic-monsters/map.md),
[issue 03 — Monster spawn points from town schema](../../.scratch/basic-monsters/issues/03-monster-spawn-points-from-town-schema.md)
(resolved). Third and final Basic Monsters slice; completes that map's
destination server-side.

## SDD

Goal: Spawn one monster per town spawn point, drive their state machines on the
server tick against the nearest player, and respawn defeated monsters after a
cooldown — with every spawn and respawn kept OUTSIDE the town boundary (user
caveat). Add the spawn points to the hub fixture and wire the runtime into the
server's frame loop.

Public seams:

- `server/starting_town_hub_fixture.gd` — the hub blueprint now carries a
  `spawn_points` array, each placed OUTSIDE the ±8 town wall ring
  (`wild_east`/`west`/`north`/`south` at distance 10) so monsters spawn in the
  wilds, never inside town.
- `server/server_monster_manager.gd` (`class_name ServerMonsterManager`,
  `RefCounted`) — creates one `ServerMonsterState` per spawn point (bounded by
  `SectorBlueprintSchema.MAX_SPAWN_POINT_COUNT`), `advance_all(player_positions,
  delta, tick)` drives each monster against the nearest player and handles
  death → cooldown → respawn, and emits `monster_died` / `monster_respawned`
  telemetry. Respawns are randomized within `RESPAWN_AREA_RADIUS_METERS` of the
  spawn base and clamped to stay outside the town exclusion box.
- `server/server_main.gd` — builds the manager from the validated hub's spawn
  points at boot, connects the death/respawn telemetry to logs, and drives
  `advance_all` on every `physics_frame` with all connected peers' positions.
- `tests/unit/test_server_monster_manager.gd` and the updated
  `tests/unit/test_starting_town_hub_fixture.gd`.

Behavior (per resolved ticket 03, plus the outside-town caveat):

- **1:1 spawn at boot**: one monster per spawn point, at the spawn point's
  world position (`y == MONSTER_SPAWN_Y`).
- **Tick driving**: each physics frame, every living monster advances against
  the nearest connected player; with no players connected, monsters idle.
- **Death → respawn**: when a monster is defeated (its `MonsterCombatState`
  reaches 0), the manager emits `monster_died`, clears the slot, and after
  `RESPAWN_COOLDOWN_TICKS` respawns a fresh monster at a randomized in-area
  position, emitting `monster_respawned`.
- **Bounded**: the live monster count is capped at `MAX_SPAWN_POINT_COUNT`.

Implementation decisions:

- **Outside-town caveat enforced structurally**: spawn points are authored
  beyond the wall, and `_random_position_outside_town` re-pushes any respawn
  that lands inside the `TOWN_EXCLUSION_HALF_EXTENT` (8.5) box back out along
  the spawn's dominant axis, so a monster can never appear inside town on spawn
  or respawn. A dedicated test drives 30 kill/respawn cycles across all four
  spawn points and asserts every respawn is outside the exclusion box.
- **`RefCounted` + injectable seed/cooldown**: the manager is SceneTree-free and
  takes an RNG seed and (in tests) a small respawn cooldown, so the full
  spawn/death/respawn lifecycle is deterministic and unit-testable; the server
  wires it to the real `physics_frame` with a fixed `MONSTER_TICK_DELTA`.
- **Telemetry-first**: death and respawn are signals the server logs, per the
  map's standing requirement.

## BDD

### Spawn outside town

Given the hub fixture's spawn points (all outside the town wall)
When the manager is built
Then one monster exists per spawn point and every monster's position is outside
the town boundary.

### Chase and idle

Given connected players
When the manager advances
Then each monster chases the nearest player; with no players connected, monsters
idle and survive.

### Death and respawn outside town

Given a defeated monster
When the respawn cooldown elapses
Then the manager emits `monster_died` then `monster_respawned`, and the
respawned monster is positioned outside the town — verified across many cycles.

## TDD evidence

- `tests/unit/test_server_monster_manager.gd` (7 tests): one monster per spawn
  point; all initial positions outside town; capped at `MAX_SPAWN_POINT_COUNT`;
  idle/survive with no players; chase the nearest player; death → cooldown →
  respawn with the right telemetry; and — for the caveat — every respawn across
  30 cycles on all four spawn points stays outside the town exclusion box.
- `tests/unit/test_starting_town_hub_fixture.gd` — updated: the "no spawn_points"
  assertion becomes "spawn points exist and are all outside the ±8 town wall".

## ADR decision

No new ADR. Server-authoritative runtime over the existing hub fixture and the
Slice 020/021 monster contracts; no new authority boundary or persistence.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_server_monster_manager -gexit`: PASS, 7/7 tests, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_starting_town_hub_fixture -gexit`: PASS, 8/8 tests, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 140/140 tests, 510 assertions, exit 0.
- `godot --headless --check-only` on `server/server_monster_manager.gd`,
  `server/server_main.gd`, `server/starting_town_hub_fixture.gd`: all exit 0.
- Jidoka during development: (1) an initial test referenced `MONSTER_TICK_DELTA`
  on the wrong script (it lives on `server_main`), producing a risky test;
  fixed to a literal delta. (2) Three `assert_signal_emitted_with_parameters`
  calls in the Slice 021 monster-state test emitted non-fatal GUT-internal
  `SCRIPT ERROR` diagnostics (once each); replaced with explicit
  captured-parameter lambda assertions so the suite runs clean.

## Explicit non-goals and next boundary

This slice does not render monsters on the client (they exist and behave
server-side but are not yet visible), does not wire a player's accepted melee
hit to `monster.receive_damage` (so monsters are not yet damageable in the live
loop — the manager exposes `monster_at()` for that future wiring), and adds no
player-damage model or loot. With this slice the Basic Monsters map's three
resolved tickets are all implemented server-side; `IP-023` stays `In Progress`
until the follow-up that makes monsters visible to and fightable by players
(client representation + melee-hit-to-damage wiring), plus the future
destructible-spawner idea recorded in the map's "Not yet specified".
