# Slice 176 - Dashboard Phase/Outcome/Slice/Goal roadmap rebuild

GitHub issue: #374

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)

## User outcome

An executive looking at the Project0 Flow Dashboard's `/detail` page sees the
currently understood roadmap: every active Phase, how far along it is, which
Outcomes (customer-facing goals) it touches and their completion, which Goal
issues and tracker slices belong to it — driven by live GitHub data instead of
stale or duplicated local conventions.

## Scope and non-goals

In scope: retiring `.scratch`-based goal maps, the GitHub traceability summary,
the old phase/slice tables, and the standalone GitHub-milestone "outcome
tracks" section from `dashboard/app.py`'s `/detail` and `/` routes (per the
retire/keep/merge decisions on issues #374-#380); replacing them with one
Phase -> Outcome -> Goal/slice roadmap section. Phase completion = fraction of
that phase's touching Outcome labels that are fully closed (every Outcome-
labeled issue across the repo), per the 2026-09-19 convention change recorded
on issue #374 (Phase = GitHub milestone, Track renamed Outcome = GitHub label).

Out of scope: per-slice `Goal issue:` front-matter (#376's decision, not yet
added to `docs/slices/*.md`); a dedicated Goal-only page; any change to
`/tests` or `/telemetry`.

## Public seam

`dashboard/app.py`: `phase_milestones()`, `outcome_completion()` (new),
`render()` (rebuilt `/detail`), `render_exec()` (drops the stale milestone
section). Reuses existing `goal_issue_cards()`, `feature_cards()`,
`debt_cards()`, `action_items()`, `slice_index_rows()` unchanged.

## Falsifiable hypothesis

If Phase is read from GitHub milestones and Outcome from GitHub labels instead
of parsing `.scratch` goal maps and a separate GitHub-milestone "Track" concept,
the dashboard can show one consistent Phase -> Outcome -> Goal/slice roadmap
without contradicting itself across `/` and `/detail`.

## BDD

1. Given the live GitHub repo has Phase-titled milestones (`Phase N: <title>`)
   and `Outcome: <name>` labeled issues, when `/detail` is requested, then it
   renders one section per active Phase showing its outcome completion
   fraction, touching Outcome labels, touching Goal issues, milestone issues,
   and tracker slices.
2. Given a Phase has no Outcome-labeled issues yet, when rendered, then its
   completion falls back to the milestone's own closed/total issue ratio.
3. Given `.scratch` goal maps, the old traceability summary, and the old
   phase/slice tables are removed, when `/detail` is requested, then none of
   that content appears; feature cards, Andon debt cards, and action-item
   signals are unaffected.

## Root-cause learning

- Symptom: none (proactive rebuild following an explicit convention-change
  request from the user, not a bug report).
- Public seam: `dashboard/app.py` HTTP routes `/` and `/detail`.
- Falsifiable hypothesis: see above.
- Confirmed root cause: n/a (design change, not a defect).
- Countermeasure: n/a.
- Remaining limitation: slice-to-Goal alignment is still phase-level only
  (a slice's phase's touching Goals), not per-slice, until #376's `Goal issue:`
  slice front-matter is implemented. Tracked as follow-up scope, not a defect
  in this slice.

## Validation

- `python -c "import ast; ast.parse(open('dashboard/app.py', encoding='utf-8').read())"` — no syntax errors.
- Imported `dashboard/app.py` directly (`PROJECT_ROOT` pointed at this repo
  checkout) and invoked `render('committed')`, `render_exec('committed')`,
  `render_tests()`, and `render_telemetry(...)` against live repo + GitHub
  data: all four returned well-formed HTML with no exceptions.
- Spot-checked `/detail` output contains Phase 12/13/16/18 headers, the new
  `Outcome: Nakama multiplayer backend adoption` label, and Goal-issue chips
  (`target_percent`) — confirming real GitHub milestone/label/goal data flows
  through, not placeholder content.
- No GUT coverage — this is Python delivery tooling outside the Godot suite,
  consistent with F-025's existing validation approach.
