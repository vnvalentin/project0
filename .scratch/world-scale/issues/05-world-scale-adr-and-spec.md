Type: grilling
Status: claimed
Blocked by: 01, 02, 03, 04

## Question

Author the capstone artifact that makes the map's destination real and handoff-ready.

Sub-questions to resolve here:

- Write an ADR (`docs/adr/NNNN-imperial-world-scale.md`) recording: 1 unit = 1 yard
  (Imperial); the world unit → Tile → Sector hierarchy; Sector ≈ ¼ mile; the
  grid-resolution / bounds decision (ticket 01); the Godot physics stance (ticket 02);
  the contract seam (ticket 03); and the constant-reconciliation policy (ticket 04) —
  with trade-offs and rejected alternatives.
- Add `CONTEXT.md` glossary terms: **World unit**, **Tile** (with its yard size),
  **Sector** (with its span), and any **World scale** term — glossary only, no
  implementation detail.
- Produce a concise measurement spec / implementation-handoff brief enumerating the
  downstream slices (contract-seam module, constant reconciliation, schema-bound
  changes) with public seams, non-goals, and validation expectations, so slices can be
  opened safely.

Before writing the ADR, verify its three-part test is met (hard to reverse, surprising
without context, the result of a real trade-off).
