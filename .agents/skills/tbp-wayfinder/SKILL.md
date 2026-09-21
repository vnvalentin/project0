```markdown
---
name: tbp-wayfinder
description: Plan project work through the five-level TBP GitHub backlog hierarchy using a strict Breadth-First Layered Grilling protocol.
disable-model-invocation: true
---

# TBP Wayfinder

Use this skill when the user asks to plan or map work through the TBP backlog. The canonical hierarchy is [.github/tbp-wayfinder.md](../../../.github/tbp-wayfinder.md). Use GitHub Issues as the backlog and `gh` for every GitHub operation. 

Act as a strict quality gatekeeper. Work breadth-first: finish and export one horizontal layer before moving to a lower layer. This keeps the fog of war clear and prevents premature backlog expansion.

## Guardrails

- **Pacing:** Ask a maximum of 2 questions per turn. Do not overwhelm the user.
- **State Tracking:** Start every response with `📍 Current Focus: [Phase Name] > [Active Item]`.
- **Strict Phase Discipline:** Move to a lower level only after the current horizontal layer is completely grilled, summarized, exported to GitHub, and verified.
- Work only on the scope the user names. If the scope is ambiguous, ask for a destination or existing Hoshin before changing GitHub.
- Read existing parent and child issues before creating or rewriting anything.
- Use the existing TBP labels: `tbp:hoshin`, `tbp:theme`, `tbp:feature`, `tbp:epic`, and `tbp:experiment`.
- If a required label is missing, stop and report it; do not substitute a generic label.
- Create one issue per backlog level item. Preserve parent/child links both as markdown task lists and as native GitHub parent/sub-issue relationships.
- Every child issue body must include the textual parent marker for its level (`Parent vision: #N`, `Parent theme: #N`, `Parent feature: #N`, or `Parent epic: #N`) and must also be related with `gh issue edit <child> --parent <parent>`.
- Do not invent measurable outcomes, owners, dates, or root causes. Mark unknown mandatory fields with the exact gap marker and add `tbp:needs-refinement`.
- Do not close, reopen, reparent, or alter existing issues unless the user explicitly requests it.
- Re-read every created or changed issue and verify labels, textual parent markers, native GitHub parent links, child links, required sections, and gap labels before claiming completion.
- When a requested action conflicts with a guardrail, explain the specific constraint, offer the compliant alternative, and wait for confirmation before proceeding.
- Before any GitHub mutation, show the planned issue list, taxonomy, parent links, and unresolved gaps. For one explicitly named issue, show its plan and request confirmation; for a bulk scope, request confirmation for the complete plan.

## Invocation

Use `/tbp-wayfinder` followed by a planning destination, an existing Hoshin issue, or a precise scope. Examples:

- `/tbp-wayfinder create a Hoshin for the next playable milestone`
- `/tbp-wayfinder continue Hoshin #495`
- `/tbp-wayfinder map the backlog for persistent player housing`

## Five levels

### 1. Hoshin: North Star
Create one issue labeled `tbp:hoshin` containing:
```markdown
## Aspirational Goal

<ultimate outcome>

## Current Condition

<real-world condition and gap>

## What Good Looks Like

- [ ] <measurable top-level outcome>

## Themes

- [ ] <child Theme issue>

```

Mandatory fields: aspirational goal, current condition, measurable outcomes, and child Theme links.

### 2. Theme: Major Problem Space

A Theme solves one major problem preventing the Hoshin from being achieved. Create it under the Hoshin with `tbp:theme`:

```markdown
## Problem Statement

<the major problem>

## Measurable Outcome

<how completion is measured>

## Features

- [ ] <child Feature issue>

```

Mandatory fields: problem statement, measurable outcome, and child Feature links.

### 3. Feature: Capability Gap

A Feature names the gap between current and ideal conditions. Create it under a Theme with `tbp:feature`:

```markdown
## Ideal Condition

<what must be true>

## Current Condition

<what is true now and the gap>

## Measurable Component

<metric confirming completion>

## Epics (Gaps)

- [ ] <child Epic issue>

```

Mandatory fields: ideal condition, current condition, measurable component, and child Epic links.

### 4. Epic: Root Cause and 4Ws

An Epic captures the specific root cause or bounded task group. Create it under a Feature with `tbp:epic`:

```markdown
## The 4Ws

- **Who:** <actor or owner>
- **When:** <time or triggering condition>
- **Where:** <system or boundary>
- **What:** <specific root cause or bounded work>

## Root Cause

<underlying reason for the gap>

## Measurable Metric

<data point proving the root cause is resolved>

## Experiments

- [ ] <child Experiment issue>

```

Mandatory fields: all four Ws, root cause, measurable metric, and child Experiment links.

### 5. Experiment: Execution and Learning

An Experiment tests a solution for an Epic. Create it under an Epic with `tbp:experiment`:

```markdown
## Test Definition

<solution being tested>

## Status

- [ ] Pass
- [ ] Fail

## Learning Outputs

<evidence captured from execution>

## Next Action

<If Pass: inspect the parent Epic's measurable metric. If Fail: adjust the experiment and retry.>

```

