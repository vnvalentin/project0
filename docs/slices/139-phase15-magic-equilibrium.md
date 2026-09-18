# Slice 139 - Phase 15 (P-016-F): Magic equilibrium
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [docs/SYSTEMS-SPECIFICATION.md](../SYSTEMS-SPECIFICATION.md)
("Magic Equilibrium And Opportunity Cost"),
[#219](https://github.com/vnvalentin/project0/issues/219),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md). Final
subsystem slice (P-016-F).

## User outcome

Magic has a real, embodied opportunity cost. A hyper-bulked brute's muscle mass
grounds magical currents, so a spell fizzles or backlashes rather than firing;
higher-tier magic demands the player organically lean the vessel out, trading
brute force for concentration. A magic attempt is always resolved explicitly by
the server — never a client-chosen success, and never silently swallowed.

## Scope and non-goals

In scope: the magic tuning namespace on `server/embodiment_tuning.gd` and
`shared/magic_equilibrium.gd` — the pure, deterministic resolution of a magic
attempt (CHANNELED / FIZZLE / BACKLASH / REJECTED with a bounded reason) from the
effective vessel bulk, requested spell tier, and tuning.

Out of scope: a spell list, mana constants, or final balance thresholds (all
tuning/future); the server channel-request path + resource cost + revision; and
folding equilibrium state into the replicated `derived` map (server service).
This slice defines the equilibrium rule, not the casting pipeline.

## Public seam

`shared/magic_equilibrium.gd` (`MagicEquilibrium`): `resolve(effective_nodes,
spell_tier, tuning) -> {outcome, reason}`, `insulation_for(effective_nodes,
tuning)`, and the `OUTCOME_*` / `REASON_*` constants.
`server/embodiment_tuning.gd` gains `magic()` returning the insulation
coefficient, per-tier channel ceiling, fizzle margin, and max tier.

## Falsifiable hypothesis

If magic eligibility is a pure function of vessel bulk (insulation) versus a
tier-scaled channel ceiling, then a lean vessel channels, a bulked vessel fizzles
or backlashes, higher tiers require leaning out, and every attempt returns an
explicit outcome — never a silent success or consumption.

## SDD

`resolve` computes `insulation = (STR + CON) × coefficient` and a tier ceiling
`base_channel_ceiling − (tier − 1) × ceiling_step_per_tier` (floored at 0), so
higher tiers tolerate less insulation. Insulation at/under the ceiling →
`CHANNELED`; within `fizzle_margin` above → `FIZZLE` (insufficient equilibrium);
beyond → `BACKLASH` (insulation overload). An out-of-range tier → `REJECTED`
(unsupported tier). Every branch returns an explicit `{outcome, reason}`. Baseline
tuning: coefficient 1.0, base ceiling 40, step 8/tier, fizzle margin 12, max tier
5. Pure and deterministic; thresholds are frozen tuning behind `resolve()`.

## BDD

1. Given a lean vessel, when a low tier is attempted, then it channels.
2. Given a bulked brute, when a low tier is attempted, then it fizzles.
3. Given a hyper-bulked juggernaut, when a low tier is attempted, then it
   backlashes.
4. Given a high tier, then a baseline vessel fizzles while a drastically
   leaned-out vessel channels.
5. Given an out-of-range tier, then it is rejected — never silent.
6. Given any attempt, then it returns one explicit outcome.
7. Given the tuning, then it exposes the magic namespace.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 501 tests / 501 passing, exit 0**. The new
`test_magic_equilibrium.gd` ran **8/8** (lean channels, brute fizzles, juggernaut
backlashes, high-tier lean-out requirement, out-of-range rejection, the
always-explicit-outcome invariant, bulk-derived insulation, and the magic tuning
namespace). `check_record_sync.sh` exit 0. GUT cannot run on Windows, so
validation was on the Linux host per repo convention; the new files and the
Phase 15 tuning chain were staged and removed.

## Safety invariants

- Eligibility is a pure, deterministic server-side derivation; the client can
  never select a success.
- Every attempt returns an explicit CHANNELED/FIZZLE/BACKLASH/REJECTED with a
  bounded reason — never silently consumed.
- Thresholds are frozen tuning reached only through `resolve()`; no spell list or
  mana constants are hardcoded here.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. The casting pipeline (channel request, resource cost,
revision) and folding equilibrium into the replicated `derived` map are explicit
later scope, not liabilities. With this slice, all five Phase 15 embodiment
subsystems (friction, kinetic, meridian, burnout, magic) are delivered on the
P-016-A read-model; the remaining work is the server progression service that
wires the vessel + subsystems into live replication.
