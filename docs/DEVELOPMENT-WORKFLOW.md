# Slice Development Workflow

This workflow operationalizes the [Engineering Constitution](ENGINEERING-CONSTITUTION.md).
It is mandatory for implementation issues and creates the evidence trail from
customer need to validated product behavior.

## Delivery process: request to usable functionality

The delivery process is **request -> agreed outcome -> small tested change ->
integrated application -> evidence that it works**. This overview summarizes
the required gates below; it does not claim that past deliveries satisfied them.
Documentation of this overview is tracked in
[issue #1254](https://github.com/vnvalentin/project0/issues/1254); the current
milestone alignment is tracked in
[issue #1257](https://github.com/vnvalentin/project0/issues/1257).

```text
User requests a change
   |
   v
Clarify the player outcome, current gap, constraints and measurable success
   |
   v
User confirms scope <---------------- Revise if not confirmed
   |
   v
Record or update the GitHub issue and Project #2
Locate the committed milestone and named slice group
Link the bounded work issue, or record why it is cross-cutting/uncommitted
   |
   v
Inspect actual behavior; investigate or experiment where uncertainty remains
   |
   v
Define behavior scenarios, design boundaries, acceptance tests and rollback
   |
   v
Check foundation prerequisites and platform; create a change branch
   |
   v
Write a failing behavior test -> implement the smallest change -> rerun
   |
   v
Validate focused behavior, integration, full suite and delivery records
   |
   v
Review code and evidence -> push PR -> merge only when gates pass
   |
   v
Make the change available in the intended development application
Deploy the server or replace the client as needed within authorized scope
   |
   v
Exercise the real player journey; capture runtime evidence
Obtain user acceptance where the agreed outcome requires human judgment
   |
   v
Close the work issue with proof; synchronize Project; retain learning
   |
   v
Delivered increment -> verify slice acceptance -> verify milestone outcome

At ANY stage: a new problem is discovered
   -> Capture a linked issue and make it visible in Project #2
   -> Classify against the current goal and mandatory safety/validation gates
   -> Blocking: STOP affected work; apply Jidoka; close with evidence
       OR remain explicitly blocked with the next owner and action recorded
   -> Non-blocking: record as deferred follow-up; return to the original goal
```

### Goal-first execution and discovery handling

This rule applies to every task, as approved in
[#1261](https://github.com/vnvalentin/project0/issues/1261).

1. **Anchor the task.** Before starting, name its governing GitHub issue,
   specific goal, acceptance criteria, and explicit non-goals. Clarify missing
   or conflicting goals before implementation. The issue defines completion;
   incidental discoveries do not silently expand it.
2. **Capture first.** Create or update a GitHub issue for each newly discovered
   problem before pursuing it. Link it to the governing issue, record the
   symptom, affected public seam and available evidence, and make it visible in
   Project #2 with an owner and next action. Immediate factual discovery capture
   is authorized without another proposal-approval cycle; it does not authorize
   scope expansion. Mark an unknown root cause as unknown. Reuse an existing
   issue for the same problem rather than creating duplicates.
3. **Classify against the goal.** A problem is blocking when it prevents the
   governing issue's acceptance criteria or a mandatory safety or validation
   gate from being satisfied. Record the classification and why. If uncertain,
   perform only the smallest discriminating check needed to decide. Stop the
   affected path immediately when safety is unclear; capture never delays
   necessary containment. A failed required gate cannot be deferred merely
   because its cause predates the task.
4. **Blocking: apply Jidoka.** Stop the affected delivery path, establish the
   root cause from evidence, and apply a focused countermeasure within
   authorized boundaries. Record hypotheses, the discriminating check,
   acceptance criteria and rollback boundary in the problem issue. Create or
   update its Technical Debt record with root cause, impact, remediation,
   validation evidence and remaining limitations; the same issue may serve both
   roles. Pass the focused check and required regression gates, then close the
   blocker with evidence before resuming the original goal. If authority,
   access or evidence is insufficient, leave it explicitly blocked with the
   unresolved hypotheses, required decision, next owner and action. Never bypass
   it or claim the goal complete.
5. **Non-blocking: record and return.** Make the issue visible as deferred
   follow-up, record why it does not block the goal, and immediately return to
   the original task. Further diagnosis or repair requires separately authorized
   work. An unrelated open issue neither expands the current acceptance criteria
   nor prevents completion when the original criteria and required gates pass.
6. **Close the original goal.** Complete the task only with its own acceptance
   evidence, required delivery gates, and synchronized issue/Project status.
   Report linked deferred discoveries without making their closure an additional
   requirement. Preserve the existing safety, platform and validation boundaries.

### Responsibilities and boundaries

- The user defines the desired experience, confirms scope and meaningful
   tradeoffs, and provides acceptance where human judgment matters, such as
   whether movement feels responsive. Clarification is paced at no more than
   two questions per turn; required fields and confirmation precede proposed
   scope changes. Factual discovery capture follows the rule above immediately.
- Copilot owns investigation, implementation, tests, review, and delivery
   records within the authorized scope. Code or a deployment step is not
   authority to expand that scope. Blocked authorization or access is recorded,
   not silently bypassed.
- GitHub Issues and Project #2 own active delivery state and evidence. Local
   planning notes do not replace the governing issue, and frozen Markdown
   trackers must not become a second active status system.
- Windows-required changes are labeled, implemented and validated on Windows.
   Server-side, container and Linux-only work executes on `192.168.1.254` through
   SSH. Client-only validation cannot prove authoritative server behavior.
- Every discovery follows goal-first classification above. Blocking failures
   follow the Jidoka and root-cause learning gates; non-blocking discoveries
   remain visible deferred work. A post-merge fix follows a new branch and PR
   cycle; it does not bypass review or validation.

### What counts as delivered

| State | Meaning |
| --- | --- |
| Code written | A candidate solution exists. |
| Tests pass | The checked behaviors work under test conditions. |
| PR merged | The change is integrated into the repository. |
| Available in the app | The intended runtime contains the change. |
| Delivered | The agreed user outcome is demonstrated, evidence and review are recorded, Project is synchronized, and the governing issue is closed. |

For example, "fix movement sticking at sector boundaries" is not complete
because a movement test passes. Run the updated Windows client against the
authoritative development server, cross the relevant boundary, and demonstrate
the agreed behavior. Record the commands, results, artifacts and required user
acceptance. Unit tests or startup success alone cannot prove the player journey.

For documentation-only work, the observable outcome is the documented contract
and its checks, not a fictitious application deployment. Record which runtime
steps are inapplicable and why; the applicable traceability, review and merge
gates still apply.

Deliver one small, useful increment, then reassess what remains. Closing an issue
does not automatically complete its slice group or milestone. Missing
acceptance evidence means **awaiting evidence**; an unresolved blocker means
**blocked**, never delivered. Retain proven reusable practices in the Library
and identified problems with confirmed root causes in the Memorial; unresolved
liabilities remain active Technical Debt issues.

## Milestones, slice groups, and linked issues

The active delivery structure is **Milestone -> named slice groups -> linked
GitHub issues**, as approved in [#1217](https://github.com/vnvalentin/project0/issues/1217).
Phases are retired. Existing Phase fields or historical text are legacy metadata:
do not populate them or use them to sequence, approve, or complete current work.

```text
Milestone: committed, observable player/system outcome
   +-- Named slice group: bounded part of that outcome
   |     +-- Included GitHub issue: work, acceptance evidence, and resolution
   |     +-- Included GitHub issue: investigation or implementation
   |     +-- Linked Technical Debt: liability, owner, and remediation evidence
   +-- Another named slice group with its own acceptance and dependencies

Vision / Goals / Features: strategic purpose and retained parent links
Project #2: operational status, ownership, evidence, and blockers
```

### Milestone and slice contracts

A **milestone** commits an outcome, not a status or a batch of code. Its title
uses `Milestone N: Outcome`; its stable GitHub number/URL is distinct from that
display number. Preserve existing IDs, history and paused commitments. Renaming
or completing another milestone never authorizes paused work.

A **slice group** is a named, independently observable part of that milestone.
The milestone description's `## Slice Mapping` owns the grouping. Each group
states `Outcome:`, `Included issues:`, `Complete when:`, and `Dependency:` under
a `### Slice M<N>.<n>: Name` heading. Keep issue milestone assignment and this
mapping consistent. Shared context belongs in references, not duplicate work.

Milestone descriptions have no `## Shared Context` section (user rule,
[#1400](https://github.com/vnvalentin/project0/issues/1400)). An issue assigned
to the milestone that relates to several slices is listed once, under
`Included issues:` of the first slice it relates to. Context from outside the
milestone, such as a Vision, Theme or roadmap decision, is cited on the first
slice it relates to in a `Context:` line; that is a reference, not membership.

An **issue** owns a bounded problem or work item, its acceptance criteria,
evidence, owner, blockers and resolution. Reuse suitable existing issues; a
slice group does not require a new wrapper issue or a particular issue label.
An issue labeled `Slice` is still an issue, not automatically the milestone's
slice-group record. Preserve applicable native parent/child relationships and
body links; those relationships do not replace milestone membership or mapping.

Before implementation, name the outcome, committed milestone, slice group,
governing issue, applicable parent links, hypothesis, public seam, non-goals,
rollback and exact checks. Cross-cutting governance or uncommitted work may
have no milestone/slice: record that reason instead of inventing a commitment.
Choose the smallest observable, reversible implementation increment within the
owning issue. A group containing several issues is not one large coding batch.

Each milestone outcome includes a `## Player Example`: starting situation,
player action, visible experience and lasting result. Keep measurable technical
acceptance separate. Completion requires the named slice outcomes and milestone
acceptance evidence, not a count of closed issues or a successful merge.

For example, GitHub milestone **14** is displayed as **Milestone 0: Solo Playable
Foundation**. Its **M0.2 Movement and Traversal** group includes **#1213**. Closing
the movement defect does not prove the repeatable traversal route or the user's
responsiveness acceptance. The mapping, issue evidence and milestone acceptance
must agree before that outcome is complete.

### Technical Debt and blocking work

Technical Debt is an active GitHub liability, not another hierarchy level or a
Markdown tracker entry. Record classification, affected boundary, impact, owner,
symptom, evidence, confirmed root cause (or explicitly unresolved hypotheses),
remediation, regression check, remaining limitations and closure criteria.
Link the affected issues and slice groups. Assign a milestone and include the
debt in a slice only when its remediation is committed to that outcome; otherwise
retain it as explicitly uncommitted work with an owner and next action.

Blocking debt prevents acceptance of the affected issue, slice and milestone.
Nonblocking follow-up must have an explicit rationale. An exception requires a
recorded user decision naming its scope, risk and retained debt; it does not fix
or close that debt and does not waive future delivery gates. A green result in
another environment alone is not blocker resolution. Close debt only with its
own required remediation and validation evidence.

## Vision, Goal, Feature, and Slice semantics (2026-09-20)

These strategic and historical issue relationships explain why work matters;
they do not replace the milestone delivery structure above. Retain existing
identifiers and applicable parent links rather than relabeling old issues.

- The **Vision** is the single, permanent north star: the unchanging statement
  of what Project0 ultimately is (issue [#495](https://github.com/vnvalentin/project0/issues/495),
  mirrored in [.scratch/game-vision/map.md](../.scratch/game-vision/map.md)).
  It does not get rewritten to fit current work; work gets planned to close
  distance toward it.
- A **Goal** is a large, concrete, testable capability statement that is one
  focused slice of the Vision — for example "up to 10 players can occupy the
  same shared world at once." Not a task list, not an abstract principle, not
  a design document to produce: a capability someone could watch happen or
  fail to happen. Its `## What Good Looks Like` items (in the
  `.scratch/<goal>/map.md` and mirrored in the Goal issue body) are the
  itemized, individually Feature-trackable breakdown of that one capability.
- A **Feature** solves one specific problem that stands between today and a
  Goal's capability being true. A Feature issue must state both sides of that
  gap: the current condition (what is true today) and which capability it is
  closing distance toward (`Parent goal: #N`), **and which specific
  `## What Good Looks Like` item it advances**
  (`Advances: #<goal issue> item <n>`, where `<n>` is that item's 1-based
  position in the Goal's WGL list). A Feature with no `Advances:` line is not
  yet justified: if it doesn't close distance toward a named capability item,
  why does it exist? The Feature resolves only when measurable proof shows
  the stated gap is closed — code merging is not, by itself, resolution.
- Existing **Slice issues** record bounded implementation work. Keep their
   `Parent feature: #N` links when applicable and their root-cause and acceptance
   evidence. They can be included in a milestone's slice group alongside other
   issue types; creating one is not a mandatory intermediate step. A Feature
   closes only when evidence satisfies its own stated resolution proof.

Every milestone outcome record, including a Feature that serves as a milestone,
must include a `## Player Example` section. State one concrete scenario in
plain language: the player's starting situation, the action they take, what
they see or experience, and what lasting result they can rely on afterward.
This example explains why the milestone matters to the user; it complements,
but never replaces, the measurable outcome and technical acceptance evidence.

### Feature-to-Epic decomposition

Epics are not created by filling out the same 4W form repeatedly. The parent
Feature's 4W analysis is the partitioning tool: Who, When, Where, and What
identify distinct problem occurrences or seams that may need separate Epics.
The same Who can produce multiple Epics when that actor performs different
actions; a different When can expose another Epic at a separate point in the
process; and a changed boundary or problem can create another seam.

The Feature's root cause or dependency is also a sequencing input. It helps
determine which of the resulting Epics should start first, but it is not a
mandatory duplicate field on every Epic. Each Epic records its bounded problem
seam, a measurable metric, and its child Experiments; the parent Feature keeps
the 4W partition and root-cause ordering that explain why those Epics are
separate and why work begins in that order.

Epic decomposition is a working hypothesis, not a permanent checklist. After
an Experiment or Epic produces meaningful evidence, re-evaluate the parent
Feature: resolving one root cause may eliminate several sibling Epics, expose a
different root cause, move the first dependency, or reveal a new seam. The
opposite is also possible: an apparent solution may leave the other Epics
unchanged. Update the Feature's child links and ordering to match the evidence;
do not execute obsolete Epics merely because they were identified earlier.

A Goal's completion is **never** established by its open/closed state, a
hand-ticked WGL checkbox, or issue-count progress alone. Each capability item
needs linked evidence that the stated outcome holds. Required descendant work
must be resolved, but closing descendants does not replace outcome acceptance.

This applies to every Goal regardless of its current status, including
`chartering`, `research-first`, and `design gate` ones: a Goal without a stated
capability cannot yet spawn a Feature, because there is no gap to define.
Grilling and research on a Goal exist precisely to produce that capability
statement and its `## What Good Looks Like` breakdown; they are not exempt
from eventually stating one.

Every Goal must also trace to and advance the Vision. A Goal map or Goal issue
states `Parent vision: #495`; a Goal with no traceable line here is out of
scope until it is re-chartered or retired.

### Goal shape (2026-09-20)

Every Goal issue and every `.scratch/<goal>/map.md` must state all three of
these, in this order, before it can carry a `## What Good Looks Like` list or
spawn a Feature:

1. **Capability statement** — one sentence naming the concrete, observable
   thing players or the system can do when this Goal is met (e.g. "up to 10
   players can occupy the same shared world at once"). Not a design-document
   deliverable ("a handoff-ready spec exists"), not an abstract principle: a
   capability someone could watch hold true or fail. This replaces naming
   which abstract part of the Vision a Goal "targets" — the capability
   statement itself is the concrete slice of the Vision.
2. **Measurable outcome** — the test that decides completion, stated as four
   explicit fields:
   - **What**: the observable fact or artifact that must exist or hold true.
   - **How much**: the quantifiable threshold (a count, a percentage, a
     pass/fail on a fixture, a binary yes/no with no fuzziness).
   - **Who**: the actor or beneficiary the outcome is measured against (a
     playtester, the server, an operator, two Characters, etc.) — a Goal
     without a "who" is measuring nothing real.
   - **By when**: a bound — a committed milestone, a dependency, or an explicit "no fixed
     date, gated on evidence X" — never left implicit.
3. **What Good Looks Like** — the existing checklist, now understood as the
   itemized, individually Feature-trackable breakdown of the single capability
   statement and measurable outcome above, not a second, separate list of
   unrelated asks. Every WGL item must be traceable back to the Measurable
   outcome; an item that doesn't move that outcome doesn't belong on the list.

A Goal missing its Capability statement or Measurable outcome is
under-specified regardless of how many WGL boxes are checked — fix the frame
before trusting the percentage.

## Delivery lifecycle

Every capability moves through one lifecycle with a single authoritative status
at each stage. Active status lives on the governing GitHub issue and its item in
GitHub Project #2 (`Project0 Delivery`). The Markdown records and dashboard
archive route are historical context only; they never mirror or override live
delivery state.

### Stages

1. **Vetting** - clarify the current gap, target outcome, scope and acceptance.
   Confirm required fields with the user before creating or updating an issue.
   Research and architecture work resolve into evidence or decisions, not
   automatic Feature/Slice promotion. Local `.scratch` notes are optional aids.
2. **Ready** - the governing issue has an approved brief, applicable milestone
   and slice mapping, explicit dependencies and executable acceptance checks.
   Record readiness on the issue; Project Status remains `Todo` until work starts.
3. **Active** - Project Status is `In Progress`; the issue follows SDD, BDD, TDD
   and verification in small increments.
4. **Awaiting evidence / blocked** - implementation or checks are incomplete,
   contradictory or blocked. Keep the issue open, retain `In Progress` for
   started work, and use Evidence and Blocked fields plus the next owner/action
   to explain the hold. Code written is not Done.
5. **Done** - the issue's acceptance, applicable runtime evidence, review and
   merge gates are satisfied and synchronized; close it and mark Project Status
   `Done`. Re-evaluate the owning slice and milestone against their own criteria.

A **goal/map** is "complete" only when its own `## What Good Looks Like`
criteria are satisfied by evidence. Child issues are the known work and learning
questions under that goal; they do not, by themselves, define the goal's success
condition. Resolving every currently known child issue can still leave the goal
open when more fog must be cleared or new child issues must be created.

Every `.scratch/<goal>/map.md` must contain a `## What Good Looks Like` section
with customer-outcome acceptance criteria. Write criteria as checkboxes so the
dashboard can distinguish target-condition coverage from child-issue workflow
state. A goal folder with no `map.md` is a new, unresearched goal and has 0%
target coverage until the map and criteria are written.

### Stable identifiers

GitHub assigns new issue numbers. Preserve existing issue IDs, milestone IDs,
slice-group identifiers and parent links as status changes. Legacy `P-`/`IP-`/
`F-` prefixes and archived numbered slices are history, not allocation or status
authorities. Do not allocate new records in `FEATURE-LIST.md`, the Slice Registry
or other frozen trackers. The dashboard is a view of GitHub, not a second status
system.

## Process maps and material/information flow

The living MIFC and the three concurrent process maps are maintained in
[PROCESS-MAPS.md](PROCESS-MAPS.md). Every meaningful slice should be traceable
through the maps from customer trigger, to product behavior, to delivery
evidence and standardized learning. When a slice introduces a new queue,
failure state, handoff, or external boundary, update the relevant map before
calling the flow complete.

## 1. Intake and scope

Before approving a validation plan, follow [validation ownership](validation-ownership.md).
Record each selected test's owner, execution host, dependencies, expected artifacts,
and the successful machine-readable preflight on the issue. A missing dependency
is a setup defect only when the architecture assigns it to that runtime; otherwise
correct test placement or paired orchestration, not the product's dependencies.

Classify the request and identify the user outcome, affected systems and
boundaries, unacceptable outcomes, smallest useful change, and explicit
non-goals. Identify the governing GitHub Issue before work starts; create one
when no suitable issue exists. Local `.scratch/<goal>/issues/*.md` planning
tickets can refine design and decisions, but they are not a substitute for the
GitHub Issue. Check GitHub for an existing issue before creating a new one.
Record the milestone, slice group, governing issue and applicable parent links, and ask
Wayfinder or grilling questions when a product, ownership, or safety decision is
unclear. Ask only questions that affect implementation or safety.

## 2. SDD

Write a short slice design before coding when the change crosses a meaningful
boundary. State the goal, domain boundary, public seam, input/output contract,
invariants, failure behavior, persistence or integration effects, rollback plan,
and explicit non-goals. Link the governing issue, slice group and accepted ADRs.

## 3. BDD

Describe externally visible behavior as concrete scenarios:

```text
Given [context]
When [action]
Then [observable result]
```

Include the normal path, highest-risk edge case, and applicable safety,
authorization, idempotency, or recovery rule.

BDD scenarios are required for every slice, including documentation and
workflow capabilities when they have an observable seam.

## 4. TDD

Implement at the agreed public seam using red-green-refactor. Start with one
failing behavior test, add the smallest implementation, then add the next
behavior. Prefer fixture-backed tests and avoid private implementation details.

TDD is the default evidence path from the beginning. When no test framework is
available, use the narrowest executable public-seam check and record the gap as
technical debt rather than silently treating manual inspection as equivalent.

## 5. ADR

Create or update an ADR for an architectural, security, ownership, persistence,
integration, or irreversible boundary decision. Ordinary implementation details
do not require an ADR. Link the decision from the SDD and governing issue.

## 6. Verification and review

Run the focused test after each TDD cycle, then available type, lint, build,
integration, and full-suite checks. Inspect actual configuration, persisted state,
logs, and runtime behavior when the change crosses an integration or operational
boundary. Add telemetry for important inputs, state transitions, decisions,
failures, retries, rejections, and stop signals at the public seam. Stop on
unexpected failure or contradictory evidence. Review scope, safety,
specification compliance, observability, reversibility, and missing tests.

## 7. Root-cause learning gate

Every unexpected runtime failure, failed validation, user-reported defect, or
integration surprise MUST produce a durable learning record before the slice,
fix, or PR can be marked done. The record belongs in the affected slice's
`Root-cause learning` section on its governing issue and, when the liability
remains open, in a linked Technical Debt issue. A chat message, terminal log, or commit
message alone is not a sufficient record.

Each learning record MUST state:

- observed symptom and affected public seam;
- falsifiable hypothesis and the discriminating check;
- confirmed root cause, including why the existing tests did not catch it;
- countermeasure and its rollback boundary;
- regression test or executable validation added/run;
- remaining limitation, owner, and linked follow-up when the issue is not
   fully closed.

The review gate MUST reject completion when a fix has no root-cause record,
when the record describes only the symptom, or when a repeated failure mode
has not been converted into a regression check or an explicit accepted
limitation. This gate applies equally to application code, test code,
deployment, dashboard, and workflow changes.

The delivery validation itself is an observable contract. Every implementation
slice must have an executable focused validation command, an explicit expected
pass signal, and a machine-readable result artifact. For the current GUT unit
suite, run `scripts/run_gut_validation.sh`; it writes JUnit results to
`build/validation/gut.xml` and a status/exit-code/timestamp record to
`build/validation/validation-summary.json`. A slice using another boundary must
produce an equivalent result artifact rather than relying on prose or a manual
claim. A failed command or missing artifact is an Andon stop signal.

The repository CI gate in `.github/workflows/validation.yml` runs that same
command on every push and pull request. It uploads the validation directory
with `if: always()`, so failed runs retain their logs and telemetry for review.

## Branching and pull requests

`main` is always releasable and is never committed to directly. Every change —
a slice, a fix, or a docs/chore edit — is made on its own short-lived branch cut
from the latest `origin/main` and lands back on `main` only through a merged
pull request.

- **Branch per slice.** Before starting work, fetch and branch from the latest
   `origin/main`. Every slice gets its own `slice/<issue-number>-<topic>` branch
   and pull request. Fixes, docs, chores, and experiments likewise get their own
   `type/short-topic` branch. Keep one logical change per branch, consistent
   with small-lot delivery.
- **No direct commits to `main`.** All history reaches `main` through a pull
  request; never push commits straight to `main`.
- **Commit each completed edit.** After every completed logical edit, run the
   narrowest relevant validation and commit the resulting work before starting
   the next edit. Push each commit that is ready to share and update or create
   the pull request. Do not accumulate completed edits in an uncommitted
   worktree.
- **Green before merge.** A branch may merge only after its delivery gate is
  green: the focused validation, the full `scripts/run_gut_validation.sh` suite
  (exit 0 with its `build/validation/` artifacts), and
  `scripts/check_record_sync.sh` (exit 0) all pass; the required slice/delivery
  records are synchronized; and review is complete. CI runs the same suite on
  the pull request. A red gate is an Andon stop — fix it, do not merge.
- **Merge and clean up.** When the change is done and the gate is green, merge
  the pull request into `main` with a merge commit (`--no-ff`; no squash, no
  rebase) so each change lands as one reviewable merge, then delete the branch.
- **Who merges.** The agent completing the change merges the pull request as
  soon as the gate is green and does not wait for a separate manual approval.
  This is the repository's chosen automation setting and may be tightened to
  require human approval later.

## Required implementation issue record

Each implementation ticket links:

- Slice design (SDD), or an explicit no-SDD rationale.
- Behavior scenarios (BDD).
- Tests and public seam (TDD).
- Related ADR, or an explicit no-ADR rationale.
- Validation results and review outcome.
- Focused validation command, expected pass signal, and telemetry artifact path.
- Milestone and slice-group mapping (or a reason neither applies), applicable
   parent/debt links, duplicate-check result, governing issue and Project fields.
- GitHub Issue number or URL, plus the closing or reference keyword expected in
   the pull request (`Fixes #N`, `Closes #N`, `Resolves #N`, or `Refs #N`).
- Telemetry events, failure states, and stop signals, or an explicit rationale
   for why the issue has no observable runtime telemetry.

## GitHub delivery synchronization gate

Whenever work is started, in progress, or completed, update the governing
GitHub issue and its Project #2 item before implementation or status changes
are reported. The issue carries the problem, outcome, parent link, acceptance
evidence, and resolution. Project #2 carries Outcome, Milestone, Status,
Evidence, Blocked, owner, and applicable parent relationships. Slice membership
comes from the milestone description's mapping and the included issues, not a
new required Project field. Milestones carry committed outcomes; Status records
work state and explicit dependencies determine ordering. Legacy Phase metadata
has no role in this gate.

The Markdown tracker, feature list, debt tracker, and slice archive are frozen
historical context. Do not update them as a second active status system.

## Agent-assisted delivery orchestration

Copilot implements changes directly and owns validation and review. The
authoritative ownership rules live in
[AGENTS.md](../AGENTS.md) and
[.github/copilot-instructions.md](../.github/copilot-instructions.md); this
section defines the implementation brief and what makes delivery *traceable*.

The loop:

1. **Brief** — Copilot records a durable implementation brief in the governing
   GitHub Issue and ticket with a recorded decision: user outcome, bounded scope
   and non-goals, target public seam, safety invariants, acceptance scenarios,
   the exact validation command, and the required return evidence.
2. **Implement** — Copilot makes the named application, test, and
   implementation-facing record changes directly and runs the validation.
3. **Return evidence** — the implementer reports files changed, exact commands
   and exit codes, behavior observed, limitations, and any scope deviation.
4. **Review** — Copilot checks scope, safety, specification compliance, and
   synchronization, recording a linked Technical Debt issue for any unresolved gap
   rather than accepting it.

Delivery is **traceable** only when the governing GitHub issue and Project item
together carry the brief, the change set at the declared seam, the validation
evidence (focused command, expected pass signal, and the machine-readable
artifact with its exit code), and the review outcome. An edit outside the
declared scope is an unscoped edit; a session limit, timeout, or validation
failure leaves the slice `blocked`/`awaiting evidence`. Completion is never
inferred from files appearing in the tree.

## Outcome completion gate

Issue types and strategic TBP parent links remain useful, but are not a second
mandatory delivery ladder. Readiness requires resolved decisions and dependencies;
completion requires explicit outcomes and all required work with evidence. A
blocked issue propagates a blocker to affected slice and milestone acceptance,
not an automatic rewrite of unrelated issue status. New/current issue records
contain a `## Outcomes` checklist and validation evidence; completed outcomes
must be checked. Closed Experiments additionally require a checked `Pass`
outcome. Preserve the existing pre-2025 compatibility rule for historical closed
records without Outcomes; it is not an exemption for new work.
