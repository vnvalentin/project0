# TBP Wayfinder Skill

When planning work or mapping a project, you must strictly follow the Toyota Business Practice (TBP) backlog hierarchy. Never use generic "tasks" or "tickets." Work must be structured across 5 levels in GitHub Issues.

## GitHub parent relationships

Every child issue must be linked two ways:

- Add the textual parent marker to the child body: `Parent vision: #N`, `Parent theme: #N`, `Parent feature: #N`, or `Parent epic: #N`.
- Set the native GitHub parent relationship with `gh issue edit <child-number> --parent <parent-number>`.

Parent issues must also keep the markdown task list of child links. Verify native parent links with `gh issue view <child-number> --json parent -q '.parent.number'` before reporting completion.

## Level 1: Hoshin (The North Star)
The Hoshin is the overarching map. You must create one GitHub Issue labeled `tbp:hoshin` containing:
- **Aspirational Goal:** The ultimate outcome.
- **Current Condition:** The real-world situation we are trying to solve.
- **What Good Looks Like (Acceptance Criteria):** Measurable top-level outcomes.
- **Themes:** A markdown task list `- [ ]` linking to child Theme issues.

## Level 2: Theme
Themes solve one massive problem preventing the Hoshin from being achieved. Create an issue labeled `tbp:theme` containing:
- `Parent vision: #<hoshin>`
- **Problem Statement:** The big problem this theme solves.
- **Measurable Outcome:** How we define this theme as complete.
- **Features:** A markdown task list `- [ ]` linking to child Feature issues.

## Level 3: Feature
Features identify the gap. Create an issue labeled `tbp:feature` containing:
- `Parent theme: #<theme>`
- **Ideal Condition:** What must be true to accomplish part of the Theme.
- **Current Condition:** The reality, highlighting the gap.
- **Measurable Component:** The metric that confirms the feature is complete.
- **Epics (Gaps):** A markdown task list `- [ ]` linking to child Epic issues.

## Level 4: Epic (Root Cause & 4Ws)
Epics capture the specific gaps and root causes. Create an issue labeled `tbp:epic` containing:
- `Parent feature: #<feature>`
- **The 4Ws:** Who, When, Where, and What (identifying the exact points of occurrence).
- **Root Cause:** The underlying reason for the gap.
- **Measurable Metric:** The data point to determine if the root cause is resolved.
- **Experiments:** A markdown task list `- [ ]` linking to child Experiment issues.

## Level 5: Experiment (Execution & Learning)
Experiments test the solution for the root cause. This level is optimized for the shortest time to learning. Create an issue labeled `tbp:experiment` containing:
- `Parent epic: #<epic>`
- **Test Definition:** The solution being tested against the root cause.
- **Status:** [ ] Pass / [ ] Fail
- **Learning Outputs:** Evidence captured from the execution.
- **Next Action:** If Pass -> Inspect the parent Epic's measurable metric. If Fail -> Adjust the experiment and try again.