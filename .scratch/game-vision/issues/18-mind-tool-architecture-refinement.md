# Mind versus Tool architecture refinement

Type: architecture
Status: done
Primary phase: 7. Delivery workflow capabilities
Implementation slice: 011

## Outcome

Make player intellect and Player embodiment explicitly separate architectural
domains throughout Project0. Clarify perceptual cues and combat execution
profiles, and correct the earlier ambiguous use of `MET`.

## Decision

- The human mind owns observation, enemy-telegraph recognition, positioning,
  and puzzle deduction. No attribute grants permission for those decisions.
- The Player body is a tool whose attributes modify physical feedback,
  execution windows, movement, invulnerability, and other mechanical results.
- `MET` means derived Metabolism in friction and dodge contexts. Derived Mental
  Focus is a separate value named `mental_focus`; neither is a seventh vessel
  node.

## Scope

Update `CLAUDE.md`, ADR 0002, Slice 011, the Feature List, and Project Tracker.
No runtime code, formulas, tuning values, or melee-ticket decisions are added.

## Acceptance

The specification explicitly covers environmental perception cues, enemy
telegraph reading, unconditional correct puzzle execution, Focus-based timing,
physics alternatives, and DEX/Metabolism-based dodge frames and distance. A
focused term/semantic check and the configured GUT suite must pass.

Completed 2026-09-12. The focused semantic/placeholder check passed with exit
0. `scripts/run_gut_validation.sh` passed 23/23 tests and 70 assertions with
exit 0; both standard telemetry artifacts were verified.
