# Slice 114 - Goal target coverage cards
GitHub issue: #214

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing
[F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard).

## User outcome

The Reality page Goal cards show a conservative target-condition coverage value
instead of claiming that a goal is complete just because its currently known
child issues are resolved.

## Scope and non-goals

In scope: `dashboard/app.py` Goal-card calculation and rendering for target
coverage from the parent Goal state plus child planning issue status, while
preserving known child coverage and GitHub open/closed counts on each card.

Out of scope: changing GitHub issue state, changing the goal/child issue
hierarchy, changing product delivery status, or replacing the Detail and Tests
pages.

## Public seam

`GET /` from `dashboard/app.py`, specifically the GitHub Source of Truth Goal
cards.

## SDD

The dashboard treats child planning issue status as known child coverage, not as
proof that the whole parent Goal target is closed. A Goal with the `new` label or
a missing `map.md` source shows 0% target coverage because the goal has not been
researched. A closed parent Goal shows 100%. An open parent Goal may show child
coverage, but its target coverage is capped below complete because there can
still be fog to clear and additional child issues to discover.

## BDD

1. Given a new parent Goal has no `map.md`, when the Reality page renders, then
   its Goal card shows 0% target coverage even if it has a child issue.
2. Given an open parent Goal has all currently known child issues resolved, when
   the Reality page renders, then target coverage stays below 100% while known
   child coverage shows the resolved/total child issue count.
3. Given child issues may be open or closed in GitHub, when the Goal card
   renders, then GitHub open/closed counts remain visible separately from target
   coverage.
4. Given the GitHub Source of Truth section renders, then it still contains only
   parent Goal cards.

## TDD / validation

Focused command:

```bash
python -m py_compile dashboard/app.py
python - <<'PY'
import os
os.environ['PROJECT_ROOT']='.'
import dashboard.app as app
feed = app.github_issues()
goals = app.goal_issue_cards(feed)
html = app.render_exec('working')
section = html.split('<section class="sec"><h2>GitHub source of truth</h2>', 1)[1].split('</section>', 1)[0]
checks = {
    'goal_cards': section.count('class="issue"') == 15,
    'target_coverage_label': 'Target coverage:' in section,
    'coverage_percent': '%' in section,
    'closed_label': 'closed</span>' in section,
    'open_label': 'open</span>' in section,
   'new_goal_zero': next(g for g in goals if g['number'] == 204)['target_percent'] == 0,
   'open_complete_children_capped': next(g for g in goals if g['number'] == 96)['target_percent'] < 100,
   'known_child_coverage_visible': 'known child coverage' in section,
}
print(checks)
raise SystemExit(0 if all(checks.values()) else 1)
PY
```

Expected pass signal: both commands exit 0 and every check prints `True`.

Observed evidence: `python -m py_compile dashboard/app.py` exited 0; focused
Reality render assertions verified #204 reports 0% target coverage, open goals
with all currently known children resolved stay below 100%, and known child
coverage remains visible separately from GitHub open/closed counts.

Record sync: `bash scripts/check_record_sync.sh`, expected exit 0.

## ADR / telemetry / review

No ADR: this is dashboard presentation logic for the accepted GitHub goal/child
issue hierarchy. No runtime telemetry change: the dashboard remains read-only.
Review focus is whether the Goal card separates target-condition coverage from
GitHub open/closed issue state.
