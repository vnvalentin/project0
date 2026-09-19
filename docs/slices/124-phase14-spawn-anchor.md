# Slice 124 - Phase 14 spawn-anchor / NPC-population contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#232](https://github.com/vnvalentin/project0/issues/232)
(anchors, population, replacement), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

A town stays believably staffed: guard posts and market stalls have their roles
filled, and when a guard is defeated the post does not instantly pop a clone
back into place. After a delay — shorter when the place is busy — the role is
refilled, either by quietly promoting a nearby ambient townsperson into it or,
when there is nobody to promote, by a freshly generated newcomer. The same
person never comes back from the dead.

## Scope and non-goals

In scope: `shared/spawn_anchor.gd` — the fixed anchor's staffing math: role and
desired capacity, deficit, the pressure-scaled replacement delay, whether a
refill is due, and whether it promotes an ambient NPC or generates a new
identity.

Out of scope: contextual identity generation itself, choosing WHICH ambient NPC
is promoted, the actual world spawn/placement, anchor authoring/placement in the
world, and named/story NPC handling (never auto-respawned — a Phase 14
non-goal). The contract decides the staffing action, not how it is carried out.

## Public seam

`shared/spawn_anchor.gd` (`SpawnAnchor`): the static `deficit`,
`effective_delay(base_delay, pressure)`, `is_replacement_due`,
`replacement_source(has_ambient_candidate)`, the instance `current_deficit` /
`is_understaffed` / `advance(ticks)` / `vacate(count)` / `fill()` /
`plan_replacement(pressure, has_ambient_candidate)`, and the fail-closed
`from_wire_dict`.

## Falsifiable hypothesis

If anchor staffing is deterministic math over deficit, a pressure-scaled delay,
and ambient availability, then refills are always delayed (never instant clones),
pressure reproducibly shortens the wait, and a lost occupant is replaced by a
promotion or a new identity — never resurrected — by construction.

## SDD

`deficit = max(0, desired - current)`. `effective_delay = round(base_delay *
(1 - clamp(pressure)))` — full pressure refills immediately, no pressure keeps
the full delay. `is_replacement_due` requires both a deficit and the vacancy
clock reaching the effective delay. `replacement_source` promotes when an ambient
candidate exists, else generates. The instance layers state: `advance`
accumulates the vacancy clock while understaffed and resets it when full;
`vacate` floors occupancy at zero; `fill` caps at desired; `plan_replacement`
combines them into `{due, source}` (source `none` when not due). `from_wire_dict`
fails closed on version, structure, role, and count/delay bounds.

## BDD

1. Given an understaffed anchor, when the deficit is computed, then it is the
   unfilled slots (zero when full/over).
2. Given pressure, when the delay is scaled, then it shortens toward zero at full
   pressure.
3. Given a deficit and an elapsed delay, when checked, then a replacement is due;
   otherwise not.
4. Given ambient availability, when a due replacement is sourced, then it
   promotes; otherwise it generates.
5. Given occupancy changes, when vacated/filled, then occupancy floors at zero
   and caps at desired, and the vacancy clock accumulates/resets correctly.
6. Given a malformed/out-of-bounds request, when parsed, then it fails closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 508 tests / 508 passing, exit 0**. The new
`test_spawn_anchor.gd` ran all **15/15** of its tests (deficit, pressure-scaled
delay, the due predicate, promote/generate sourcing, vacate/fill occupancy
bounds, the vacancy-clock accumulate/reset, the end-to-end `plan_replacement`
decisions, and the fail-closed accept/reject matrix), confirming the script
executed (not a silent preload skip). `check_record_sync.sh` exit 0. GUT cannot
run on Windows, so validation was performed on the Linux host per repo
convention. (Standalone contract with no Phase 14 dependencies; the suite total
reflects the baseline plus this one script.)

## Safety invariants

- The server owns anchor state and the tick clock; clients never author staffing
  or spawns.
- Refills are always delayed and pressure-clamped; occupancy is bounded to
  `[0, desired]`, so no anchor over- or under-flows.
- A lost occupant is replaced by promotion or a new identity — never resurrected.
- Parsing fails closed on version/structure/role/bounds; invalid input yields no
  anchor.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred contextual generation, ambient-candidate
selection, and world placement are explicit non-goals here and on the Phase 14
map, not liabilities. This completes the Phase 14 shared-contract set (Slices
116-124); wiring these contracts into the running server/client is the follow-on
integration work tracked separately.
