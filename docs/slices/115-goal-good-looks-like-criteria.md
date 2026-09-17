# Slice 115 - Goal What Good Looks Like criteria
GitHub issue: #215

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing
[F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard) and
[P-004](../FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration).

## User outcome

A Goal is no longer treated as complete just because its current child issues are
done. Each researched Goal now has explicit customer-outcome criteria describing
what good looks like, and the dashboard target-coverage metric is based on those
criteria.

## Scope and non-goals

In scope: the goal-completion rule in the workflow/constitution, explicit
`## What Good Looks Like` checklists in existing `.scratch/*/map.md` files,
mirroring those sections into parent GitHub Goal issues, and dashboard parsing
of the criteria for Reality Goal cards.

Out of scope: inventing a map for `zone-sharding`, automatically closing parent
Goal issues, changing child issue hierarchy, or changing product behavior.

## Public seam

- `.scratch/<goal>/map.md` as the local goal definition.
- Parent GitHub Goal issue body as the mirrored goal definition.
- `GET /` from `dashboard/app.py`, specifically the Goal cards in GitHub Source
  of Truth.

## SDD

A Goal's target condition is a checklist under `## What Good Looks Like`. Child
issues remain known work and learning questions; they are not the goal's success
condition. The dashboard parses the parent Goal issue body for the WGL checklist
and computes target coverage as checked criteria divided by total criteria. A
Goal with no map or no criteria reports 0% and is visibly incomplete.

## BDD

1. Given a researched Goal has WGL criteria, when the Reality page renders, then
   its Goal card shows criteria-based target coverage.
2. Given a Goal's current child issues are complete but one WGL criterion remains
   unchecked, when the card renders, then target coverage remains below 100%.
3. Given `zone-sharding` has no map, when the card renders, then target coverage
   is 0% and criteria are marked missing.
4. Given local maps are mirrored to GitHub, when the dashboard fetches parent
   Goal issues, then it can calculate WGL coverage from GitHub without reading
   child issues as the acceptance criteria.

## TDD / validation

Focused command:

```bash
python -m py_compile dashboard/app.py
python - <<'PY'
import os
os.environ['PROJECT_ROOT']='.'
import dashboard.app as app
app._ISSUE_CACHE['at'] = 0
feed = app.github_issues()
goals = app.goal_issue_cards(feed)
by = {g['number']: g for g in goals}
html = app.render_exec('working')
section = html.split('<section class="sec"><h2>GitHub source of truth</h2>', 1)[1].split('</section>', 1)[0]
checks = {
    'goal_cards': section.count('class="issue"') == 15,
    'target_coverage_label': 'Target coverage:' in section,
    'criteria_missing_visible': 'criteria missing' in section,
    'zone_new_zero': by[204]['target_percent'] == 0 and by[204]['criteria_missing'],
    'basic_monsters_partial': by[96]['target_percent'] == 75,
    'world_scale_complete': by[198]['target_percent'] == 100,
    'child_coverage_still_visible': 'known child coverage' in section,
}
print(checks)
raise SystemExit(0 if all(checks.values()) else 1)
PY
bash scripts/check_record_sync.sh
```

Expected pass signal: all commands exit 0; every dashboard assertion is `True`;
record-sync reports 0 errors.

Observed evidence: the focused checks passed. Parent GitHub Goal issues with map
sources were updated from local maps: 14 updated, 14 contain WGL, 1 missing-map
goal skipped, no failures. Dashboard assertions verified 15 Goal cards,
`zone-sharding` at 0% with missing criteria, `basic-monsters` at 75%,
`world-scale` at 100%, and known child coverage still visible.

## ADR / telemetry / review

No ADR: this standardizes goal acceptance criteria and dashboard presentation,
not product architecture. No runtime telemetry change: the dashboard remains
read-only. Review focus is whether WGL criteria are distinct from child work
items and whether the dashboard refuses to infer target closure from child issue
completion alone.
