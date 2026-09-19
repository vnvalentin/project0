# Slice 177 - Dashboard per-slice Goal alignment (real data, not phase-level)

GitHub issue: #374

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)

## User outcome

On the Project0 Flow Dashboard's `/detail` roadmap, each tracker slice row
under a Phase shows the specific Goal issue it is actually aligned to (if
any) — not every Goal touching that slice's Phase.

## Scope and non-goals

In scope: deriving a slice's Goal from data that already exists — its
`docs/slices/NNN-*.md` `GitHub issue:` front-matter, resolved against that
issue's own `Parent goal: #N` reference (or the issue being a Goal issue
itself). No new front-matter field added to slice docs.

Out of scope: the `#95` bulk-backfill placeholder bucket (109/172 slices) is
explicitly excluded from resolution and shown as "no linked goal" rather than
guessed; adding real per-slice `GitHub issue:` links to those slices is a
separate, much larger cleanup not attempted here.

## Public seam

`dashboard/app.py`: `slice_files_by_number()`, `slice_linked_issue_number()`,
`slice_goal_number()` (new), wired into `render()`'s per-phase slice rows.
`slice_issue_stats()` unchanged.

## Falsifiable hypothesis

If a slice's linked GitHub issue is itself a Goal issue, or names a
`Parent goal: #N`, that number is the slice's real Goal alignment and needs no
new tracking field — reusing exactly what `goal_issue_cards()` already parses.

## BDD

1. Given a slice's `GitHub issue:` front-matter resolves to an issue whose body
   contains `Parent goal: #N`, when `/detail` renders that slice's row, then it
   shows a link to Goal `#N`.
2. Given a slice's linked issue is itself labeled `Goal` (or titled `Goal: ...`),
   when rendered, then the slice's row links to that same issue as its goal.
3. Given a slice's `GitHub issue:` line is missing, unresolvable, or points at
   the `#95` backfill placeholder, when rendered, then the row shows "no linked
   goal" rather than any phase-wide guess.

## Root-cause learning

- Symptom: the prior roadmap (Slice 176) showed "goals touched" per Phase, but
  every slice in that phase inherited the same phase-wide goal list, which the
  user correctly flagged as misleading for slices that don't actually touch
  every goal in their phase.
- Public seam: `dashboard/app.py`'s `/detail` route, per-slice rows.
- Falsifiable hypothesis: see above.
- Confirmed root cause: the phase-level rollup was a placeholder pending
  #376's per-slice Goal linkage decision; the real per-slice signal was
  already present in existing GitHub issue bodies (`Parent goal: #N`) and did
  not require the new front-matter field #376 proposed.
- Countermeasure: derive alignment from existing data instead of waiting on a
  slice-doc migration; explicit "no linked goal" instead of a false phase-wide
  positive.
- Regression evidence: see Validation below.
- Remaining limitation: slices without a real (non-`#95`) `GitHub issue:` link
  cannot be goal-aligned at all; only a slice-doc backfill (out of scope here)
  fixes that.

## Validation

- `python -c "import ast; ast.parse(open('dashboard/app.py', encoding='utf-8').read())"` — no syntax errors.
- Invoked `render('committed')` against live repo + GitHub data: 23 of the
  active-phase tracker slices resolved a real Goal (`#100` client-auto-update
  x14, `#354` Nakama v1 integration x9); the rest correctly show "no linked
  goal" instead of a phase-wide guess.
- `scripts/check_record_sync.sh` — 0 errors (6 pre-existing warnings unrelated
  to this change).
- No GUT coverage — Python delivery tooling outside the Godot suite.
