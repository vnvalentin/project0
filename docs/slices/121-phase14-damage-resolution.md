# Slice 121 - Phase 14 damage-resolution composition contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#231](https://github.com/vnvalentin/project0/issues/231)
(combat/status), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

A strike does the right amount of damage: a better weapon in more capable hands
with a well-practised technique hits harder, and an armoured defender takes
less — but a landed hit always stings. Players and NPCs resolve damage by the
same rule, and the result feeds one shared health pool.

## Scope and non-goals

In scope: `shared/damage_resolution.gd` — the pure, deterministic seam that
COMPOSES the already-derived Phase 14 combat scalars (weapon effective magnitude,
attacker attribute, technique reliability, defender mitigation) into a single
incoming damage amount for `CombatHealth.apply_damage`.

Out of scope: re-deriving nodes/effectiveness/reliability (each belongs to its
own contract — this seam only combines them), the status-effect contract,
critical hits / to-hit chance / RNG, threat/aggro, death/respawn, and any UI.
Damage is deterministic given its inputs; how randomness (if any) enters is a
later decision.

## Public seam

`shared/damage_resolution.gd` (`DamageResolution`): `attribute_scale`,
`mitigation_fraction`, `resolve_damage(weapon_effective, attacker_node,
technique_reliability, raw_mitigation)`, and the fail-closed `from_wire_dict`
that validates an untrusted strike request and returns the resolved damage.

## Falsifiable hypothesis

If damage resolution is a pure composition over the four Phase 14 combat
scalars, then the same weapon/attribute/technique/mitigation inputs always
produce the same damage for a player or an NPC, and the existing item, technique,
foundation, and health contracts compose end-to-end through one seam without a
separate combat model.

## SDD

`attribute_scale(node) = max(0, node) / BASELINE_NODE` (10.0), so a baseline
attacker scales 1.0 and a doubled node scales 2.0. `mitigation_fraction` clamps
armour to `[0, 0.9]` so mitigation can neither heal the attacker nor fully negate
a hit. `resolve_damage = max(0, weapon_effective * attribute_scale *
clamp(reliability,0,1) * (1 - mitigation_fraction))`. Stateless (no value
object) because damage resolution is a pure function of its inputs, not a
persisted entity — matching the resolution helpers in
`shared/combat_contracts.gd`. `from_wire_dict` fails closed on version,
structure, and numeric bounds.

## BDD

1. Given a baseline attacker, perfect reliability, and no mitigation, when a
   strike resolves, then damage equals the weapon's effective magnitude.
2. Given a stronger attacker, when a strike resolves, then damage scales with
   the attribute.
3. Given a less reliable technique, when a strike resolves, then damage scales
   down; reliability above 1.0 does not amplify.
4. Given an armoured defender, when a strike resolves, then damage is reduced,
   but capped so a hit always lands for at least 10% of offense.
5. Given negative/zero inputs, when a strike resolves, then damage floors at
   zero (never heals).
6. Given a real item + technique + health, when the pipeline runs end-to-end,
   then a mastered giant-sword strike defeats a baseline target.
7. Given a malformed/out-of-bounds request, when parsed, then it fails closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 505 tests / 505 passing, exit 0**. The new
`test_damage_resolution.gd` ran all **12/12** of its tests (attribute scale,
mitigation clamp/cap, reliability scaling, mitigation reduction, the floor-at-
zero rule, the fail-closed matrix, and the end-to-end composition wiring
`ItemContract` + `TechniqueContract` + `CombatHealth`), confirming the script
executed (not a silent preload skip). `check_record_sync.sh` exit 0. GUT cannot
run on Windows, so validation was performed on the Linux host per repo
convention. (This run copied only the composition dependencies —
`item_contract`, `technique_contract`, `combat_health` — plus the new script, so
the suite total reflects those scripts rather than the whole Phase 14 set.)

## Safety invariants

- The server owns every input; this seam only combines server-derived scalars,
  never client-authored damage.
- Damage is floored at zero and never heals; mitigation is capped below 1.0 so a
  landed hit is never fully negated.
- Reliability and mitigation are clamped, so out-of-range state cannot produce an
  absurd result.
- Parsing fails closed on version/structure/bounds; invalid input yields zero
  damage.
- No RNG, critical hits, or hidden state — deterministic given its inputs.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred status effects, critical/to-hit
randomness, and death/respawn are explicit non-goals here and on the Phase 14
map, not liabilities.
