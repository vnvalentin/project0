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
- **4W Partition:** Use Who, When, Where, and What to separate the Feature into
	distinct problem occurrences or seams. A changed actor, process point,
	boundary, or problem can justify a separate Epic; the 4Ws are decomposition
	criteria, not a form copied into every Epic.
- **Root-Cause Ordering:** Identify the Feature-level root cause or dependency
	that determines which resulting Epic should start first. This sequences child
	Epics rather than becoming a duplicate field on each one.

## Level 4: Epic (Bounded Problem Seam)
An Epic captures one problem seam produced by the Feature's 4W partition. Create
an issue labeled `tbp:epic` containing:
- `Parent feature: #<feature>`
- **Problem Seam:** The bounded occurrence or problem this Epic owns, including
	enough context to distinguish it from sibling Epics.
- **Measurable Metric:** The data point to determine if the root cause is resolved.
- **Experiments:** A markdown task list `- [ ]` linking to child Experiment issues.

An Epic may reference the relevant Feature-level 4W cluster or local cause when
useful, but it does not need to repeat all four Ws or restate the Feature's
sequencing root cause.

Epic decomposition is a working hypothesis. After an Experiment produces
evidence, revisit the Feature: one solution may collapse several Epics, change
the ordering or root cause, leave siblings unchanged, or reveal a new seam.
Update the child Epic set to match the evidence.

## Level 5: Experiment (Execution & Learning)
Experiments test the solution for the root cause. This level is optimized for the shortest time to learning. Create an issue labeled `tbp:experiment` containing:
- `Parent epic: #<epic>`
- **Test Definition:** The solution being tested against the root cause.
- **Status:** [ ] Pass / [ ] Fail
- **Learning Outputs:** Evidence captured from the execution.
- **Next Action:** If Pass -> Inspect the parent Epic's measurable metric. If Fail -> Adjust the experiment and try again.