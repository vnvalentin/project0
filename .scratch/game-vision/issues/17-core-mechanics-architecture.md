# Core mechanics architecture contract

Type: architecture
Status: done
Primary phase: 7. Delivery workflow capabilities
Implementation slice: 010

## Outcome

Capture the biological progression, kinetic combat, magic-equilibrium, and
Canon-generation rules as one normative root architecture contract that future
implementation slices can use without reconstructing authority or validation
boundaries.

## Scope

- Replace the thin root `CLAUDE.md` with a strict, self-contained systems
  specification.
- Define server/client/shared ownership, versioned data contracts, validation,
  state transitions, telemetry, and testing seams.
- Preserve the supplied mechanics while distinguishing current implementation
  from future target behavior.
- Synchronize the living-architecture feature and add planned progression work.

## Non-goals

No gameplay code, final balance formulas, tuning constants, geometry, database
migration, spell catalog, content list, UI, art, audio, or resolution of the
open `.scratch/melee-combat/` decision tickets.

## Decision

Initial interpretation (superseded by Slice 011): `MET` was treated as derived
Mental Focus. The clarified specification establishes `MET` as derived
Metabolism and `mental_focus` as a separate derived value; neither is a seventh
vessel attribute. `INT`, `WIS`, Metabolism, and Focus effects may change
physical affordances, sensory presentation, or execution windows but never
determine whether a correctly deduced puzzle solution is accepted. Clients
submit intents; the server alone validates and commits combat, progression,
cooldown, magic, and Canon outcomes.

## Acceptance evidence

- `CLAUDE.md` contains every required mechanic, authority boundary, schema,
  validation rule, and current-versus-target distinction.
- Local Markdown links and required terms pass an executable documentation
  check.
- The configured GUT suite remains green and emits its normal artifacts.

Completed 2026-09-12. The required-term/placeholder check passed with exit 0;
all local links resolve. `scripts/run_gut_validation.sh` passed 23/23 tests and
70 assertions with exit 0. Evidence is recorded in
`docs/slices/010-core-mechanics-architecture.md`.
