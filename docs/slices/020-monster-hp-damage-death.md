# Slice 020: Monster HP, damage, and death model
GitHub issue: #95

Tracker context: Phase 10 — Authoritative runtime and action input; advances
[IP-023](../FEATURE-LIST.md#ip-023-basic-monster-combat).
Planning tickets: [Basic Monsters map](../../.scratch/basic-monsters/map.md),
[issue 01 — HP/damage/death model](../../.scratch/basic-monsters/issues/01-hp-damage-death-model.md)
(resolved). First slice of the Basic Monsters effort.

## SDD

Goal: Add the minimal, explicitly provisional flat HP/damage/death data model
for a server-authoritative monster, plus the shared death combat-event kind, so
later Basic Monsters slices (the detect/chase/attack state machine and spawning)
have a validated contract to build on. No AI, no runtime loop, no spawning, and
no persistence in this slice.

Public seams:

- `shared/monster_contracts.gd` (`class_name MonsterContracts`) — a new sibling
  contract file, deliberately not folded into `combat_contracts.gd` (whose
  scope is tightly bounded to Slice 012's melee-strike contracts with an
  explicit no-damage/HP non-goal). Owns `MAX_HP`, `DAMAGE_PER_HIT`, the
  `MonsterCombatState` inner class (`target_id`, `max_hp`, `current_hp`,
  `apply_damage`, `is_dead`), and a `default_monster(target_id)` factory.
- `shared/combat_contracts.gd` — gains `COMBAT_EVENT_DEATH = "DEATH"` alongside
  `COMBAT_EVENT_HIT`. Death reuses the existing `CombatEvent` shape (attacker,
  target, position, tick) rather than a new event class — a death still has all
  four.
- `tests/unit/test_monster_contracts.gd` — pure unit tests over the state
  transitions and the new event kind.

Contract (per resolved ticket 01):

- `MAX_HP = 30`, `DAMAGE_PER_HIT = 10` — single fixed constants, not a
  per-archetype table (only one baseline monster exists in this map's scope).
  `30 / 10` gives a deterministic 3 hits to defeat.
- `MonsterCombatState.apply_damage(amount)` clamps `current_hp` at 0 (never
  negative) and returns `true` only on the transition to 0 — the tick a hit
  defeats a still-living monster — so the caller emits exactly one death event
  and never a duplicate for an already-dead monster.
- `target_id` mirrors the id a `CombatEvent.target_id` resolves against (as
  `client/target_dummy.gd` already uses), so monster hit resolution keys the
  same way as the existing dummy.

Implementation decisions:

- **PROVISIONAL by design**: this flat pool is a placeholder for the future
  six-node vessel-derived health formula (`CLAUDE.md` Phase 12, 0% built),
  documented as such in the file header. It is a bounded stand-in so monsters
  can be built and fought before the vessel system exists.
- **Sibling file, not `combat_contracts.gd`**: keeps Slice 012's closed scope
  intact and contains the new provisional concept.
- **`DAMAGE_PER_HIT` lives on `MonsterContracts`, not
  `MeleeWeaponArchetype`**: the weapon archetype has no damage field by Slice
  012's explicit non-goal; adding one there would silently expand that slice's
  scope.
- **Typing note**: `MonsterCombatState` is accessed via the preloaded
  `MonsterContractsScript` const and typed `Object` at call sites, matching the
  repo pattern (a bare `class_name` type annotation does not resolve under
  headless class-cache runs — see Slice 019).

## BDD

### A fresh monster starts at full health

Given `default_monster(target_id)`
When it is created
Then `current_hp == max_hp == MAX_HP`, it keeps its `target_id`, and it is not
dead.

### Damage reduces health and clamps at zero

Given a monster
When `apply_damage` is called
Then `current_hp` drops by the amount, never below 0, and over-damage leaves it
at exactly 0 and dead.

### Death is reported exactly once

Given a living monster
When a hit reduces it to 0
Then `apply_damage` returns `true` that once; further hits on the dead monster
return `false` (no second death).

### The shared death event exists

Given `COMBAT_EVENT_DEATH`
When a `CombatEvent` is built with it
Then the event carries the DEATH kind and names its target, reusing the
existing event shape.

## TDD evidence

`tests/unit/test_monster_contracts.gd` (6 tests, 18 assertions): fresh monster
at full HP; one hit removes `DAMAGE_PER_HIT` and is non-lethal; over-damage
clamps at 0 and is dead; three `DAMAGE_PER_HIT` hits defeat the baseline monster
with the third reporting the death transition; damage after death reports no
second death; and `COMBAT_EVENT_DEATH` exists and fits a `CombatEvent`.

Telemetry note: this slice is a pure data/contract layer with no runtime loop,
so there is nothing to emit yet. The map's telemetry-first standing requirement
attaches to the next Basic Monsters slice (the state machine), which will emit
structured transition/attack/death telemetry as it drives these contracts.

## ADR decision

No new ADR. A provisional, bounded, server-owned value contract extending the
existing combat-event vocabulary; it introduces no authority boundary or
persistence beyond `CLAUDE.md`/ADR 0002, and explicitly defers the real
vessel-derived health model.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_monster_contracts -gexit`: PASS, 6/6 tests, 18 assertions,
  exit 0.
- `scripts/run_gut_validation.sh`: PASS, 123/123 tests, 345 assertions, exit 0.
- `godot --headless --check-only -s shared/monster_contracts.gd` and
  `... shared/combat_contracts.gd`: both exit 0.

## Explicit non-goals and next boundary

This slice adds no monster AI/state machine, no server-side monster entity or
runtime loop, no spawning, no client rendering, no telemetry (nothing runs yet),
and no vessel-derived health. The next Basic Monsters slice is the authoritative
detect → chase → windup → attack → recovery state machine (resolved ticket 02),
which consumes `MonsterCombatState`/`DAMAGE_PER_HIT`, emits `COMBAT_EVENT_DEATH`,
and carries the telemetry and windup-fairness regression test the map requires.
