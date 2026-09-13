Type: grilling
Status: resolved
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

## Answer

Assembled 2026-09-13; the four upstream decisions were locked, so this capstone authored
the destination artifacts (Copilot's planning-doc ownership; the code itself stays a
downstream slice). The ADR's three-part test is met — the anchor is hard to reverse
(touches all constants + future content), surprising without context (Imperial yards
over Godot's meter convention; a Sector that isn't fully tiled), and a real trade-off
(yard vs foot vs meter; region-container vs coarsen vs chunk).

Authored:
- **ADR** `docs/adr/0003-imperial-world-scale.md` — records the anchor (1 unit = 1 yard),
  the world unit → Tile → Sector model, Sector ≈ ¼ mile (440 units, tunable,
  region-container), the `WorldScale` seam, the relabel-only reconciliation + gravity
  stance, consequences, and a two-slice implementation handoff with non-goals and
  validation.
- **`CONTEXT.md` terms** — added **World unit** (1 yard, Imperial) and **Tile** (the fine
  1-yard cell), and extended **Sector** with its span + region-container model.
- **Handoff brief** — the ADR's "Implementation handoff" section enumerates the two
  downstream slices (`WorldScale` module + relabel reconciliation) with public seams,
  non-goals, and validation expectations.

**Map destination reached** — all five tickets resolved, no open frontier. The scale is
locked and handoff-ready; implementation (the `WorldScale` module + meters→yards rename)
is a downstream Claude slice, not this planning map.
