# Slice 119 - Phase 14 technique readiness & proficiency contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#230](https://github.com/vnvalentin/project0/issues/230) /
[#234](https://github.com/vnvalentin/project0/issues/234) (techniques),
[ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

A technique is not handed over by hitting one stat — it becomes usable when the
Character develops the whole combination its action needs (a Jump Slash wants
STR, DEX, WIS, and INT together), and how reliably it executes tracks the
Character's proficiency in it.

## Scope and non-goals

In scope: the deterministic `shared/technique_contract.gd` contract — a
technique's multidimensional readiness requirements, per-node shortfalls,
proficiency-driven reliability, and mastery/teaching gates. Server-authoritative,
fail-closed.

Out of scope: per-Character technique proficiency STATE and its growth/decay,
failed-attempts-teach accrual, the teaching/discovery flow, combinations and
hints, and any UI — later slices per the Phase 14 map's non-goals. Proficiency
values are per-Character state owned by a later slice; this contract only derives
readiness/reliability/mastery from given values.

## Public seam

`shared/technique_contract.gd` (`TechniqueContract`): `is_ready`,
`readiness_shortfalls`, `reliability`, `is_mastered`, `can_teach`, and the
fail-closed `from_wire_dict`.

## Falsifiable hypothesis

If readiness is a pure predicate over effective nodes and reliability is a pure
function of proficiency, then technique availability and quality are reproducible
and auditable, and later progression/combat slices can consume one technique seam
without re-deriving requirements.

## SDD

`is_ready(effective_nodes)` is true only when every required node meets its
threshold (a missing node reads 0.0 and fails). `readiness_shortfalls` reports
each unmet node's deficit. `reliability(proficiency)` clamps to 0..1; mastery
(1.0) is permanent and fully reliable; `can_teach` requires mastery. A
technique's `primary_node` must be one of its requirements (it lives in that
stat's graph zone). Pure and deterministic; the server owns proficiency.

## BDD

1. Given effective nodes, when readiness is checked, then it requires the whole
   stat combination, not any single stat.
2. Given unmet requirements, when shortfalls are computed, then each missing node
   reports its deficit, and a ready technique reports none.
3. Given a proficiency, when reliability is computed, then it tracks proficiency
   and clamps to 0..1.
4. Given a proficiency, when mastery/teaching is checked, then both require full
   proficiency.
5. Given malformed/out-of-bounds/unknown-node/empty-requirements/primary-not-
   required input, when parsed, then it fails closed with a bounded outcome.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **76 scripts / 537 tests / 537 passing, exit 0**. The new
`test_technique_contract.gd` ran all **11/11** of its tests (multidimensional
readiness, per-node shortfalls, reliability clamping, mastery/teaching gates, and
the fail-closed rejection matrix), confirming the script executed (not a silent
preload skip). `check_record_sync.sh` exit 0. GUT cannot run on Windows, so
validation was performed on the Linux host per repo convention.

## Safety invariants

- The server is the sole authority for proficiency and effective nodes;
  readiness/reliability are derived, never client-authored.
- Reliability clamps to 0..1 so no state produces an absurd value.
- Parsing fails closed on version/structure/node/threshold/primary; invalid
  input yields no technique.
- All helpers are pure and deterministic — no RNG, clock, IO.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred proficiency state, teaching/discovery flow,
and combinations are explicit non-goals here and on the Phase 14 map, not
liabilities.
