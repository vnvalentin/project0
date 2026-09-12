# Project0 Copilot Instructions

Follow [AGENTS.md](../AGENTS.md) for repository commands, boundaries, sensitive
data, and deployment rules. Treat the
[Engineering Constitution](../docs/ENGINEERING-CONSTITUTION.md) and
[development workflow](../docs/DEVELOPMENT-WORKFLOW.md) as mandatory operating
logic for every implementation slice.

Use [TPSA](../docs/tpsa.md) as the core behavior profile for all activities.

Use the delivery records together:

- [Project Tracker](../docs/PROJECT-TRACKER.md) owns phase exit gates and the
  cross-index for features, liabilities, and slices.
- [Feature List](../docs/FEATURE-LIST.md) owns validated capabilities and their
  change history.
- [Technical Debt Tracker](../docs/TECHNICAL-DEBT-TRACKER.md) owns every
  liability through resolution, reclassification, or permanent acceptance.

## Implementation ownership

Copilot is the orchestration and review layer for implementation work in this
repository. Unless the user explicitly requests direct Copilot edits, Copilot
must not modify application code, tests, or implementation-facing delivery
records. Copilot may inspect files, form the bounded handoff, invoke Claude CLI,
coordinate validation, and review Claude's resulting diff and evidence.

Claude CLI owns application-code, test-code, and implementation-facing
delivery-record edits. Every handoff must name the target slice, public seam,
non-goals, validation command, and required evidence. If Claude CLI is
unavailable or the handoff times out, stop and report the blocker rather than
silently taking over implementation.

Before implementation, identify the primary phase and slice. Update the
authoritative feature or debt record and the Project Tracker together whenever
scope or status changes. Do not treat a completed slice as proof that its phase
exit gate is complete.

Foundation gate: before implementation, read `../docs/PROJECT-SETUP-CHECKLIST.md`.
If `../.foundation-incomplete` exists or any active record still contains a
`{{...}}` placeholder, stop implementation and complete the foundation records
first. Remove the marker only after the checklist validation passes.