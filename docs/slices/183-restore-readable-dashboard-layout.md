# Slice 183 - Restore readable dashboard layout and correct closed Goal percentages

GitHub issue: #374

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)

## User outcome

The dashboard uses the prior readable Reality/detail layout instead of the
hard-to-scan replacement roadmap page, and a closed Goal issue no longer
renders as 0% merely because its What Good Looks Like checklist was not
backfilled with checked boxes.

## Scope and non-goals

In scope: restore the committed `dashboard/app.py` entrypoint and Docker
entrypoint; remove the uncommitted `dashboard/roadmap.py` replacement; count a
closed GitHub Goal issue as 100% complete in the existing Goal cards.

Out of scope: changing open Goal percentages without evidence, rewriting Goal
checklists, or touching unrelated workspace changes.

## Public seam

`dashboard/app.py` `goal_issue_cards()` and the existing `/` and `/detail`
routes.

## Falsifiable hypothesis

If the dashboard returns to the last committed `app.py` layout and closed Goal
issues override an empty/unbackfilled WGL checklist, the readability regression
and the misleading 0% for closed Goals disappear without changing open Goal
metrics.

## Validation

- Python AST parse passed.
- `render_exec('committed')` returned HTML successfully.
- Goal #100 changed from 0% to 100% because its GitHub issue is closed.
- Full Goal distribution: 10/16 nonzero; remaining zero values have no closed
  WGL/child evidence.
- `scripts/check_record_sync.sh` reports two pre-existing registry errors for
  slices 172 and 175 plus six pre-existing feature-name warnings; this slice
  introduces no new diagnostics and leaves those unrelated records untouched.
- No unrelated workspace files were staged.
