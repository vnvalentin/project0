# Project Foundation Setup

Status: complete

This checklist is the required gate between bootstrapping and implementation.
The bootstrap creates `.foundation-incomplete`; remove that marker only after
all checks below pass.

## Product and boundaries

- [x] `AGENTS.md` names real test, typecheck, lint, build, and runtime commands.
- [x] `AGENTS.md` names the product boundary, external systems, sensitive-data
      rules, retention/deletion rules, and rollback unit.
- [x] `CONTEXT.md` names the product, primary users, domain terms, authorities,
      external contexts, and invariants.
- [x] `.github/copilot-instructions.md` points to the governing records and this
      foundation gate.

## Delivery records

- [x] Every active delivery item has a governing GitHub issue with its current
      condition, target outcome, acceptance criteria, non-goals, and evidence.
- [x] Feature and Slice issues carry their required parent relationship in the
      issue body and as a native GitHub parent link.
- [x] Active issues are in GitHub Project `Project0 Delivery` (#2) with Outcome,
      Phase, Status, Evidence, Blocked, owner, and Parent populated. Milestones
      are assigned only to committed delivery outcomes.
- [x] The first implementation Slice issue links its SDD, BDD, public seam,
      safety invariant, ADR or no-ADR rationale, validation, and review outcome.
- [x] Every known limitation is either a GitHub Technical Debt issue or an
      explicit intentional scope boundary.

`docs/PROJECT-TRACKER.md`, `docs/FEATURE-LIST.md`,
`docs/TECHNICAL-DEBT-TRACKER.md`, and `docs/slices/` are frozen historical
context. They are not authorities for current delivery state.

## Validation

Run from the project root:

```text
if git grep -nE "\\{\\{[A-Za-z][A-Za-z0-9_-]*\\}\\}" -- AGENTS.md CONTEXT.md CLAUDE.md docs/SYSTEMS-SPECIFICATION.md .github/copilot-instructions.md; then exit 1; fi
git grep -nE "PROJECT-TRACKER|FEATURE-LIST|TECHNICAL-DEBT-TRACKER|docs/slices" -- docs/PROJECT-SETUP-CHECKLIST.md
bash scripts/check_record_sync.sh
```

The placeholder scan must return no matches in active repository foundation
and configuration files. The delivery-record search must find the frozen-files
paragraph above and no claim that those files own current status. The
record-sync gate must exit 0; it validates historical links and GitHub issue
traceability without requiring status parity with frozen archives. Record all
three results as evidence on the governing GitHub issue.

## Gate closure

- [x] A human has reviewed the product purpose, boundaries, and unacceptable
      outcomes: the user directed the exact scope of the first playable slice
      (local identity gate, flat plane, movement only — no map, generated
      world, world save, quests, or Ollama/SQLite integration), recorded in
      `.scratch/game-vision/issues/02-choose-first-playable-slice.md` under
      "User direction", and confirmed it again when requesting this work.
- [x] The checklist status is changed to `complete`.
- [x] `.foundation-incomplete` is removed.
- [x] Only now may the first implementation slice begin.
