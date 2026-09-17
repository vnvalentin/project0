# Slice 111 - Dashboard issue traceability detail
GitHub issue: #206

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing
[F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard).

## User outcome

The dashboard detail screen shows the new GitHub Issue traceability model without
making the operator read stale delivery-roadmap prose. Goal folders under
`.scratch` appear as parent GitHub Issues, local issue files appear as child
planning issues, and unresearched goals are visible instead of disappearing.

## Scope and non-goals

In scope: `dashboard/app.py` detail-view parsing and rendering for GitHub Issue
traceability, parent goal issue counts, child planning issue counts, slice issue
links, and missing `map.md` handling.

Out of scope: changing GitHub Issue state, replacing the Reality view, adding a
front-end framework, changing delivery-record semantics, or creating new product
features.

## Public seam

`GET /detail` from `dashboard/app.py`.

## SDD

The detail view reads local delivery records and open GitHub Issues. It matches
GitHub Issues back to local `.scratch` records through the existing `Source:`
marker in issue bodies. A goal folder with no `map.md` remains visible and is
classified as a new, unresearched goal.

## BDD

1. Given every slice record has a `GitHub issue:` line, when `/detail` renders,
   then the traceability summary reports all slice records linked and zero
   missing slice links.
2. Given GitHub parent goal issues and child planning issues created from
   `.scratch`, when `/detail` renders, then the summary reports 15/15 parent
   goal issues and 95/95 child planning issues.
3. Given `.scratch/zone-sharding` has no `map.md`, when `/detail` renders, then
   `zone-sharding` is shown as a new/unresearched goal instead of being omitted.

## TDD / validation

Focused command:

```bash
python -m py_compile dashboard/app.py
python - <<'PY'
import os
os.environ['PROJECT_ROOT']='.'
import dashboard.app as app
html = app.render('working')
checks = {
    'traceability_heading': 'GitHub traceability baseline' in html,
    'goal_heading': 'Goals · parent issues and child planning issues' in html,
    'old_roadmap_hidden': 'Delivery roadmap' not in html,
    'zone_unresearched': 'zone-sharding' in html and 'new / unresearched' in html,
    'child_count': '95/95' in html,
    'goal_count': '15/15' in html,
}
print(checks)
print('rendered', len(html))
PY
```

Expected pass signal: both commands exit 0 and every check prints `True`.

Observed evidence: `python -m py_compile dashboard/app.py` exited 0; the render
check exited 0 with all six checks `True` and rendered 38588 characters.

Record sync: `bash scripts/check_record_sync.sh`, expected exit 0.

## ADR / telemetry / review

No ADR: this is a dashboard presentation and parser update for an already
accepted workflow rule. No runtime telemetry change: the dashboard is read-only
delivery tooling. Review focus is stale-content removal, issue-link accuracy,
and preserving the existing Reality and Tests screens.
