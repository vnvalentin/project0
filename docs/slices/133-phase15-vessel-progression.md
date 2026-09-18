# Slice 133 - Phase 15 (P-016-A): vessel progression state + fixed-budget redistribution
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [#219](https://github.com/vnvalentin/project0/issues/219),
[#223](https://github.com/vnvalentin/project0/issues/223) (redistribution
algorithm), [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
P-016-A foundation, part 2 (consumes Slice 132's `EmbodimentTuning`).

## User outcome

A Character's body now grows the way the design intends: training a node makes it
stronger, but the fixed vessel area means other nodes compress to pay for it —
never a free stat inflation. You keep exactly the graph you earn, and a gain that
would breach the body's floors is rejected cleanly rather than silently mangling
your build.

## Scope and non-goals

In scope: `shared/vessel_progression_state.gd` — the durable earned `base_nodes`
pinned to a `tuning_version`, the balanced-baseline factory, the fail-closed
`from_wire_dict`, and the ADR-0006 fixed-budget redistribution on `train`
(weighted opposition compression, floor clamp + deterministic re-spread, atomic
reject-at-capacity).

Out of scope: the effective-mechanics snapshot + client replication (Slice 134),
the server progression service + training-evidence validation + headless
assertion (later P-016-A part), refined per-node opposition weights (a tuning
revision), vessel migration between tuning versions (Phase 17 fog), and the
friction/kinetic/meridian/burnout/magic subsystems (P-016-B…F).

## Public seam

`shared/vessel_progression_state.gd` (`VesselProgressionState`):
`create_baseline(tuning)`, `train(node, evidence_units, tuning) ->
{outcome, detail}`, `from_wire_dict(wire, tuning) -> {outcome, detail, vessel}`,
and the durable `base_nodes` / `tuning_version` fields.

## Falsifiable hypothesis

If every vessel gain redistributes across weighted, floored opposers and rejects
atomically when no eligible capacity remains, then the fixed budget is always
preserved, no node is ever pushed below its floor, and a rejected or mismatched
train changes nothing — so earned state stays exactly as earned and reproducible.

## SDD

`base_nodes` is frozen earned state, pinned to the build `tuning_version`.
`create_baseline` splits the tuning budget equally across the six nodes.
`train` validates the node, the positive finite evidence, and that the supplied
tuning matches the pin, then computes `gain = evidence * tuning.gain_per_evidence`
and calls `_redistribute`: add the gain to the trained node and remove it from the
opposers weighted by `opposition_weights_for`, capped by each opposer's capacity
above `floor_for`. A floored opposer's leftover deficit re-spreads across
still-eligible opposers (renormalized weights, fixed node order, bounded passes).
It rejects `rejected_at_capacity` when the opposers' total capacity above floors
cannot absorb the gain. Commit is atomic — `base_nodes` is only replaced on `ok`.
`from_wire_dict` fails closed on version, structure, node bounds, and the fixed
budget.

## BDD

1. Given a fresh vessel, then it is balanced and pinned to its tuning.
2. Given a gain, when trained, then the node grows and the budget is preserved by
   uniform opposer compression.
3. Given a gain equal to total capacity, when trained, then all opposers floor
   exactly and it succeeds.
4. Given a gain beyond capacity, when trained, then it is rejected atomically
   (no change).
5. Given a low opposer, when trained, then it clamps at its floor and the deficit
   re-spreads; no node goes below the floor and the budget holds.
6. Given an unsupported node, non-positive evidence, or a mismatched tuning, then
   it fails closed and changes nothing.
7. Given a persisted state, when parsed, then a budget-breaking or bad-version
   base is refused.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 504 tests / 504 passing, exit 0**. The new
`test_vessel_progression_state.gd` ran **11/11**: balanced pinned baseline, gain +
budget preservation, uniform opposer compression, exact-capacity flooring,
over-capacity atomic rejection, the floor-clamp-and-re-spread on an asymmetric
vessel (DEX clamped at its floor, deficit re-spread, no node below floor, budget
held), and the unsupported-node / non-positive-evidence / tuning-mismatch /
`from_wire` fail-closed matrix. `check_record_sync.sh` exit 0. GUT cannot run on
Windows, so validation was on the Linux host per repo convention; the new files
and the Slice 132 tuning deps were staged and removed.

## Safety invariants

- `base_nodes` is server-owned durable earned state; the fixed budget is always
  preserved and no node ever drops below its floor.
- A gain that cannot preserve the budget is rejected as an atomic no-op; a
  mismatched or malformed train changes nothing.
- The vessel is pinned to its build `tuning_version`; gains are evaluated with the
  pinned tuning.
- Parsing fails closed on version/structure/bounds/budget.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. Uniform opposition weights and deferred vessel
migration are explicit ADR-anticipated scope, not liabilities.
