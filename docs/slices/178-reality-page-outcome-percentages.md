# Slice 178 - Reality (/) page phase bars use real Outcome-label completion

GitHub issue: #374

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)

## User outcome

The Reality (`/`) page's "Delivery by phase" bars show the same phase
completion percentage as `/detail`'s Phase -> Outcome -> Goal/slice roadmap
(Slices 176/177), instead of a second, independently-computed tracker-text
percentage that could silently disagree with it.

## Scope and non-goals

In scope: for phases with an active `Phase N: <title>` GitHub milestone,
`executive_model()`'s phase bars now use `phase_milestones()`'s Outcome-label
completion percentage (same source as `/detail`); phases without a milestone
(all historical, already-100%-done phases) keep their existing tracker-text
percentage as a fallback. `phase_activity_label()` now also shows the
outcomes-complete/total count next to the slices-delivered count.

Out of scope: the overall completion donut (still the existing item-weighted
tracker formula \u2014 a repo-wide aggregate, not a per-phase number, changing it
is separate scope); the pre-existing tracker-parsing gap that omits Phases 15
and 16 from `phase_progress_map()`'s bold-header regex (observed during
validation, not caused by or fixed in this slice).

## Public seam

`dashboard/app.py`: `executive_model()` gains an optional `phase_outcomes`
parameter; `render_exec()` now builds it from `phase_milestones(issue_feed)`
and passes it through. `phase_activity_label()` renders the added outcome
count.

## Falsifiable hypothesis

If `/` and `/detail` compute phase completion from the same
`phase_milestones()` data for active phases, their percentages cannot drift
apart the way a tracker-text percentage and a GitHub-outcome percentage could.

## BDD

1. Given Phase 12 has GitHub milestone `Phase 12: ...` with 0/2 Outcomes
   complete, when `/` renders its phase bar, then it shows 0%, identical to
   `/detail`'s Phase 12 percentage.
2. Given a historical phase (e.g. Phase 1) has no GitHub milestone, when `/`
   renders its phase bar, then it falls back to the existing tracker-text
   percentage (100%), unchanged from before this slice.

## Root-cause learning

- Symptom: user asked to review `/` after building the new Phase/Outcome flow
  on `/detail`; found `/` still computed phase % from `phase_progress_map()`
  tracker text, unrelated to the new milestone/Outcome mechanism.
- Public seam: `dashboard/app.py`'s `/` route (`render_exec`).
- Confirmed root cause: `executive_model()` predates the Phase=milestone
  convention (Slice 176) and was never updated to consume it.
- Countermeasure: thread `phase_milestones()` output through as an override,
  falling back to the tracker-text number only when no milestone exists.
- Remaining limitation: none new; the Phase 15/16 tracker-parsing gap is
  pre-existing and unrelated to this change (only affects the tracker-text
  fallback path, not the new outcome path).

## Validation

- `python -c "import ast; ast.parse(open('dashboard/app.py', encoding='utf-8').read())"` — no syntax errors.
- Invoked `render_exec('committed')` and `render('committed')` against live
  repo + GitHub data: both returned well-formed HTML; Phase 12/13's exec-page
  bars and `/detail`'s Phase 12/13 rows report the same percentage (0%, 0/2
  outcomes each) and the same outcomes-complete/total counts.
- `scripts/check_record_sync.sh` — 0 errors (6 pre-existing warnings unrelated
  to this change).
- No GUT coverage — Python delivery tooling outside the Godot suite.
