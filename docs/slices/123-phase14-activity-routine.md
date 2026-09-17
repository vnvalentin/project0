# Slice 123 - Phase 14 activity-routine contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#229](https://github.com/vnvalentin/project0/issues/229)
(activity-driven movement), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

NPCs live to a schedule: the smith forges, then visits the market, then the
tavern, on a loop. An NPC you are not watching keeps its schedule "for free" and,
when you come back, is exactly where its routine says it should be — no drift,
no snapping into place. With nothing scheduled it idles or patrols, and combat
or another event can interrupt its routine and then let it resume where the
clock has moved on to.

## Scope and non-goals

In scope: `shared/activity_routine.gd` — the routine of timed activities, the
pure time→activity resolution (off-screen simulation and route-consistent
arrival via a looping period), idle/patrol fallback for an empty routine, and
the interrupt/resume lifecycle.

Out of scope: pathfinding, world locations/coordinates, rendering and visible
travel, activity-scoped following behaviour, and how activities are authored or
assigned — all scene-layer or later concerns. The routine models WHAT activity
is current over time, not WHERE in the world it happens.

## Public seam

`shared/activity_routine.gd` (`ActivityRoutine`): the static `total_duration`
and `resolve_step(steps, elapsed_ticks)`, the instance `current_activity(
elapsed_ticks)` / `interrupt(activity_id)` / `resume()` / `is_interrupted()`,
and the fail-closed `from_wire_dict`.

## Falsifiable hypothesis

If the current activity is a pure function of elapsed ticks over a looping
routine, then an unobserved NPC needs no per-tick state to stay correct, and
re-resolving at any later time yields the exact route-consistent activity — so
off-screen simulation is free and arrival never drifts.

## SDD

`total_duration` sums step durations into a looping period. `resolve_step`
reduces elapsed ticks modulo the period, walks the cumulative durations, and
returns `{index, activity_id, step_elapsed, step_remaining}` (index -1 for an
empty routine) — a pure function of time, the off-screen simulation.
`current_activity` layers the lifecycle: an interruption overrides everything; an
empty routine falls back to `idle`/`patrol`; otherwise the resolved routine step.
`interrupt`/`resume` toggle state without touching the routine clock, so
resuming lands on the route-consistent activity. `from_wire_dict` fails closed on
version, structure, the steps array, and the fallback enum; an empty routine is
valid (pure fallback).

## BDD

1. Given a routine, when the current step is resolved at a time, then it is the
   correct step with correct elapsed/remaining.
2. Given a time past the period, when resolved, then it loops (route-consistent
   arrival with no drift).
3. Given an empty routine, when the current activity is asked, then it falls back
   to idle or patrol.
4. Given an interruption, when asked, then it overrides the routine activity; on
   resume the routine clock is unchanged.
5. Given a malformed/unknown-fallback/out-of-bounds request, when parsed, then it
   fails closed; an empty steps array is accepted.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 509 tests / 509 passing, exit 0**. The new
`test_activity_routine.gd` ran all **16/16** of its tests (duration sum, step
resolution at start/midpoint/boundary, looping route-consistency, empty-routine
handling, routine/fallback/interrupt sources, interrupt-then-resume clock
preservation, and the fail-closed accept/reject matrix), confirming the script
executed (not a silent preload skip). `check_record_sync.sh` exit 0. GUT cannot
run on Windows, so validation was performed on the Linux host per repo
convention. (Standalone contract with no Phase 14 dependencies; the suite total
reflects the baseline plus this one script.)

## Safety invariants

- The server owns routine assignment and the tick clock; clients never author
  the current activity.
- Activity resolution is a pure, deterministic function of time with no hidden
  per-NPC state, so unobserved NPCs cannot desync.
- Every interruption is reversible via `resume`; the routine clock is never lost.
- Parsing fails closed on version/structure/fallback/bounds; invalid input yields
  no routine.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred pathfinding, world locations, visible
travel, and activity-scoped following are explicit non-goals here and on the
Phase 14 map, not liabilities.
