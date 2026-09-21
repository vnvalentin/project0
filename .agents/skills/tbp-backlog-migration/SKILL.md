---
name: tbp-backlog-migration
description: Migrate specified legacy Wayfinder GitHub issues into the TBP backlog taxonomy and markdown structure.
disable-model-invocation: true
---

# TBP Backlog Migration

Migrate only the issues the user names. This is a user-invoked, mutation-capable workflow: classify each issue, rewrite its body into the appropriate TBP shape, audit missing fields, and verify the result.

The canonical hierarchy is [.github/tbp-wayfinder.md](../../../.github/tbp-wayfinder.md). The three-phase source protocol is [.github/tbp-migrate.md](../../../.github/tbp-migrate.md). This skill is the callable execution workflow; those files remain reference documents.

## Guardrails

- Use `gh` for every GitHub operation. Do not use browser scraping or direct API guesses.
- Read each issue's title, body, labels, state, comments, and parent/child links before changing it.
- Never migrate an issue outside the user's target scope.
- Preserve existing links, issue numbers, code spans, and materially relevant wording. Convert preserved child/parent links into task-list items where the template calls for them.
- Apply exactly one primary TBP taxonomy label per issue. Keep unrelated labels unless the user explicitly asks for label cleanup.
- Add `tbp:needs-refinement` whenever any mandatory field receives a gap marker.
- Do not close, reopen, reparent, or alter assignees/milestones unless the user explicitly requests it.
- Before a bulk migration, show the planned issue-to-taxonomy mapping and ask for confirmation. A single explicitly named issue may proceed after showing its mapping.
- Never overwrite a body until its replacement has been reviewed against the original and all links have been accounted for.
- Do not claim completion until every changed issue has been re-read from GitHub and verified.

## Invocation

Use `/tbp-backlog-migration` followed by a target scope, for example:

- `/tbp-backlog-migration #101 #102 #103`
- `/tbp-backlog-migration issues labeled legacy-wayfinder`
- `/tbp-backlog-migration the open issues in the Wayfinder map`

If the scope is ambiguous, ask for explicit issue numbers or a precise query before mutating anything.

## Workflow

### 1. Resolve the target scope

Turn the user's scope into a fixed issue list. For a label/query scope, run the query once and record the resulting issue numbers. Exclude pull requests unless the user explicitly includes them.

For every target, collect:

- issue number, title, state, author, labels, assignee, milestone;
- complete body and comments;
- all issue links, parent/child references, and checklist items;
- existing TBP labels and any prior migration notes.

### 2. Classify the taxonomy

Choose the one level that best describes the issue's scope:

| Issue shape | Primary label |
| --- | --- |
| Broad project or map | `tbp:hoshin` |
| Major initiative or problem space | `tbp:theme` |
| Gap analysis or measurable deliverable | `tbp:feature` |
| Specific root cause or task group | `tbp:epic` |
| Atomic coding task or execution slice | `tbp:experiment` |

Classification is about the issue's work shape, not its current status. Record one sentence of reasoning for each issue. If two levels seem equally plausible, stop and ask instead of applying both.

Apply the label with:

```sh
gh issue edit <number> --add-label "<primary-label>"
```

If the label does not exist, stop and report the missing repository label. Do not silently substitute a different label.

### 3. Rewrite the body

Use the template matching the selected taxonomy. Keep the issue's original links in the relevant `Related issues`, `Parent`, `Children`, or checklist section. Do not invent facts; use the gap marker when evidence is missing.

#### `tbp:hoshin` template

```markdown
# <title>

## Aspirational Goal

<the broad project or map outcome>

## What Good Looks Like

- [ ] <observable outcome>
- [ ] <preserved child or decision link>

## Current Condition

<what the legacy issue says today>

## Decisions and Links

- <preserved parent/child/related link>

## TBP Gap Audit

<mandatory fields that remain unknown, or `Complete`>
```

Mandatory fields: aspirational goal, measurable What Good Looks Like outcomes, current condition, and parent/child structure.

#### `tbp:theme` template

```markdown
# <title>

## Problem Statement

<the major problem this theme solves>

## Measurable Outcome

<how completion is measured>

## Features

- [ ] <preserved child issue link>

## TBP Gap Audit

<mandatory fields that remain unknown, or `Complete`>
```

Mandatory fields: problem statement, measurable outcome, and child Feature links.

#### `tbp:feature` template

```markdown
# <title>

## Ideal Condition

<target capability>

## Current Condition

<verified current capability>

## Measurable Component

<the metric that confirms the Feature is complete>

## Epics (Gaps)

- [ ] <preserved child issue link>

## TBP Gap Audit

<mandatory fields that remain unknown, or `Complete`>
```

Mandatory fields: ideal/current condition, measurable component, and child Epic links.

#### `tbp:epic` template

```markdown
# <title>

## The 4Ws

- **Who:** <actor or owner>
- **When:** <time or triggering condition>
- **Where:** <system or boundary>
- **What:** <specific root cause or bounded work>

## Root Cause

<the underlying reason for the gap>

## Measurable Metric

<the data point that determines whether the root cause is resolved>

## Experiments

- [ ] <preserved child issue link>

## TBP Gap Audit

<mandatory fields that remain unknown, or `Complete`>
```

Mandatory fields: all 4Ws, root cause, measurable metric, and child Experiment links.

#### `tbp:experiment` template

```markdown
# <title>

## Test Definition

<the solution being tested against the root cause>

## Status

- [ ] Pass
- [ ] Fail

## Learning Outputs

<evidence captured from execution>

## Next Action

<if Pass, inspect the parent Epic metric; if Fail, adjust the experiment>

## Related Work

- [ ] <preserved parent/child/related issue link>

## TBP Gap Audit

<mandatory fields that remain unknown, or `Complete`>
```

Mandatory fields: test definition, status, learning outputs, next action, and related work.

### 4. Run the gap audit

For every mandatory field that cannot be safely inferred from the original issue, insert this exact block immediately under that heading:

```markdown
> **[TBP GAP: Needs Definition]**
```

Then apply:

```sh
gh issue edit <number> --add-label "tbp:needs-refinement"
```

If no gap markers remain, do not add `tbp:needs-refinement`. Never remove an existing refinement label without explicit authorization.

### 5. Apply and verify

For each approved issue:

1. Add the primary taxonomy label.
2. Add `tbp:needs-refinement` if required.
3. Replace the body with the reviewed template using a temporary UTF-8 file:

   ```sh
   gh issue edit <number> --body-file <temporary-file>
   ```

4. Re-read the issue:

   ```sh
   gh issue view <number> --json number,title,state,labels,body,comments
   ```

5. Verify the primary label, required gap label state, every preserved link, every checklist item, and every mandatory section.

### Completion report

Report:

- migrated issue numbers and titles;
- taxonomy label and one-line classification reason for each;
- issues marked `tbp:needs-refinement` and the missing fields;
- preserved parent/child/related links;
- verification command and result;
- any issue skipped or blocked, with the exact reason.
