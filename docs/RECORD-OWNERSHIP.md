# Record Ownership Rule
Status: **accepted**. GitHub is the single active source of truth.

## 2026-09-23: All active delivery moved to GitHub
`FEATURE-LIST.md` and `docs/slices/*.md` (including `SLICE-REGISTRY.md`) are now a
**frozen historical archive** — the record of everything delivered before this
date. Do not add new entries to them. Going forward:

- A **Feature** is a GitHub issue labeled `Feature`, with a `Parent goal: #N`
  line in its body when it advances a Goal issue.
- A **Slice** is a GitHub issue labeled `Slice`, with a `Parent feature: #N`
  line in its body when it advances a Feature issue.
- `docs/PROJECT-TRACKER.md`, `docs/TECHNICAL-DEBT-TRACKER.md`, and the other
   Markdown records are frozen historical or explanatory archives.
- GitHub Project `Project0 Delivery` (#2) owns the visible operational fields:
   Outcome, Phase, Milestone, Status, Evidence, Blocked, owner, and parent.

See [Vision, Goal, Feature, and Slice semantics](DEVELOPMENT-WORKFLOW.md#vision-goal-feature-and-slice-semantics-2026-09-20)
for what a Feature and a Slice issue must each state (the gap they close and
the root cause they resolve) before creating one.

## Why this exists

The former file records drifted whenever work and status were changed in
different places. Keeping a live tracker beside GitHub made the source of truth
ambiguous. Issue bodies, native issue state, labels, parent links, Project
fields, milestones, and linked evidence are canonical; repository Markdown is
context only.

## Rules

1. **Issue first.** Create or identify the governing GitHub issue before code.
   Put the current condition, target outcome, exit criteria, non-goals,
   evidence, and parent link in the issue body.
2. **Project visible.** Add active issues to Project #2 and populate Outcome,
   Phase, Status, Evidence, Blocked, owner, and Parent. Assign a Milestone only
   for committed delivery work.
3. **Link parent before you create.** When opening a new Slice issue, add
   `Parent feature: #N` in its body; when opening a new Feature issue, add
   `Parent goal: #N` in its body. Never renumber or relabel a shipped issue's
   identity — status lives in the issue's state/labels, not a renamed title.
5. **Validate the active system.** Run focused tests and the full validation
   suite. `scripts/check_record_sync.sh` checks historical links and issue
   traceability; it does not require tracker status parity.

## One-line summary

GitHub Issues and Project #2 are the single active delivery system. Milestones
state when a committed outcome is due; Outcome and Phase state why and in what
dependency order; parent links state hierarchy; Evidence and linked PRs prove
completion. Repository records remain frozen context and are never a second
status system.
