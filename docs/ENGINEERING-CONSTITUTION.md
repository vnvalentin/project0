# Engineering Constitution

This constitution governs how `{{project_name}}` is designed, built, tested,
operated, and improved. It applies to people and engineering agents. Product
terms and ownership rules belong in `CONTEXT.md` and `AGENTS.md`; they specialize
this general constitution.

The repository's Copilot instructions are a concise entrypoint for agents. They
must point to this constitution, the development workflow, `AGENTS.md`, and the
delivery records; they do not duplicate this constitution's rules.

## 1. Purpose and priority

The product is a tool for people. Make work easier for the person using,
operating, testing, or maintaining it. Prefer clarity, confidence, and
time-to-completion over code volume, utilization, or premature optimization.

Evaluate every action in this order:

1. **Safety**: avoid unacceptable harm, data loss, security exposure,
   uncontrolled side effects, and unsafe production behavior.
2. **Quality**: satisfy intended behavior, contracts, edge cases, accessibility
   where applicable, and regression requirements.
3. **Flow**: reduce waiting, handoffs, repeated work, confusion, and rework.
4. **Efficiency**: only then reduce time, compute, complexity, or operator effort.

Never buy efficiency by weakening an earlier stage. If an earlier stage is
unknown, stop and gather evidence.

## 2. TPSA thinking way

Apply TPSA: **Make It Work, Then Make It Right**. Use the smallest functional,
observable, reversible change that tests the current hypothesis. Build, validate,
observe actual behavior, and improve from evidence.

TPSA is the core behavior profile for all activities by people and agents. Follow
`docs/tpsa.md` when planning, building, operating, reviewing, or improving work.

TPSA is not permission to rush. Security-sensitive changes, data migrations,
public contracts, financial or compliance behavior, and irreversible actions
require explicit design, stronger validation, and a recovery plan first.

## 3. Three process lanes

Keep these lanes distinct while connecting them through evidence:

### Customer process

The person's journey, intent, decisions, waits, confidence, and outcome. Identify
the trigger, desired outcome, repeated work, confusion, and observable success.

### Product behavior process

The system's inputs, decisions, state transitions, outputs, queues, failures,
and telemetry. Identify what can fail, how failure is surfaced or absorbed, and
what stop signal protects the person or system.

### Delivery and learning process

The team's evidence, hypothesis, experiment, implementation, validation, and
standardization loop. Record what triggered the change, what reality showed, and
what practice should be retained, changed, or removed.

Customer experience is the purpose. Product behavior serves it. Delivery and
learning improve both.

## 4. Required development loop

### Phases and implementation slices

A **phase** defines a product-level desired outcome and exit gate. An
**implementation slice** is the smallest observable, reversible increment that
tests a stated hypothesis and delivers a bounded capability toward that phase.
It is not a general bundle of tasks or an experiment without a delivery seam.

Each slice must identify its primary phase, user/system outcome, hypothesis or
risk, public seam, acceptance evidence, and explicit non-goals. A slice can
advance tracker items in other phases when a capability crosses a boundary, but
it has one primary phase for delivery ownership. Slice completion measures the
slice's own evidence; phase completion measures progress toward the phase exit
gate and is not reduced to a count of completed slices.

Every work item must be traceable to a GitHub Issue before work starts. Local
planning tickets under `.scratch/` may refine the design, but they do not
replace the GitHub Issue that anchors external intent, branch work, pull request
review, slice records, and tracker updates. Pull requests that complete the work
use a closing keyword such as `Fixes #N`; partial or related work uses `Refs #N`.

Every goal must name what good looks like before it can be treated as complete.
The goal's success condition is a customer-facing acceptance-criteria checklist,
not the mere existence or closure of child work items. Child issues capture known
questions, research, decisions, and implementation candidates; new child issues
may appear as learning clears fog around the goal. A goal with no map is new and
unresearched, and its target coverage is zero until its criteria are written.

Apply TPSA as small-lot, frequent delivery: prefer the smallest independently
observable, reversible slice that tests one hypothesis and produces evidence.
Feature groups and phases must not become excuses for bundled implementation.
Every slice includes SDD, BDD, and TDD thinking from intake onward, with
telemetry designed at the public seam so quality and observability are built in
from the beginning.

Every implementation slice follows `docs/DEVELOPMENT-WORKFLOW.md`:

1. Intake and clarify the user, outcome, constraints, boundaries, and
   unacceptable outcomes.
2. Scope the smallest useful change and explicit non-goals.
3. Specify SDDs for persistence, authentication, external APIs, irreversible
   behavior, or other meaningful boundaries. Write BDD scenarios for normal,
   highest-risk, and applicable safety or idempotency behavior.
4. Test first at an agreed public seam using a red-green-refactor loop.
5. Implement with existing abstractions; preserve unrelated work. Staged
   capabilities must be safely disabled when off.
6. Validate the cheapest focused check first, then relevant type, lint, build,
   integration, and full-suite checks.
7. Record the design, scenarios, tests, ADR or no-ADR rationale, validation, and
   review outcome. Name the GitHub Issue, feature IDs advanced, check for
   duplicates, update `FEATURE-LIST.md` and `PROJECT-TRACKER.md`, and record
   telemetry and stop signals. Update documentation when behavior or operations
   change.

## 5. Jidoka and Genchi Genbutsu

Stop automatically on an unexpected test or build failure, degraded health,
contradictory behavior, missing or ambiguous evidence, suspicious persisted data,
external dependency drift, or an unclear security boundary.

Go and see the actual evidence: inspect requests, responses, logs, configuration,
environment, persisted state, and failing versus working paths. Reproduce the
smallest discriminating check and verify every link in the root-cause chain.
Never call a workaround a root-cause fix without evidence that it prevents
recurrence.

## 6. Evidence, observability, and completeness

A capability is complete only when integrated into the intended runtime path,
observable through meaningful state or telemetry, regression tested, validated in
the environment where it matters, and reversible or safely disabled where needed.

Measure blocked, skipped, degraded, rejected, and no-op decisions with explicit
reasons, not only successes. Use progressive disclosure: signal first, context
second, detail when needed. Never claim live behavior from unit tests or startup
success alone.

## 7. Safety and data

- Treat external input as untrusted.
- Fail closed for authorization, destructive operations, and safety-critical
  policy gates unless the design explicitly requires otherwise.
- Fail open only when consequences are bounded, observable, understood, and safer
  than blocking the whole system.
- Prefer durable state for workflows that must survive restart or reload.
- Make rollback and recovery explicit.
- Never silently discard an accepted but unconfirmed external operation.
- Never persist secrets, tokens, passwords, payment data, browser storage, or
  regulated personal data in unsafe locations.
- Preserve source evidence when a decision is ambiguous; do not guess.

Project-specific safety rules in `AGENTS.md` are mandatory constraints.

## 8. Language and learning

Use blameless language. Describe system conditions and process, not personal
fault. Use TPS, kaizen, muda, Jidoka, Genchi Genbutsu, and standardized work
when they clarify an engineering decision.

For defects and incidents, record the issue, observed evidence, verified root
cause, affected boundary, fix, validation, regression test, and follow-up. Keep
reusable lessons separate from product-specific secrets.

## Decision gate

Before acting, ask:

1. Is it safe?
2. Is it correct and testable?
3. Does it improve flow for the person or system?
4. Only then, can it be made more efficient?

If any answer before efficiency is unknown, stop and gather evidence.