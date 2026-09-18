# Slice 137 - Phase 15 (P-016-D): Meridian pathways
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [docs/SYSTEMS-SPECIFICATION.md](../SYSTEMS-SPECIFICATION.md)
("Meridian Pathways"), [#219](https://github.com/vnvalentin/project0/issues/219),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md). Subsystem
slice P-016-D.

## User outcome

Sustained cross-training between two attributes permanently burns open a Meridian
pathway — Impact (STR+CON), Flow (DEX+WIS), or Spark (STR+DEX) — a durable
capability the player earns. Because progress is deduplicated, a player can never
farm the same training twice, and a reconnect or replay can never double-count or
re-unlock.

## Scope and non-goals

In scope: the meridian tuning namespace on `server/embodiment_tuning.gd` and
`shared/meridian_state.gd` — the per-pathway progress state, deduplicated
evidence accumulation, and the deterministic, idempotent, durable unlock.

Out of scope: what a validated piece of cross-training evidence looks like and
how the server produces it, the pathways' activation costs/effects/temporary
status (runtime state elsewhere), folding Meridian state into the replicated
`derived` map (server service), and the other subsystems (burnout/magic,
P-016-E…F).

## Public seam

`shared/meridian_state.gd` (`MeridianState`): `nodes_for(pathway)`,
`record_evidence(evidence_id, amount, tuning) -> {outcome, progressed,
newly_unlocked}`, `is_unlocked()`, and the `PATHWAY_*` / `PATHWAY_NODES`
constants. `server/embodiment_tuning.gd` gains `meridian()` returning the unlock
threshold.

## Falsifiable hypothesis

If Meridian progress is driven by deduplicated evidence ids and unlock is a pure
threshold transition, then replaying the same evidence can neither increment
progress nor emit a second unlock, distinct evidence accumulates deterministically,
and the unlock is durable — exactly the idempotency the spec requires.

## SDD

`MeridianState` holds a `pathway`, accumulated `progress`, an `unlocked` flag, and
a consumed-evidence-id set. `record_evidence` rejects an unsupported pathway or
malformed (empty id / non-positive / non-finite amount), returns
`duplicate_evidence` (a no-op) for a seen id, else marks the id consumed, adds the
amount, and unlocks once — setting `newly_unlocked` only on the crossing tick —
when progress reaches the tuning threshold (100.0 baseline). Unlock is durable
(further evidence never re-emits it). `nodes_for` maps each pathway to its two
channelled nodes. Pure and deterministic; threshold is frozen tuning.

## BDD

1. Given a pathway, when queried, then it maps to its two nodes.
2. Given fresh evidence, when recorded, then progress accumulates and stays locked
   below the threshold.
3. Given evidence crossing the threshold, when recorded, then it unlocks exactly
   once.
4. Given a replayed evidence id, when recorded, then it is a no-op (no progress,
   no re-unlock).
5. Given an unlocked pathway, when more evidence arrives, then the unlock does not
   re-emit and stays durable.
6. Given malformed evidence or an unsupported pathway, then it fails closed.
7. Given the tuning, then it exposes the meridian namespace.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 501 tests / 501 passing, exit 0**. The new
`test_meridian_state.gd` ran **8/8** (pathway node mapping, progress accumulation,
threshold unlock-once, replay idempotency, durable non-re-emitting unlock, the
malformed/unsupported-pathway fail-closed matrix, and the meridian tuning
namespace). `check_record_sync.sh` exit 0. GUT cannot run on Windows, so
validation was on the Linux host per repo convention; the new files and the
Phase 15 tuning chain were staged and removed.

## Safety invariants

- Progress is driven by deduplicated evidence ids; a replay can never increment
  progress or re-unlock (deterministic idempotency).
- Unlocks are durable and emit exactly once at the crossing tick.
- The server owns the live state; the threshold is frozen tuning reached only
  through `resolve()`.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. Evidence production, pathway activation effects, and
folding Meridian state into the replicated `derived` map are explicit later scope,
not liabilities.
