# Map: Basic Monsters

## Destination

A handoff-ready spec (SDD/BDD-shaped) describing a minimal server-authoritative
monster: a flat HP/damage/death model extending
`shared/combat_contracts.gd`, and a simple detect → chase → attack state
machine with an authored telegraph before its attack lands, spawned from the
Starting Town's sector blueprint spawn points. Ready to become an
implementation slice under Phase 10 (Authoritative runtime and action input).
See [Project Tracker](../../docs/PROJECT-TRACKER.md) and
[CLAUDE.md](../../CLAUDE.md).

## What Good Looks Like

- [x] Server-owned monster HP, damage, and death outcomes exist at a public combat seam.
- [x] A monster can detect, chase, telegraph, attack, recover, and emit bounded telemetry.
- [x] Monsters spawn from validated town spawn points and respawn without blocking play.
- [ ] A player-facing run confirms monsters are visible, readable, fightable, and defeatable in the intended client experience.

## Notes

- Domain: server-authoritative combat, extends the existing
  `ActionIntent`/`ActionResolution`/`CombatEvent` pattern
  (`shared/combat_contracts.gd`) and the phase pattern already used for
  player attacks (`server/server_player_state.gd`,
  `docs/slices/012-authoritative-melee-strike.md`).
- Must satisfy CLAUDE.md's "Combat Reading And Execution Rules": enemy intent
  must replicate early enough for a human to read and dodge — no
  same-tick/unavoidable damage.
- Standing requirement (user direction, 2026-09-12): every tuning-relevant
  behavior (state transitions, attack outcomes, future balancing-relevant
  values) must emit structured, bounded telemetry from the start — build it
  in per-ticket, not bolted on after the fact. Reuse CLAUDE.md's existing
  "Telemetry And Andon Signals" seam rather than inventing a new one.
- Standing requirement (user direction, 2026-09-12): every implementation
  slice from this map follows this repo's SDD/BDD/TDD workflow (public-seam
  failing test first, unit tests for pure logic, GUT integration tests, plus
  regression tests for any safety-relevant invariant such as the windup
  telegraph timing) — matching `docs/slices/012-authoritative-melee-strike.md`
  as the existing template for this repo.
- Skills to consult: `domain-modeling`, `tdd` (server logic here is
  unit-testable the same way the existing GUT suite covers
  `combat_contracts.gd`'s pure helpers).
- Depends on the sibling [Starting Town map](../starting-town/map.md) for the
  spawn-point schema shape (ticket 03 below is cross-map blocked).

## Decisions so far

- [01 — HP/damage/death model](issues/01-hp-damage-death-model.md): New sibling file `shared/monster_contracts.gd` (not an addition to `combat_contracts.gd`); `MonsterCombatState` = `{current_hp, max_hp, target_id}` with a single fixed `MAX_HP` constant (no per-archetype table); a new fixed `DAMAGE_PER_HIT` constant; death reuses `CombatEvent`'s shape with a new `COMBAT_EVENT_DEATH` kind. All explicitly provisional pending the future vessel-derived health formula.
- [02 — Monster state machine with telegraph](issues/02-monster-state-machine-with-telegraph.md): `IDLE -> CHASE -> WINDUP -> ATTACK -> RECOVERY` (no separate DETECT state); fixed tick/range/speed constants (`WINDUP_TICKS=10 >= player's 6`, `ACTIVE_TICKS=4`, `RECOVERY_TICKS=10`, `DETECTION_RADIUS_METERS=8.0`, independent `CHASE_SPEED`); reuses `is_within_reach_and_arc()` for hit detection; every state transition and attack outcome emits structured telemetry (per CLAUDE.md's Telemetry section); implementation must follow SDD/BDD/TDD with unit + GUT integration + a windup-fairness regression test.
- [03 — Monster spawn points from town schema](issues/03-monster-spawn-points-from-town-schema.md): 1:1 Monster-per-spawn_point at server boot; on death, fixed `RESPAWN_COOLDOWN_TICKS` cooldown then respawn at a randomized position within a bounded `RESPAWN_AREA_RADIUS_METERS` (not permanent removal); respawn emits telemetry; max-concurrent count reuses Starting Town's `MAX_SPAWN_POINT_COUNT` per-sector, no separate global cap.

## Not yet specified

- Monster movement/pathfinding fidelity beyond a straight-line chase (e.g.
  obstacle avoidance around town buildings) — fog until the Starting Town
  map's actual sector geometry is known.
- Future "monster spawner" object (user idea, 2026-09-12): a visible,
  destructible generator entity (Gauntlet-style) that would own/control
  respawn instead of an invisible per-spawn-point timer — would need its own
  entity kind, HP/destruction rules, and schema field, not yet specified.

## Out of scope

- Full six-node vessel-derived damage/health formula (Phase 12, 0% built) —
  this map uses a flat provisional HP pool instead.
- Multiple monster archetypes — only one baseline monster this map.
- Loot/rewards on death, and any broader monster "economy" (drops, currency,
  scaling). Respawn timers themselves are now in scope (ticket 03) per user
  direction, 2026-09-12 — removed from this Out-of-scope list.
