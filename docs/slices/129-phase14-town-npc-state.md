# Slice 129 - Phase 14 integration: live town-NPC state (Character + ActivityRoutine)
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#229](https://github.com/vnvalentin/project0/issues/229)
(activity-driven movement), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
First of three slices closing the exit gate's "What Good Looks Like" item 4
(NPC activities, off-screen simulation, route-consistent arrivals). Consumes
[Slice 123](123-phase14-activity-routine.md)'s `ActivityRoutine` and
[Slice 116](116-phase14-character-foundation-handoff.md)'s `CharacterFoundation`.

## User outcome

The world gains living townsfolk: a town NPC is a Character (the same vessel the
player and monster use, AI-controlled) that follows a daily schedule, walking
between the forge, market, and tavern. Unwatched, it keeps its schedule for free
and, when a player looks again, it is exactly where its route says — no snapping.
A nearby event can interrupt its routine, and it holds its place until it resumes.

## Scope and non-goals

In scope: `server/server_town_npc_state.gd` — the town NPC entity: its shared
`CharacterFoundation`, its `ActivityRoutine`, the pure time→position derivation
(travel between activity locations, off-screen simulation, route-consistent
arrival), interrupt/resume with position freezing, and a relevance check.

Out of scope: the population manager (anchors, pressure, replacement — Slice
130), wiring into `server_main` and client replication/rendering (Slice 131),
pathfinding/obstacle avoidance (straight-line route interpolation for now), and
combat behaviour (town NPCs are non-combat here).

## Public seam

`server/server_town_npc_state.gd` (`ServerTownNpcState`): `current_activity(
elapsed_ticks)`, `position_at(elapsed_ticks)`, `interrupt(activity_id,
at_elapsed_ticks)` / `resume()` / `is_interrupted()`, `is_relevant(observer_
positions, radius)`, and the presentation-safe `character_snapshot()`.

## Falsifiable hypothesis

If a town NPC's position is a pure function of elapsed ticks over its
ActivityRoutine and a per-activity location map, then it needs no per-tick state
to stay correct off-screen, and re-resolving at any later time yields the exact
route-consistent position — so activity-driven movement and arrival are correct
by construction, reusing the shared Character seam.

## SDD

`ServerTownNpcState` is an AI-controlled `CharacterFoundation` of kind
"villager". `position_at` resolves the current routine step
(`ActivityRoutine.resolve_step`, a pure function of ticks) and linearly
interpolates from the previous activity's world location to the current one
across the step, so the NPC arrives at each station by the end of its step and
travel is continuous across the looping route. An empty routine holds at home.
`interrupt` freezes the position captured at the interruption tick until
`resume`. `character_snapshot()` is presentation-safe (no raw numbers).
RefCounted + deterministic, unit-testable like `ServerMonsterState`.

## BDD

1. Given a town NPC, when its snapshot is read, then it is an AI-controlled
   "villager" Character.
2. Given a schedule, when position is resolved mid-step, then the NPC is on the
   route between the previous and current stations.
3. Given the end of a step, when position is resolved, then the NPC has arrived
   at that activity's station.
4. Given a time past the period, when resolved, then the route loops with no
   drift (off-screen simulation).
5. Given an interruption, when the NPC is asked, then it holds its position; on
   resume it rejoins the route clock.
6. Given the snapshot, when inspected, then no raw stat numbers leak.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green —
**73 scripts / 502 tests / 502 passing, exit 0**. The new
`test_server_town_npc_state.gd` ran **9/9** (AI villager Character, route travel,
arrival at station by end of step, looping route-consistency, empty-routine
home hold, interrupt-freeze + resume, current-activity, relevance detection, and
the presentation-safe snapshot). `check_record_sync.sh` exit 0. GUT cannot run on
Windows, so validation was on the Linux host per repo convention; the new files
and their merged-but-undeployed dependencies (`character_foundation`,
`activity_routine`) were staged and then removed.

## Safety invariants

- The server owns the town NPC's schedule and position; nothing is client-authored.
- Position is a pure, deterministic function of time with no hidden per-NPC
  state, so unobserved NPCs cannot desync.
- Every interruption is reversible via `resume`.
- The Character snapshot is presentation-safe (no raw stat numbers).

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry. Straight-line route interpolation (no pathfinding)
is a deliberate first-cut simplification noted as a non-goal, not a liability;
the population manager and client replication follow in Slices 130-131.
