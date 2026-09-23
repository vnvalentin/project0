# Slice Development Workflow

This workflow operationalizes the [Engineering Constitution](ENGINEERING-CONSTITUTION.md).
It is mandatory for implementation slices and creates the evidence trail from
customer need to validated product behavior.

## Phases and slices

A **phase** defines the product-level desired outcome and exit gate. An
**implementation slice** is the smallest observable, reversible increment that
tests a stated hypothesis and delivers a bounded capability toward that phase.
It is not a general task bundle or an experiment without a delivery seam.

Every slice names its primary phase, user/system outcome, hypothesis or risk,
public seam, acceptance evidence, and explicit non-goals. A slice can advance
work tracked in another phase, but retains one primary phase for delivery
ownership. Slice completion comes from its own record; phase completion comes
from progress toward the phase exit gate.

Use TPSA small-lot, frequent delivery: choose the smallest independently
observable and reversible slice that can test one hypothesis, deliver it, and
learn from its evidence before planning the next slice. Do not turn a phase or
feature group into a large implementation batch.

## Vision, Goal, Feature, and Slice semantics (2026-09-20)

Four record types form one causal chain, top to bottom:

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
- A **Slice** is one step, or one bounded group of steps, that resolves a root
  cause standing between the current condition and the Feature's target
  condition. Slices are not experiments run to see whether a gap closes --
  they are where the code that closes it actually gets written. A Slice issue
  must name the root cause it addresses (`Parent feature: #N`) and the
  evidence that step closes that portion of the gap. A Slice that does not
  reduce the Feature's stated gap is scope creep, not delivery. A Feature
  closes only when its Slices' combined evidence satisfies the Feature's
  resolution proof.

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

A Goal's percent-complete is **never** derived from the Goal issue's own
open/closed state or a hand-ticked WGL checkbox — both are unreliable signals
on their own. It is the fraction of WGL items that have at least one
`Advances:` Feature which is itself resolved (closed, or every one of its
Slices closed). An item with zero linked Features, or only unresolved ones,
is not done, no matter what its checkbox says or whether the Goal issue itself
got closed.

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
   - **By when**: a bound — a phase, a dependency, or an explicit "no fixed
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
at each stage. As of 2026-09-20, a Feature's authoritative status lives on its
GitHub issue (label `Feature`), not in a file; `PROJECT-TRACKER.md` and the
flow dashboard mirror that status rather than duplicating it.

### Stages

1. **Vetting** — the capability exists only as one or more issues under a
   `.scratch/<goal>/` map. Each issue is validated and refined (grilled,
   researched, scoped) until its design is settled. Issue status moves
   `unclaimed` → `claimed` (being refined) → `resolved`. Decision-type issues
   (`grilling`, `research`, `architecture`) resolve into an ADR or recorded
   decision, not a feature.
2. **Ready** — a `resolved` *implementation* (`task`) issue graduates to a
   GitHub issue labeled `Feature` (`Parent goal: #N` in its body). Its design is
   complete and a developer can pick it up, but no implementation has started.
3. **Active** — a developer has started the slice. Feature `Status: In Progress`
   (equivalently *Active*). The slice follows SDD → BDD → TDD → verification.
4. **Awaiting evidence** — the slice's code is complete but its focused
   validation, telemetry artifact, and review are not yet green. It is NOT Done;
   this is a sub-state of Active enforced by the Jidoka evidence gate.
5. **Done** — the slice is delivered and validated with evidence. Feature
   `Status: Implemented` (equivalently *Done*).

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

### Promotion rules

- **The unit of promotion is the issue, not the goal.** Each resolved
  implementation issue becomes its own feature and slice; goals are containers,
  not the unit that ships.
- **Only implementation (`task`) issues become features.** `grilling`,
  `research`, and `architecture` issues resolve into ADRs/decisions that inform
  features.
- **A capability whose originating issues are not all `resolved` stays
  `Planned`**, never `Ready`.

### Stable identifiers

A feature keeps ONE identifier for its whole life; its `Status:` field carries
the lifecycle. The legacy `P-`/`IP-`/`F-` prefixes are frozen, opaque history and
no longer signal status — never rename an item when its status changes. New
features take the next unused number as `F-<n>` with an authoritative `Status:`.

### Cross-layer status mapping

| Lifecycle stage | `.scratch` issue | `FEATURE-LIST.md` status | Tracker badge | Dashboard |
| --- | --- | --- | --- | --- |
| Vetting | `unclaimed`/`claimed`/`resolved` | — | `queued` | Goal roadmap |
| Ready | `resolved` | `Ready` | `ready` | Ready |
| Active | `resolved` | `In Progress` (Active) | `in-progress` | Active |
| Awaiting evidence | `resolved` | `In Progress` (Active) | `in-progress` | Awaiting evidence |
| Done | `resolved` | `Implemented` (Done) | `done` | Done |

## Process maps and material/information flow

The living MIFC and the three concurrent process maps are maintained in
[PROCESS-MAPS.md](PROCESS-MAPS.md). Every meaningful slice should be traceable
through the maps from customer trigger, to product behavior, to delivery
evidence and standardized learning. When a slice introduces a new queue,
failure state, handoff, or external boundary, update the relevant map before
calling the flow complete.

## 1. Intake and scope

Classify the request and identify the user outcome, affected systems and
boundaries, unacceptable outcomes, smallest useful change, and explicit
non-goals. Identify the governing GitHub Issue before work starts; create one
when no suitable issue exists. Local `.scratch/<goal>/issues/*.md` planning
tickets can refine design and decisions, but they are not a substitute for the
GitHub Issue. Check `FEATURE-LIST.md` for an existing feature before creating a
new one. Record the GitHub Issue and feature IDs advanced by the slice and ask
Wayfinder or grilling questions when a product, ownership, or safety decision is
unclear. Ask only questions that affect implementation or safety.

