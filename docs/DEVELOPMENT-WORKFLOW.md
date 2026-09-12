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