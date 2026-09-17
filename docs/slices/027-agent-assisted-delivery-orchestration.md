# Slice 027: Agent-assisted delivery orchestration
GitHub issue: #95

Status: complete

Tracker context: Phase 13 — Delivery workflow capabilities; delivers
[P-004](../FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration) by
formalizing the Copilot → Claude Code CLI handoff mechanism and demonstrating
one traceable handoff.

Planning ticket: [game-vision map](../../.scratch/game-vision/map.md) — the
"Delivery workflow" and "Handoff rule" notes; handoff-template origin
[.scratch/game-vision/claude-code-handoff-template.md](../../.scratch/game-vision/claude-code-handoff-template.md).

## SDD

Goal: make agent-assisted delivery orchestration a first-class, durable, and
traceable capability. Copilot (orchestration/review) produces a bounded
implementation handoff; Claude Code CLI (implementation) makes the named
multi-file changes and returns validation evidence; Copilot reviews the result
against the brief before records advance.

Domain boundary: this is a delivery-workflow capability, not product/game code.
It owns the durable handoff template, the traceable-handoff evidence format, and
the records that prove one handoff — nothing in `client/`, `server/`, or
`shared/`.

Public seam:

- [docs/templates/claude-code-handoff-template.md](../templates/claude-code-handoff-template.md)
  — the durable, canonical handoff brief (promoted from `.scratch/`).
- [DEVELOPMENT-WORKFLOW.md](../DEVELOPMENT-WORKFLOW.md) — the "Agent-assisted
  delivery orchestration" section defining the loop and the traceable-handoff
  evidence record.
- Slice records under `docs/slices/` and the synchronized
  `FEATURE-LIST.md` / `PROJECT-TRACKER.md` entries.

Ownership is authoritative in [AGENTS.md](../../AGENTS.md) and
[.github/copilot-instructions.md](../../.github/copilot-instructions.md); this
slice references, and does not redefine, those rules.

Invariants:

- Copilot forms the brief and reviews; Claude Code CLI owns application/test and
  implementation-facing record edits, unless the user explicitly authorizes a
  direct Copilot edit.
- A handoff is complete only with brief, change set, validation evidence, review
  outcome, and synchronized feature/tracker records — code passing alone is
  insufficient.
- An edit outside the declared scope is an unscoped edit and is flagged in
  review, never silently accepted.

Failure behavior: a session limit, timeout, or validation failure leaves the
slice `blocked`/`awaiting evidence`; completion is never inferred from files in
the tree.

Rollback: revert this documentation-only slice; no runtime data or migration is
created.

## BDD

### Bounded handoff produces a traceable record

Given a governing ticket with a recorded decision and a bounded public seam
When Copilot fills the handoff template and hands implementation to Claude Code
CLI
Then the resulting slice record links the brief, the change set at the declared
seam, the validation evidence with its exit code, the review outcome, and the
synchronized feature/tracker updates.

### Unscoped edit is caught in review

Given a handoff that declared a bounded set of files
When the returned change set touches a file outside that set, or omits required
feature synchronization
Then Copilot's review flags it (opening a `TECHNICAL-DEBT-TRACKER.md` liability
if needed) rather than accepting it, and the slice is not marked done.

### Direct-edit authorization

Given the user explicitly authorizes a direct Copilot edit for a
delivery-workflow record
When Copilot makes the edit itself instead of handing off
Then the ownership boundary is preserved because the authorization is explicit
and recorded, and the same evidence and synchronization requirements apply.

## Demonstration: the Slice 008 handoff (worked example)

One real, traceable handoff already in the repository, reconstructed end to end:

