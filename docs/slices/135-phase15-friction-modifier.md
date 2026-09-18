# Slice 135 - Phase 15 (P-016-B): inverse friction modifier (Massive Bulk / Fragile Agility)
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [docs/SYSTEMS-SPECIFICATION.md](../SYSTEMS-SPECIFICATION.md)
("Inverse Biological Friction"), [#219](https://github.com/vnvalentin/project0/issues/219),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md). First
subsystem slice (P-016-B) atop the P-016-A read-model.

## User outcome

Pushing a body to a physical extreme has organic consequences. A Massive Bulk
build (huge STR and CON) dodges shorter, recovers slower from swings, and sinks
in water; a Fragile Agility build (high DEX with shed structural mass) regenerates
stamina almost instantly and skips across water but shatters under a stray hit.
The server derives this cost from the vessel; the client just renders it.

## Scope and non-goals

In scope: the friction tuning namespace on `server/embodiment_tuning.gd`
(profile thresholds + modifier factors) and `shared/friction_modifier.gd` — the
pure, deterministic derivation of the Massive Bulk / Fragile Agility / none
profile and its modifier factors from the effective nodes.

Out of scope: applying the factors to live movement/combat (they are consumed by
those systems later), folding friction into the `EffectiveMechanicsSnapshot`'s
`derived` map (the server progression service wiring), overlap-combination across
multiple temporary effects (documented deterministic order lands with more
effects), and the other subsystems (kinetic/meridian/burnout/magic, P-016-C…F).

## Public seam

`shared/friction_modifier.gd` (`FrictionModifier`): `derive(effective_nodes,
tuning) -> {profile, dodge_distance_factor, windup_recovery_factor,
stamina_regen_factor, stagger_resistance_factor, water_behavior}` and the
`PROFILE_*` / `WATER_*` constants. `server/embodiment_tuning.gd` gains
`friction()` returning the frozen friction params.

## Falsifiable hypothesis

If the friction profile is a pure function of the effective nodes under the
current tuning, then the same vessel always yields the same friction cost, the
two profiles are mutually exclusive (by CON), and the client can render the
replicated result without independently selecting the curve.

## SDD

`FrictionModifier.derive` reads the effective STR/DEX/CON and the friction
tuning. Massive Bulk triggers when STR and CON both meet the bulk threshold
(16.0): dodge distance ×0.5, wind-up/recovery ×1.5, water `sink`. Fragile Agility
triggers when DEX meets its threshold (16.0) and CON is at/under the fragile
ceiling (6.0): stamina regen ×3.0, stagger resistance ×0.0, water
`skip_then_sink`. The profiles are mutually exclusive by CON; Massive Bulk is
evaluated first as the documented deterministic order. Otherwise `none` with
neutral factors and `float`. The spec's "MET (Metabolism)" is read as shed
structural mass (low CON) since the six-node vessel has no MET node. Thresholds
and factors are frozen tuning behind `resolve()`.

## BDD

1. Given a balanced vessel, when derived, then there is no friction profile
   (neutral factors, float).
2. Given high STR + high CON, when derived, then Massive Bulk shrinks dodge,
   lengthens recovery, and sinks.
3. Given high DEX + low CON, when derived, then Fragile Agility regenerates fast,
   zeroes stagger resistance, and skips water.
4. Given high STR alone or high DEX with normal CON, then no profile triggers.
5. Given values exactly at the thresholds, then the boundary qualifies; just
   below does not.
6. Given the tuning, then it exposes the friction namespace.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 500 tests / 500 passing, exit 0**. The new
`test_friction_modifier.gd` ran **7/7** (balanced → none, Massive Bulk
dodge/recovery/sink, Fragile Agility regen/stagger/water, the both-conditions-
required negatives, threshold boundaries, and the tuning friction namespace).
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was on
the Linux host per repo convention; the new files and the Phase 15 tuning chain
were staged and removed.

## Safety invariants

- Friction is a pure, deterministic derivation from the effective nodes; the
  server owns it and the client renders the replicated result, never selecting
  the curve.
- The two profiles are mutually exclusive; overlap is resolved by a documented
  deterministic order (Massive Bulk first).
- Thresholds and factors are frozen tuning reached only through `resolve()`.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. Applying the factors to live movement/combat and
folding friction into the replicated `derived` map are explicit later scope, not
liabilities.