## 2. SDD

Write a short slice design before coding when the change crosses a meaningful
boundary. State the goal, domain boundary, public seam, input/output contract,
invariants, failure behavior, persistence or integration effects, rollback plan,
and explicit non-goals. Link relevant tracker work and accepted ADRs.

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
do not require an ADR. Link the decision from the SDD and tracker.

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
`Root-cause learning` section and, when the liability remains open, in
`TECHNICAL-DEBT-TRACKER.md` as well. A chat message, terminal log, or commit
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

- **Branch per change.** Before starting work, fetch and branch from the latest
  `origin/main`. Name the branch `type/short-topic`, where `type` is one of
  `slice`, `fix`, `docs`, or `chore` — e.g. `slice/054-<topic>` (matching the
  number reserved in the [Slice Registry](slices/SLICE-REGISTRY.md)),
  `fix/<topic>`, `docs/<topic>`. Keep one logical change per branch, consistent
  with small-lot delivery.
- **No direct commits to `main`.** All history reaches `main` through a pull
  request; never push commits straight to `main`.
- **Commit each completed action.** After every complete logical action, commit
   the resulting work, push the branch, update or create the pull request, and
   merge it when the delivery gate is green. Do not accumulate multiple completed
   actions in one uncommitted worktree.
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

## Required slice record

Each implementation ticket links:

- Slice design (SDD), or an explicit no-SDD rationale.
- Behavior scenarios (BDD).
- Tests and public seam (TDD).
- Related ADR, or an explicit no-ADR rationale.
- Validation results and review outcome.
- Focused validation command, expected pass signal, and telemetry artifact path.
- Feature IDs advanced or created, duplicate-check result, and synchronized
	`FEATURE-LIST.md`/`PROJECT-TRACKER.md` updates.
- GitHub Issue number or URL, plus the closing or reference keyword expected in
   the pull request (`Fixes #N`, `Closes #N`, `Resolves #N`, or `Refs #N`).
- Telemetry events, failure states, and stop signals, or an explicit rationale
	for why the slice has no observable runtime telemetry.

## Atomic Delivery Record Synchronization Gate

Whenever a slice is started, in progress, or completed, all 4 sections of
`PROJECT-TRACKER.md` must be updated atomically with `FEATURE-LIST.md` and
`TECHNICAL-DEBT-TRACKER.md`:

1. **`## Phases` table**:
   - Set status to `in-progress` when the first slice for that phase starts
     implementation.
   - Transition status to `done` ONLY when the formal phase exit gate criteria
     are fully satisfied and verified.
2. **`### Phase work index`**:
   - Update feature and debt status badges (`done`, `in-progress`, `queued`,
     `blocked`).
   - Recalculate and update the progress percentage (`done items / all items in phase`).
   - Set the `- **Current slice:**` pointer to the active/latest slice.
3. **`### Implementation slice index`**:
   - Record the slice with its status (e.g., `100% complete; focused and full-suite validation passed`).
   - Link the slice record `docs/slices/0NN-*.md`, feature IDs, tech debt IDs,
   GitHub Issue, planning tickets, and ADRs.
4. **`## Work queue`**:
   - Mark `[x]` for items that have been scoped and delivered by slices.
   - Update status labels (`Ready`, `Queued`, `In progress`) for active design mapping.

## Agent-assisted delivery orchestration

Implementation in this repository is split between an orchestration/review layer
and an implementation layer. The authoritative ownership rules live in
[AGENTS.md](../AGENTS.md) and
[.github/copilot-instructions.md](../.github/copilot-instructions.md); this
section defines how a handoff is expressed and what makes it *traceable*.

The loop:

1. **Brief** — Copilot fills the durable
   [handoff template](templates/claude-code-handoff-template.md) from a governing
   GitHub Issue and ticket with a recorded decision: user outcome, bounded scope
   and non-goals, target public seam, safety invariants, acceptance scenarios,
   the exact validation command, and the required return evidence.
2. **Implement** — Claude Code CLI makes the named multi-file changes and runs
   the validation, owning application/test and implementation-facing record
   edits. Copilot makes these edits directly only when the user explicitly
   authorizes it.
3. **Return evidence** — the implementer reports files changed, exact commands
   and exit codes, behavior observed, limitations, and any scope deviation.
4. **Review** — Copilot checks scope, safety, specification compliance, and
   synchronization, opening a `TECHNICAL-DEBT-TRACKER.md` liability for any gap
   rather than accepting it.

A handoff is **traceable** only when the slice record and delivery records
together carry the GitHub Issue, the brief, the change set at the declared seam,
the validation evidence (focused command, expected pass signal, and the
machine-readable artifact with its exit code), the review outcome, and the
synchronized `FEATURE-LIST.md`/`PROJECT-TRACKER.md` updates. An edit outside the
declared scope is an unscoped edit; a session limit, timeout, or validation
failure leaves the slice `blocked`/`awaiting evidence`. Completion is never
inferred from files appearing in the tree.
## Canonical TBP lifecycle gate
TBP status is recursive across Hoshin → Theme → Feature → Epic → Experiment. A refined item with no active implementation is `READY_TO_PULL`; `IN_PROGRESS` descendants make the parent `IN_PROGRESS`, and any `NEEDS_GRILLING` descendant blocks readiness. `DONE` requires satisfied explicit outcomes and every required descendant done. New/current records must contain a `## Outcomes` section with checklist items (`- [ ]`/`- [x]`) and validation evidence; all must be checked. For compatibility, only closed records created before 2025-01-01 may omit the section. Closed Experiments additionally require a checked `Pass` outcome.
