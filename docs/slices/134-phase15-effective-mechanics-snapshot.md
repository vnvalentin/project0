# Slice 134 - Phase 15 (P-016-A): effective mechanics snapshot (derived, presentation-safe read-model)
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [#219](https://github.com/vnvalentin/project0/issues/219),
[#224](https://github.com/vnvalentin/project0/issues/224) (delivery sequence),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md). P-016-A
foundation, part 3 (the L1+L2 read-model; consumes Slices 132–133).

## User outcome

The game can now show a Character's live capability without ever leaking the
hidden numbers. The server derives runtime power from the earned vessel under the
current balance tuning, and the client receives only the normalized "shape" of
that power — the spider-graph proportions — so balance changes are transparent
and universal, never a peek at raw stats.

## Scope and non-goals

In scope: `shared/effective_mechanics_snapshot.gd` — the deterministic derivation
of effective node values from a `VesselProgressionState` under the current tuning,
the presentation-safe `to_presentation_snapshot()` (normalized graph proportions +
tuning provenance + a `derived` map for subsystem summaries), and the fail-closed
client-side `from_presentation_wire`.

Out of scope: the server progression service that owns training-evidence
validation and drives replication + the headless end-to-end assertion (later
P-016-A part / server wiring), and the subsystem modifiers (friction/kinetic/
meridian/burnout/magic, P-016-B…F) that populate the `derived` map and adjust the
effective nodes on top of this foundation.

## Public seam

`shared/effective_mechanics_snapshot.gd` (`EffectiveMechanicsSnapshot`):
`derive(vessel, current_tuning)`, the `effective_nodes` / `tuning_version` /
`derived` fields, `to_presentation_snapshot()`, and the static
`from_presentation_wire(wire) -> {outcome, detail, snapshot}`.

## Falsifiable hypothesis

If effective mechanics are a pure derivation from the durable vessel under the
current tuning, and only the normalized graph crosses to the client, then the
same vessel + tuning always yields an identical snapshot (reproducible balance),
and the client can render capability without ever receiving a raw number — the
presentation-safe boundary the whole progression layer replicates through.

## SDD

`derive` copies the vessel's `base_nodes` into `effective_nodes` (foundation: no
modifiers yet) and stamps the CURRENT tuning's `tuning_version` (per ADR 0006,
effective power uses live tuning while earned base stays pinned).
`to_presentation_snapshot` normalizes the effective nodes into `graph_axes`
(each axis's share of the total, summing to 1.0), plus the tuning stamp and the
`derived` map — never the raw effective numbers. `from_presentation_wire` fails
closed on version, structure, per-axis 0..1 bounds, and the sum-to-1.0
normalization. Pure and deterministic; later subsystem layers add to
`effective_nodes` and `derived` without changing this seam.

## BDD

1. Given a baseline vessel, when derived, then effective equals earned base and
   there are no subsystem modifiers.
2. Given the current tuning, when derived, then the snapshot is stamped with it.
3. Given the same vessel + tuning, when derived twice, then the presentation
   snapshots are identical (determinism).
4. Given a trained vessel, when presented, then the graph is normalized and the
   trained node dominates its share.
5. Given the presentation snapshot, then it contains no raw base/effective
   numbers.
6. Given a wire snapshot, when parsed, then valid normalized axes are accepted
   and unnormalized/bad-version/non-dictionary inputs fail closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 501 tests / 501 passing, exit 0**. The new
`test_effective_mechanics_snapshot.gd` ran **8/8** (effective equals base at the
foundation, current-tuning stamp, derivation determinism, normalized graph
reflecting a trained node's larger share, the no-raw-numbers presentation-safe
invariant, and the `from_presentation_wire` accept/reject matrix incl.
unnormalized axes). `check_record_sync.sh` exit 0. GUT cannot run on Windows, so
validation was on the Linux host per repo convention; the new files and the
Phase 15 chain were staged and removed.

## Safety invariants

- Derivation is pure/deterministic — the same vessel + tuning always yields the
  same snapshot (reproducible balance).
- Only normalized graph proportions cross to the client; raw effective/base
  numbers stay server-side.
- Parsing fails closed on version/structure/bounds/normalization.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. The `derived` map being empty and effective equalling
base are the explicit foundation scope; subsystems (P-016-B…F) build on this seam.