- **Brief** (Copilot → Claude Code CLI): `claude -p "You are the implementation
  owner for Slice 008 … complete or repair Slice 008 only at its public seams:
  shared/sector_blueprint_schema.gd, server/sector_blueprint_service.gd, and the
  contract test path … Preserve the explicit scope boundary: no geometry,
  gameplay state, SQLite, or Canon persistence … Run focused validation and the
  configured GUT suite … report files changed, implementation decisions, exact
  commands and exit codes, and remaining failures"`. Bounded scope, a named
  seam, explicit non-goals, a validation command, and required evidence — the
  template's fields.
- **Change set**: the three declared seams only —
  `shared/sector_blueprint_schema.gd`, `server/sector_blueprint_service.gd`,
  `tests/integration/test_sector_blueprint_contract.gd`.
- **Validation evidence**: `scripts/run_gut_validation.sh` PASS, 14/14 tests,
  exit 0, with `build/validation/gut.xml` + `validation-summary.json`, recorded
  in [Slice 008](008-sector-blueprint-contract.md#validation).
- **Review outcome**: Copilot's review caught a *missing-evidence* gap (an
  absent `scripts/test_authoritative_movement.gd`) and tracked it under
  [DT-006](../TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut)
  instead of silently accepting the run as green — exactly the "no unscoped
  edits or missing synchronization" bar.
- **Feature synchronization**:
  [Slice 008 record](008-sector-blueprint-contract.md),
  [IP-004](../FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation),
  and the Phase 8 tracker entry advanced together.

This is one traceable handoff with no unscoped edits and complete feature
synchronization — the P-004 validation criterion, evidenced against a real
delivery.

## TDD and validation seam

Documentation/workflow slice: its executable check verifies the promoted
template exists with its required sections, that the workflow section is
present, and that no unresolved placeholders remain. Runtime regression uses
`scripts/run_gut_validation.sh`.

Focused validation:

```bash
test -f docs/templates/claude-code-handoff-template.md && \
required=("User outcome" "Scope" "Public seam" "Safety invariants" "Acceptance scenarios" "Validation" "Return report" "Traceable handoff evidence"); \
for t in "${required[@]}"; do grep -Fq -- "$t" docs/templates/claude-code-handoff-template.md || { printf 'missing: %s\n' "$t"; exit 1; }; done && \
grep -Fq "Agent-assisted delivery orchestration" docs/DEVELOPMENT-WORKFLOW.md && \
! grep -nE '\{\{[^}]*\}\}' docs/slices/027-agent-assisted-delivery-orchestration.md docs/templates/claude-code-handoff-template.md
```

Result: PASS, exit 0.

Full regression: `scripts/run_gut_validation.sh` passed 168/168 tests across
22 scripts with exit 0; `build/validation/validation-summary.json` records
`status: passed`, `exit_code: 0`, and `scripts_expected == scripts_ran == 22`.

## ADR decision

No new ADR. This slice formalizes and records an existing delivery mechanism
whose ownership boundary is already fixed by [AGENTS.md](../../AGENTS.md),
[.github/copilot-instructions.md](../../.github/copilot-instructions.md), and the
[development workflow](../DEVELOPMENT-WORKFLOW.md). It introduces no new
architectural, persistence, or security boundary.

## Telemetry and stop signals

No runtime telemetry (documentation slice). The orchestration's observable
signals are delivery-record artifacts: the handoff brief, the change set, the
validation summary and exit code, the review outcome, and the synchronized
feature/tracker updates. A missing brief, an unscoped edit, a failed or missing
validation artifact, or stale feature synchronization is an Andon stop signal
that leaves the slice `blocked`/`awaiting evidence`.

Delivery note: this slice was delivered by direct Copilot edits under explicit
user authorization (its subject is the orchestration records themselves), not
via a Claude Code CLI handoff. The ownership boundary is preserved because the
direct-edit authorization was explicit and recorded; the worked example above is
the demonstrated handoff.

## Non-goals

No product or game code, no CLI automation, no new scripts or dependencies, no
change to the authoritative ownership rules, and no closure of P-005 (Remote-SSH
workspace) or P-006 (asset quarantine), which remain queued in Phase 7.
