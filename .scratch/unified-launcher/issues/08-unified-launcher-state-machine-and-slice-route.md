# Unified launcher state machine, security boundaries, telemetry, and slice route

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: 02-lan-wan-mode-selection-checkbox, 03-version-check-and-patch-manifest, 04-patch-delivery-integrity-and-rollback, 05-first-run-onboarding-and-account-setup, 06-wan-self-service-registration-dt010, 07-packaging-and-build-for-patchable-payload

## Question

Integrate every resolved decision into the destination artifact: the unified
launcher spec, its ADR(s), and the staged implementation slice route.

Decide and record:

- **State machine**: the single ordered launcher flow that composes mode
  selection -> version check -> patch (if needed) -> onboarding/login -> launch,
  with the branch differences between LAN and WAN and the defined failure/
  rollback transitions at each stage.
- **Security boundaries**: what the launcher trusts and verifies (signed
  manifest/assertions, DPAPI key handling, no privilege escalation, no OPNsense
  or private-key exposure on the patch surface), stated as explicit trust
  boundaries.
- **Telemetry**: the bounded events the launcher emits per stage (mode-selected,
  version-checked, patch-applied/failed, onboarding-outcome, launch), graduating
  the fog note on the map.
- **Slice route**: an ordered set of bounded SDD/BDD/TDD implementation slices
  (each with a public seam, evidence, telemetry, rollback, and synchronized
  records) that build the launcher end to end, sequenced by dependency.

## Required decision output

The handoff-ready launcher spec + ADR(s) + staged slice route. When this ticket
resolves, the way to the destination is fully charted and implementation can be
handed off slice by slice.

## Answer

_(unresolved)_
