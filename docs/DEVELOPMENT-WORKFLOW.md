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

## Delivery lifecycle

Every capability moves through one lifecycle with a single authoritative status
at each stage. The stage lives in exactly one place at a time and is mirrored,
not duplicated, across `FEATURE-LIST.md`, `PROJECT-TRACKER.md`, and the flow
dashboard.

### Stages

1. **Vetting** — the capability exists only as one or more issues under a
   `.scratch/<goal>/` map. Each issue is validated and refined (grilled,
   researched, scoped) until its design is settled. Issue status moves
   `unclaimed` → `claimed` (being refined) → `resolved`. Decision-type issues
   (`grilling`, `research`, `architecture`) resolve into an ADR or recorded
   decision, not a feature.
2. **Ready** — a `resolved` *implementation* (`task`) issue graduates to a
   feature in `FEATURE-LIST.md` with `Status: Ready`. Its design is complete and
   a developer can pick it up, but no implementation has started.
3. **Active** — a developer has started the slice. Feature `Status: In Progress`
   (equivalently *Active*). The slice follows SDD → BDD → TDD → verification.
4. **Awaiting evidence** — the slice's code is complete but its focused
   validation, telemetry artifact, and review are not yet green. It is NOT Done;
   this is a sub-state of Active enforced by the Jidoka evidence gate.
5. **Done** — the slice is delivered and validated with evidence. Feature
   `Status: Implemented` (equivalently *Done*).

A **goal/map** is "complete" only when every one of its issues has graduated out
of Vetting — each `resolved`, and either promoted to a feature or recorded as a
decision/ADR.

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
non-goals. Check `FEATURE-LIST.md` for an existing feature before creating a
new one. Record the feature IDs advanced by the slice and ask Wayfinder or
grilling questions when a product, ownership, or safety decision is unclear.
Ask only questions that affect implementation or safety.

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
     planning tickets, and ADRs.
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
   ticket with a recorded decision: user outcome, bounded scope and non-goals,
   target public seam, safety invariants, acceptance scenarios, the exact
   validation command, and the required return evidence.
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
together carry the brief, the change set at the declared seam, the validation
evidence (focused command, expected pass signal, and the machine-readable
artifact with its exit code), the review outcome, and the synchronized
`FEATURE-LIST.md`/`PROJECT-TRACKER.md` updates. An edit outside the declared
scope is an unscoped edit; a session limit, timeout, or validation failure
leaves the slice `blocked`/`awaiting evidence`. Completion is never inferred
from files appearing in the tree.