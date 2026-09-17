# Slice 120 - Phase 14 shared health / defeat / recovery contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#231](https://github.com/vnvalentin/project0/issues/231)
(combat/status), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

Players and NPCs share one health pool: ordinary damage brings a Character
toward defeat and recovery restores it, with the same rules for everyone. There
is no injury mechanic — a hit is damage, not a lasting wound.

## Scope and non-goals

In scope: the deterministic `shared/combat_health.gd` contract — apply damage,
apply recovery, defeat detection, and a presentation-safe health fraction.
Server-authoritative, fail-closed.

Out of scope: damage-magnitude derivation (attacker effective stats + equipment
+ technique + defender mitigation — a later combat-resolution slice), the
magical/impairment status-effect contract, death/respawn design, and any UI.
An injury subsystem is explicitly NOT modeled (issue #231).

## Public seam

`shared/combat_health.gd` (`CombatHealth`): `apply_damage`, `apply_recovery`,
`is_defeated`, `health_fraction`, the instance mutators `take_damage`/`heal`/
`is_now_defeated`/`fraction`, and the fail-closed `from_wire_dict`.

## Falsifiable hypothesis

If health/defeat/recovery is a pure, shared contract, then player and NPC combat
outcomes are reproducible and identical by construction, and later
damage-resolution and status slices can consume one health seam without a
separate NPC health model.

## SDD

`apply_damage(current, amount) = max(0, current - max(0, amount))` — damage
floors at zero and never heals. `apply_recovery(current, max, amount) =
min(max, current + max(0, amount))` — recovery caps at max and never harms.
`is_defeated` is zero health. `health_fraction` is 0..1 (fails safe to 0 for a
non-positive max) so the client shows a bar without the raw numbers. Pure and
deterministic; the server owns the pool.

## BDD

1. Given damage, when applied, then health drops and floors at zero; negative
   amounts never heal.
2. Given recovery, when applied, then health rises and caps at max; negative
   amounts never harm.
3. Given zero health, when checked, then the Character is defeated.
4. Given a pool, when the fraction is computed, then it is 0..1 and fails safe.
5. Given instance mutation, when damaged to zero then healed, then defeat is
   reported and cleared correctly.
6. Given malformed/out-of-bounds input, when parsed, then it fails closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **77 scripts / 549 tests / 549 passing, exit 0**. The new
`test_combat_health.gd` ran all **12/12** of its tests (damage floor, recovery
cap, defeat, bounded fraction, instance mutation, and the fail-closed rejection
matrix), confirming the script executed (not a silent preload skip).
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was
performed on the Linux host per repo convention.

## Safety invariants

- The server is the sole authority for the health pool; damage/recovery are
  applied server-side, never client-authored.
- Damage never heals and recovery never harms; health stays within [0, max].
- The presentation fraction never leaks the raw pool numbers.
- Parsing fails closed on version/structure/bounds; invalid input yields no pool.
- No injury state is introduced.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred damage-resolution, status effects, and
death/respawn are explicit non-goals here and on the Phase 14 map, not
liabilities.
