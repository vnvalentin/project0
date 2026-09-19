# Slice 132 - Phase 15 (P-016-A): versioned embodiment tuning resolve seam
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [#219](https://github.com/vnvalentin/project0/issues/219)
(embodiment map), [#220](https://github.com/vnvalentin/project0/issues/220)
(tuning-resource contract), [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
First slice of Phase 15 (P-016-A foundation, part 1 of the L1+L2 sequence).

## User outcome

The groundwork for biological progression: every embodiment balance value
(vessel budget, node floors, opposition weights, training gain) now lives behind
one versioned, server-owned seam. Nothing player-facing changes yet — this is the
reproducible tuning foundation the vessel, friction, kinetic, meridian, burnout,
and magic layers all build on, so balance is authored once, versioned, and never
guessed.

## Scope and non-goals

In scope: `shared/embodiment_tuning_schema.gd` (the tool-neutral shape: node
keys, bounds, outcome enums, pure helpers) and `server/embodiment_tuning.gd`
(the frozen `const` tables + the sole, fail-closed `resolve(tuning_version)`
access seam returning a value object).

Out of scope: vessel progression state and redistribution (Slice 133), the
effective-mechanics snapshot + replication (Slice 134), the server progression
service + headless assertion (later P-016-A part), refined per-node opposition
weights (a later tuning revision behind this same seam), and the friction /
kinetic / meridian / burnout / magic subsystems (P-016-B…F). Server boot-refusal
on unresolved default tuning is wired when the progression service lands.

## Public seam

`server/embodiment_tuning.gd` (`EmbodimentTuning`): the static
`resolve(tuning_version) -> {outcome, detail, tuning}`, `DEFAULT_TUNING_VERSION`,
and the tuning value object's `budget` / `floor_per_node` / `gain_per_evidence`
fields + `floor_for(node)` / `opposition_weights_for(node)`.
`shared/embodiment_tuning_schema.gd` (`EmbodimentTuningSchema`): `NODE_KEYS`,
bounds, `OUTCOME_*`, and `is_supported_node` / `other_nodes` / `sum_over_nodes` /
`check_bounded`.

## Falsifiable hypothesis

If all embodiment tuning is reached only through a fail-closed
`resolve(tuning_version)`, then subsystems never read raw tables, an unknown
version can never silently fall back to a guess, and a bounds-violating table is
refused — so the server can only ever run a known, valid, reproducible tuning.

## SDD

`EmbodimentTuningSchema` owns the shared shape: the six `NODE_KEYS` (matching
`CharacterFoundation`), numeric bounds, `OUTCOME_*`, and pure helpers. Both
processes read it identically; it holds no tables and grants no authority.
`EmbodimentTuning` holds the frozen server-only default tables
(`_BUDGET` 60.0, `_FLOOR_PER_NODE` 4.0, `_GAIN_PER_EVIDENCE` 1.0, uniform
opposition weight 1.0) behind `resolve()`. `resolve` fails closed on an unknown
`tuning_version` (no fallback) and on a self-inconsistent table (bounds + floors
fitting the budget), else returns a stamped value object. `opposition_weights_for`
yields the five-node row (never the node itself); `floor_for` yields the floor
for a supported node, 0 otherwise. Uniform opposition weights are the baseline;
refined weights are a later revision behind the same seam (ADR 0006).

## BDD

1. Given the default version, when resolved, then the frozen tuning is returned,
   stamped with its provenance.
2. Given an unknown or empty version, when resolved, then it fails closed with no
   tuning.
3. Given a trained node, when its opposition row is read, then it covers exactly
   the other five nodes.
4. Given a supported/unsupported node, when its floor is read, then it is the
   floor / 0.
5. Given the shared helpers, then node support, the other-five set, the node sum,
   and bounds checking behave deterministically and fail closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 501 tests / 501 passing, exit 0**. The new
`test_embodiment_tuning.gd` ran **8/8** (resolve returns the frozen default,
rejects unknown and empty versions, the opposition row covers the other five,
unknown-node row is empty, floors for supported/unsupported nodes, the shared
helpers, and `check_bounded` failing closed on non-finite/out-of-range).
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was on
the Linux host per repo convention; the three new files were staged and removed.
(`EmbodimentTuning`'s `resolve()` self-reference trips a standalone
`--check-only` parse but resolves in the full-project GUT load — the 501/501 run
is authoritative.)

## Safety invariants

- Tuning is reached only through `resolve()`; subsystems never read the tables
  directly, and the client never receives them.
- An unknown `tuning_version` fails closed with no fallback guess; a
  bounds-violating table is refused rather than served.
- The schema module holds no authority and no tables — shared shape only.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. Uniform baseline opposition weights and the pending
server boot-refusal are explicit, ADR-anticipated first-cut scope (refined behind
the same seam), not liabilities.
