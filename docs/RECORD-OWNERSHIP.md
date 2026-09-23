# Record Ownership Rule

Status: **accepted**. GitHub Issues and the Project board are the active
delivery authority. The committed Markdown records below are historical or
explanatory archives.

## 2026-09-20: Features and Slices moved to GitHub issues

`FEATURE-LIST.md` and `docs/slices/*.md` (including `SLICE-REGISTRY.md`) are now a
**frozen historical archive** — the record of everything delivered before this
date. Do not add new entries to them. Going forward:

- A **Feature** is a GitHub issue labeled `Feature`, with a `Parent goal: #N`
  line in its body when it advances a Goal issue.
- A **Slice** is a GitHub issue labeled `Slice`, with a `Parent feature: #N`
  line in its body when it advances a Feature issue.
- Active Features, Slices, Themes, Epics, Experiments, and Debt are GitHub
   issues. Their native parent, labels, issue state, Outcome field, Phase
   field, Milestone, evidence, and exit criteria are the active record.
- `docs/PROJECT-TRACKER.md`, `docs/TECHNICAL-DEBT-TRACKER.md`,
   `docs/FEATURE-LIST.md`, and `docs/slices/` are committed historical or
   explanatory archives. Do not create new active planning records in them.
- `dashboard/tracker_schema.json` and the dashboard are projections during
   migration; they must not become a second authority for active work.

See [Vision, Goal, Feature, and Slice semantics](DEVELOPMENT-WORKFLOW.md#vision-goal-feature-and-slice-semantics-2026-09-20)
for what a Feature and a Slice issue must each state (the gap they close and
the root cause they resolve) before creating one.

## Why this exists

The old delivery records drifted because active planning state was split across
files, issue metadata, and dashboard projections. GitHub now holds one active
record per work item, while the Project board makes missing fields and
unscheduled work visible. The Markdown records remain useful for historical
context and parity checks, but they are not edited to plan new work.

## Rules

1. **Create the issue first.** Every active work item has a GitHub issue before
   implementation. Set its native parent, issue type/label, Outcome, Phase,
   Milestone (when scheduled), evidence, and exit criteria.
2. **Make scheduling explicit.** An issue without a Milestone is unscheduled;
   do not infer commitment from its parent, label, or Phase.
3. **Keep the fields distinct.** Outcome is the product result, Phase is the
   dependency/order, and Milestone is the delivery commitment.
4. **Link evidence at the public seam.** Pull requests, validation commands,
   artifacts, and review outcomes belong on the issue before closure.
5. **Keep archives stable.** Do not add active planning entries to the frozen
   Markdown records. Update them only when a migration or parity check
   explicitly requires it.
6. **The Project board exposes truth.** Views must make parent, Outcome,
   Phase, Milestone, status, blocked state, and missing evidence visible.

## One-line summary

All active delivery truth lives in GitHub Issues and the Project board. The
Markdown records remain frozen context, and code changes are complete only when
their issue contains the parent, Outcome, Phase, Milestone decision, public
evidence, and exit result.
