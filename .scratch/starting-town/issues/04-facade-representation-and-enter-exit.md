Type: grilling
Status: resolved

## Question

What does "enter/exit" a facade-only building actually do for the player
(e.g. a bounded `Area3D` trigger volume plus a UI prompt, with no interior
scene transition — just a label like "You are at the Smithy"), and what
server-vs-client ownership applies to that trigger per CLAUDE.md's Runtime
Ownership split (is entering a building purely cosmetic/client-observed, or
does the server need to know a player's current building for a future
gameplay reason)?

## Answer

- **Trigger mechanism**: automatic proximity — an `Area3D` around each
  facade; overlap alone shows the label, no interact keypress. Nothing here
  is a menu/transaction to confirm.
- **What entering shows**: a UI label overlay (e.g. "You are at the Smithy"),
  reusing the existing `client/gameplay.tscn` UI label pattern
  (`ConnectionStatus`, `MovementHint`) — no new UI system.
- **Ownership**: purely client-observed/cosmetic. Each client detects its own
  local player's `Area3D` overlap; nothing is sent over the network. This is
  presentation (like the existing camera/HUD work), not a world mutation or
  outcome, so it doesn't need server authority under CLAUDE.md's Runtime
  Ownership split. A future feature (shop economy, quests) that needs server
  awareness of "which building" is a new decision when that feature is
  scoped, not assumed here.
- **Exclusivity**: none. Any number of players can overlap the same facade
  simultaneously; each sees their own local label, no shared/contended state.
