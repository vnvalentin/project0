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

- [x] `docs/PROJECT-TRACKER.md` has a concrete goal, phase names, phase status,
      and measurable exit gates.
- [x] `docs/FEATURE-LIST.md` contains only real planned, in-progress, or
      implemented features; template entries are removed.
- [x] `docs/TECHNICAL-DEBT-TRACKER.md` contains every known liability, with
      classification, type, owner, impact, remediation, status, and links.
- [x] The Project Tracker, Feature List, and Technical Debt Tracker agree on
      feature, debt, phase, and status names.
- [x] The first implementation slice links its SDD, BDD, public seam, safety
      invariant, ADR or no-ADR rationale, validation, and review outcome.
- [x] Every known limitation is either tracked as technical debt or explicitly
      recorded as an intentional scope boundary.

## Validation

Run from the project root:

```text
rg "\\{\\{[^}]+\\}\\}" AGENTS.md CONTEXT.md docs/PROJECT-TRACKER.md docs/FEATURE-LIST.md docs/TECHNICAL-DEBT-TRACKER.md docs/slices --glob '!docs/slices/0000-template.md'
```

The command must return no matches against active delivery records.
`docs/slices/0000-template.md` is the slice template, not an active delivery
record — it is expected to contain literal `{{...}}` placeholder tokens
forever, and is excluded above for that reason rather than being emptied or
deleted. Likewise, `AGENTS.md`'s own line describing the `` `{{...}}` ``
placeholder convention (in "Foundation gate") is documentation prose about the
marker syntax, not an unresolved placeholder; if the scan above ever flags it,
confirm by inspection that the match is inside a code span describing the
convention itself, not an unfilled `{{field_name}}` token in real content, and
do not treat it as a foundation-gate failure. Then inspect the three delivery
records side by side and confirm the cross-links resolve. Run the repository's
focused validation command and record its result and telemetry artifact in the
slice.

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