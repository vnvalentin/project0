Type: grilling
Status: open
Blocked-by: 04-per-server-telemetry-content, 05-tier1-transport, 06-server-registry-and-onboarding, 07-operator-token-auth-seam, 08-operator-console-surface-prototype

## Question

**Capstone — completes the map.** Fold every resolved decision into a locked,
handoff-ready spec so downstream build slices can start safely.

Sub-questions to resolve here:

- **ADR.** Author an ADR recording the operator-console architecture: the `OpsSnapshot`
  contract + extension mechanism, health-file transport, directory-scan registry, the
  tiered read/control model, the host-helper + in-Godot control split, and the
  `OperatorAuth` seam. (ADR-worthy: hard to reverse, surprising without context, a real
  trade-off.)
- **CONTEXT.md terms.** Add the domain terms this effort introduces (Ops snapshot,
  Operator console, Control action, Operator token, Server registry, drain/degraded).
- **Downstream slice sequencing.** Produce the ordered implementation slice list with
  SLICE-REGISTRY numbers reserved, and their public seams / test seams — graduating the
  "downstream build-slice sequencing" fog from the map.
- **Handoff brief.** One brief pointing downstream implementers at the ADR + the
  resolved tickets, with the first slice's failing-test seam identified.

Recommended direction: write the ADR + `CONTEXT.md` terms, reserve the slice block in
`docs/slices/SLICE-REGISTRY.md`, and hand off with the first slice (the `OpsSnapshot`
contract seam + its pure GUT test) named as the entry point. Mark the map COMPLETE.
Confirm or revise at resolution.

## Answer

_Pending._
