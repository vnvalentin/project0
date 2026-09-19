# Slice 136 - Phase 15 (P-016-C): Kinetic Flow layer (Volume / Control / Output)
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [docs/SYSTEMS-SPECIFICATION.md](../SYSTEMS-SPECIFICATION.md)
("Kinetic Flow Layer"), [#219](https://github.com/vnvalentin/project0/issues/219),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md). Subsystem
slice P-016-C.

## User outcome

A Character's body converts raw attributes into kinetic capability: a big CON
reservoir (Volume), DEX-driven finesse (Control), and STR-driven explosive Output.
A brute with a huge reservoir but no finesse wastes energy — actions cost more —
while a controlled body moves efficiently. The server derives it; the client
renders it.

## Scope and non-goals

In scope: the kinetic tuning namespace on `server/embodiment_tuning.gd` and
`shared/kinetic_flow.gd` — the pure derivation of Volume/Control/Output and the
energy-cost inflation from Control/Volume mismatch.

Out of scope: resolving live kinetic ACTIONS (wall-runs, ground slams, collider
destruction) from authoritative position/velocity/environment — those consume
this derivation later; folding kinetic state into the replicated `derived` map
(server service); and the other subsystems (meridian/burnout/magic, P-016-D…F).

## Public seam

`shared/kinetic_flow.gd` (`KineticFlow`): `derive(effective_nodes, tuning) ->
{volume, control, output, energy_cost_factor}`. `server/embodiment_tuning.gd`
gains `kinetic()` returning the frozen coefficients + slosh penalty.

## Falsifiable hypothesis

If Kinetic Volume/Control/Output are a pure function of the backing effective
nodes under the current tuning, then the same vessel always yields the same
kinetic state, and low Control relative to Volume deterministically inflates
action energy cost — the "sloshing" the spec describes.

## SDD

`KineticFlow.derive` reads the effective CON/DEX/STR and the kinetic tuning:
`volume = CON × volume_coefficient`, `control = DEX × control_coefficient`,
`output = STR × output_coefficient` (negatives clamped to 0). Efficiency is
`clamp(control / volume, 0, 1)` (1.0 when Volume is 0 — no reservoir, no slosh);
`energy_cost_factor = 1 + (1 − efficiency) × slosh_penalty`, so matched
Control/Volume costs 1.0 and a large reservoir with little Control rises toward
`1 + slosh_penalty`. Baseline coefficients are 1.0 and slosh penalty 1.0. Pure and
deterministic; frozen tuning behind `resolve()`.

## BDD

1. Given effective nodes, when derived, then Volume/Control/Output track CON/DEX/
   STR by their coefficients.
2. Given matched Control and Volume, when derived, then the energy cost factor is
   baseline (1.0).
3. Given low Control with high Volume, when derived, then the cost factor inflates
   (sloshing).
4. Given Control exceeding Volume, then efficiency caps and cost stays baseline.
5. Given zero Volume, then there is no divide-by-zero and no slosh penalty.
6. Given the tuning, then it exposes the kinetic namespace.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 499 tests / 499 passing, exit 0**. The new
`test_kinetic_flow.gd` ran **6/6** (node backing, efficient baseline, low-Control
slosh inflation, capped efficiency, zero-Volume safety, and the kinetic tuning
namespace). `check_record_sync.sh` exit 0. GUT cannot run on Windows, so
validation was on the Linux host per repo convention; the new files and the
Phase 15 tuning chain were staged and removed.

## Safety invariants

- Kinetic state is a pure, deterministic derivation from the effective nodes; the
  server owns it and every kinetic action outcome.
- Zero Volume is handled without divide-by-zero; negatives clamp to zero.
- Coefficients and slosh penalty are frozen tuning reached only through
  `resolve()`.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. Resolving live kinetic actions and folding kinetic
state into the replicated `derived` map are explicit later scope, not liabilities.
