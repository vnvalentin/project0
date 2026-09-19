# Slice 112 - Reality page Goal source of truth
GitHub issue: #207

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing
[F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard).

## User outcome

The Reality page's GitHub Source of Truth section shows the project goals, not a
flat list of every open issue. Each goal card shows how complete that goal is by
counting closed child issues against all child issues linked to the parent goal.

## Scope and non-goals

In scope: `dashboard/app.py` GitHub issue fetching, parent/child issue grouping,
and Reality page rendering for Goal cards with open/closed child counts and a
completion percentage.

Out of scope: changing GitHub issue state, closing child issues automatically,
replacing the Detail or Tests pages, adding external dependencies, or changing
product delivery status.

## Public seam

`GET /` from `dashboard/app.py`.

## SDD

GitHub Issues are fetched with `state=all` so closed child issues can be counted.
A child issue belongs to a parent goal when its body contains `Parent goal: #N`.
The Reality page renders only issues labeled `Goal` or titled `Goal:` in its
GitHub Source of Truth section. Completion is `closed child issues / total child
issues`, rounded to a percentage; open child count remains visible on the card.

## BDD

1. Given GitHub has 15 parent Goal issues, when `/` renders, then the GitHub
   Source of Truth section contains 15 issue cards.
2. Given non-goal workflow issues and child planning issues exist, when `/`
   renders, then those issues do not appear as cards in the GitHub Source of
   Truth section.
3. Given a Goal has open and closed child issues, when `/` renders, then its card
   shows closed/total child issue counts, open child count, and a completion
   percentage.

## TDD / validation

Focused command:

```bash
python -m py_compile dashboard/app.py
python - <<'PY'
import os
os.environ['PROJECT_ROOT']='.'
import dashboard.app as app
html = app.render_exec('working')
section = html.split('<section class="sec"><h2>GitHub source of truth</h2>', 1)[1].split('</section>', 1)[0]
checks = {
    'renders': len(html) > 1000,
    'goal_cards_only_count': section.count('class="issue"') == 15,
    'has_goal_title': 'Goal:' in section,
    'has_percentage': '%' in section and 'closed /' in section,
    'has_open_child_label': 'open</span>' in section,
    'no_workflow_issue_card': 'Workflow: require every work item' not in section,
    'no_child_issue_card_title': 'basic-monsters issue 01:' not in section,
    'tile_label': 'Open goal child issues' in html,
}
print(checks)
raise SystemExit(0 if all(checks.values()) else 1)
PY
```

Expected pass signal: both commands exit 0 and every check prints `True`.

Observed evidence: `python -m py_compile dashboard/app.py` exited 0; the focused
Reality render assertions exited 0 with all checks true and exactly 15 issue
cards in the GitHub Source of Truth section.

Record sync: `bash scripts/check_record_sync.sh`, expected exit 0.

## ADR / telemetry / review

No ADR: this is dashboard presentation logic for the already accepted GitHub
Issue hierarchy. No runtime telemetry change: the dashboard remains read-only.
Review focus is whether the Reality page now shows only Goal issues and whether
its completion percentage is based on child issue state rather than local prose.