Mandatory fields: test definition, status, learning outputs, and next action.

## The Breadth-First Grilling Workflow

You operate in one of four distinct phases depending on the user's prompt.

### Phase 1: Hoshin & Theme Discovery

1. **Goal:** Define the Hoshin and identify all top-level Themes.
2. **Grilling:** Interrogate the user to scope the Aspirational Goal, Current Condition, and Acceptance Criteria. Identify all Themes blocking the Hoshin.
3. **Execution:** After confirmation, create the Hoshin and Theme issues with `gh`, add `Parent vision: #<hoshin>` to each Theme, set each Theme's native parent with `gh issue edit <theme> --parent <hoshin>`, link Themes to the Hoshin body, re-read every changed issue, and verify labels, sections, textual parent markers, native parent links, child links, and gap markers.
4. **Transition:** Stop and explicitly ask: *"Which Theme should we grill first?"*
5. **Completion criterion:** The Hoshin and all Themes in the approved layer exist, have the correct labels and required sections, and their textual and native parent/child links have been verified.

### Phase 2: Theme Breakdown

1. **Goal:** Break a specific Theme down into Features.
2. **Grilling:** For each proposed Feature, grill the user on the Ideal Condition vs. the Current Condition (the gap) and the Measurable Component.
3. **Execution:** After confirmation, create the Feature issues via `gh`, add `Parent theme: #<theme>` to each Feature, set each Feature's native parent with `gh issue edit <feature> --parent <theme>`, link them to the parent Theme body, re-read every changed issue, and verify labels, sections, textual parent markers, native parent links, child links, and gap markers.
4. **Transition:** Stop and explicitly ask: *"Should we grill another Theme, or drill down into one of these new Features?"*
5. **Completion criterion:** Every approved Feature exists under the selected Theme with a verified label, required sections, measurable component, textual parent marker, native parent link, and parent-body child link.

### Phase 3: Feature Gap Analysis

1. **Goal:** Break a Feature down into Epics (Root Causes).
2. **Grilling:** Force the user to define the 4Ws (Who, When, Where, What) for the Feature gap. Use the 4Ws to isolate the specific Root Causes (Epics). Ensure each Epic has a measurable metric.
3. **Execution:** After confirmation, create the Epic issues via `gh`, add `Parent feature: #<feature>` to each Epic, set each Epic's native parent with `gh issue edit <epic> --parent <feature>`, link them to the parent Feature body, re-read every changed issue, and verify labels, sections, textual parent markers, native parent links, child links, 4Ws, metrics, and gap markers.
4. **Transition:** Stop and explicitly ask: *"Should we grill another Feature, or drill down into one of these new Epics?"*
5. **Completion criterion:** Every approved Epic has verified 4Ws, root cause, measurable metric, child links, textual parent marker, native parent link, and the correct parent Feature body link.

### Phase 4: Epic Execution

1. **Goal:** Break an Epic down into Experiments.
2. **Grilling:** Ask how to test the solution for the Root Cause to achieve the shortest time to learning. Define pass/fail criteria and learning outputs.
3. **Execution:** After confirmation, create the Experiment issues via `gh`, add `Parent epic: #<epic>` to each Experiment, set each Experiment's native parent with `gh issue edit <experiment> --parent <epic>`, link them to the parent Epic body, re-read every changed issue, and verify labels, sections, textual parent markers, native parent links, child links, status, learning outputs, and gap markers.
4. **Completion criterion:** Every approved Experiment has a verified test definition, pass/fail status, learning outputs, next action, textual parent marker, native parent link, and parent Epic body link.

### Continue an existing map

1. Read the parent body and identify its current condition and unresolved child items.
2. Query child issues and determine the first unblocked frontier item.
3. Pick up the Grilling Workflow at the appropriate Phase. Never create a lower level until its parent capability and measurable outcome are clear.

## Gap audit

When a mandatory field cannot be safely inferred, insert this exact marker beneath that heading:

```markdown
> **[TBP GAP: Needs Definition]**

```

Then add the label:

```sh
gh issue edit <number> --add-label "tbp:needs-refinement"

```

Do not add the refinement label when no gap marker exists. Never remove an existing refinement label without explicit authorization.

## GitHub operations

Use commands shaped like:

```sh
gh issue list --state open --label "tbp:theme"
gh issue view <number> --json number,title,state,labels,body,comments
gh issue create --title "<title>" --label "tbp:feature" --body-file <file>
gh issue edit <child-number> --parent <parent-number>
gh issue edit <number> --body-file <file>
gh issue edit <number> --add-label "tbp:needs-refinement"

```

Use temporary UTF-8 body files for multiline issue content. After setting a native parent, verify it with `gh issue view <child-number> --json parent -q '.parent.number'`. Never put secrets in issue bodies or command output.

## Completion report

Report:

* the specific layer created or updated;
* each issue number, title, level, parent, and label;
* blockers and unresolved gap markers;
* preserved or newly added child links;
* verification commands and results;
* issues skipped because of ambiguity, duplication, or missing decisions.

```

```