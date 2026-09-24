# Bounded handoff — Experiment #1085: bounded sector residency & Canon-preserving eviction

**Governing issue:** #1085 (label `tbp:experiment`, parent epic #1063, milestone #13 "Outcome C-2: Bounded sector streaming").
**Branch (already cut):** `experiment/1085-sector-residency` from `origin/main`.
**Ownership:** Copilot orchestrates/reviews; you (Claude CLI) own application + test + implementation-facing record edits.

## Target slice / one step
Introduce the smallest **residency reconciliation** owner that turns an active signed
sector coordinate into desired / retained / pending / scheduled-eviction /
completed-eviction sets, and prove Canon is untouched by eviction.

## Public seam
`active-sector transition -> desired residency reconciliation -> existing-Canon load
or pending-generation state -> asynchronous runtime/client unload completion ->
durable Canon observation.`

Build **on top of** the existing placement/identity contract; do not change it:
- `shared/sector_identity.gd` — `parse(sector_id) -> {outcome, coordinate: Vector2i}` (signed `sector-X-Z`).
- `server/sector_boundary_detector.gd` — owns per-peer active-sector transition; `sector_id_for_position`, `observe_position`. No DB handle, no async.
- `shared/canon_sector_resolver.gd` / Canon repository — Canon is the durable truth; eviction must not remove any record or revision.

## Proposed shape (adjust if the seam argues otherwise, and record why)
- New pure-logic owner, no DB / no async, e.g. `shared/sector_residency_reconciler.gd`
  (`class_name SectorResidencyReconciler`). Inputs: active `Vector2i` coordinate and
  the current runtime-resident set; outputs a machine-readable bundle:
  `active`, `desired[]`, `retained[]`, `pending[]`, `scheduled_eviction[]`,
  `completed_eviction[]`, `movement_blocked` (must be `false`), and pre/post Canon
  identity+revision values.
- Desired = active sector + its 8 Chebyshev-radius-1 neighbors (exactly 9).
- Scheduled eviction = every resident sector at Chebyshev distance >= 2.
- Completed eviction removes only runtime/client residency; Canon unchanged.
- Duplicate reconciliation and duplicate unload completion are idempotent and never
  remove a newly retained sector.

## Tests (write RED first, then implement)
1. `tests/unit/test_sector_residency_reconciler.gd` — narrow public-seam GUT unit test
   asserting the full falsifiable hypothesis and every Pass Criterion in #1085,
   including idempotent duplicate reconciliation + duplicate stale unload completion,
   and `movement_blocked == false` before all nine materialize.
2. `tests/integration/test_sector_residency_canon_preservation.gd` — Canon-backed
   integration test on Linux (SQLite present) proving eviction leaves Canon
   value-for-value unchanged (pre/post identity + revision).

## Non-goals (do NOT touch)
- The placement contract from #1077 (identity/offsets/neighbor geometry).
- Blocking movement until all nine coordinates materialize.
- Deleting or rewriting Canon during runtime unload.
- Sector archetype/profile validation under Feature #1062.
- Generated geometry / generation prompts.

## Validation (all must pass before complete)
- Focused: run the two new tests via GUT and capture assertion totals.
- Full suite: `scripts/run_gut_validation.sh` (emits `build/validation/gut.xml`,
  `build/validation/validation-summary.json`).
- Record sync: `scripts/check_record_sync.sh` (exit 0).

## Required evidence (record on #1085 before merge)
Exact commit SHA; focused assertion totals; full-suite totals; record-sync result;
generated residency artifact path under `logs/experiments/`; and final Standards/Spec
review findings. Any mismatch vs. hypothesis becomes a Root-cause Learning entry
BEFORE implementation proceeds. Mark #1085 Pass/Fail. Do not mark complete on passing
code alone — evidence + records are mandatory.
