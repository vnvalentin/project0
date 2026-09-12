Type: grilling
Status: resolved

## Question

What are the authoritative states/transitions and tick-bounded timing for
the first simple monster (e.g. `IDLE -> DETECT -> CHASE -> WINDUP -> ATTACK
-> RECOVERY -> IDLE`, mirroring the existing player attack phase constants
`PHASE_IDLE`/`PHASE_WINDUP`/`PHASE_ACTIVE`/`PHASE_RECOVERY` in
`shared/combat_contracts.gd`)? The `WINDUP`-equivalent phase must replicate
early enough for a human to read and dodge, per CLAUDE.md's Combat Reading
And Execution Rules (non-negotiable — no same-tick/unavoidable damage).
Confirm detection range, chase speed, and attack range/damage as bounded
tuning-shaped constants rather than hardcoded magic numbers, matching the
`MeleeWeaponArchetype` pattern.

## Answer

- **State list**: `IDLE -> CHASE -> WINDUP -> ATTACK -> RECOVERY -> (IDLE or
  CHASE)`. No separate `DETECT` state — detection is a radius check each
  tick while `IDLE` that transitions straight to `CHASE`; a distinct detect
  state would carry no rule/timing of its own. The telegraph CLAUDE.md
  requires is `WINDUP`, not a "noticed you" beat.
- **Tick timing**: fixed constants in `shared/monster_contracts.gd`,
  no per-archetype table — `WINDUP_TICKS = 10` (longer than the player
  sword's `6`, so the monster's telegraph is at least as readable as the
  player's own attack), `ACTIVE_TICKS = 4`, `RECOVERY_TICKS = 10`. Exact
  values are tunable later; the binding rule is windup >= player windup.
- **Detection/chase**: `DETECTION_RADIUS_METERS = 8.0` (checked each tick
  while `IDLE`) and an independent fixed `CHASE_SPEED_METERS_PER_SEC`
  constant — not a multiplier of player speed, since coupling them is
  speculative structure with only one monster archetype and one player speed
  today.
- **Attack hit detection**: reuse
  `CombatContracts.is_within_reach_and_arc()` with the monster's own fixed
  `reach_meters`/`arc_degrees` constants — one shared, already-unit-tested
  helper for both player and monster attacks, no second implementation to
  keep in sync.
- **Telemetry (added per user direction, not deferred)**: every state
  transition (`IDLE->CHASE`, `CHASE->WINDUP`, `WINDUP->ATTACK`,
  `ATTACK->RECOVERY`, `RECOVERY->IDLE`/`CHASE`) and every attack
  accepted/rejected outcome emits a structured, bounded telemetry record
  (monster id, from/to state, server tick, tuning-constant values in effect)
  through the same telemetry seam CLAUDE.md's "Telemetry And Andon Signals"
  section already requires for action accept/reject — this is what makes
  `WINDUP_TICKS`/`CHASE_SPEED`/etc. actually adjustable from observed data
  later instead of guessed. No new telemetry transport is invented here;
  this reuses whatever sink the existing action-resolution telemetry uses.
- **Testing discipline (standing, not just this ticket)**: implementation
  must follow this repo's existing SDD/BDD/TDD pattern (see
  `docs/slices/012-authoritative-melee-strike.md` as the template) — a
  failing public-seam test first, unit tests for the pure state-transition
  and `is_within_reach_and_arc()`-reuse logic, and a GUT integration test
  exercising the full `IDLE->...->RECOVERY` cycle including the telemetry
  emitted at each transition, plus a regression test asserting `WINDUP_TICKS
  >= player_windup_ticks` so a future tuning change can't silently violate
  the fairness rule. Recorded here so the eventual implementation slice
  can't drop it.
