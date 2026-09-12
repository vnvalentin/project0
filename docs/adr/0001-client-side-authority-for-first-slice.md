---
status: accepted
---

# Client-side authority for the first playable slice's movement

The first playable slice (identity gate, flat plane, player movement) runs
fully client-side with no server process and no network authority boundary.
Movement is computed directly on the client `Player` node from local input.
This is a deliberate, temporary departure from the project's stated
server-authoritative multiplayer architecture, scoped to this slice only.

## Context

`CLAUDE.md` and the game-vision planning
(`.scratch/game-vision/issues/03-define-authority-model.md`) commit this
project to server-authoritative multiplayer using Godot's High-Level API.
The user, however, asked for the smallest possible first playable slice:
local identity gate, flat plane, movement — explicitly excluding networking.
Building even a minimal server/client split for movement in this slice would
mean designing input replication, reconciliation, and authority handling
before the authority model itself has been decided (that decision is tracked
as open work in `docs/PROJECT-TRACKER.md`'s work queue and in game-vision
issue 03). Doing so now risks locking in an authority model by accident,
through whatever is easiest to hack together, rather than by deliberate
design later.

## Decision

For this slice only, the `Player` node's movement script
(`client/player.gd`) reads local input and moves the node directly with no
server round-trip, no `MultiplayerSynchronizer`, and no RPCs. The identity
gate (`client/identity_gate.gd`) is a local, single-process scene transition
with no session or network handshake. No code in this slice assumes or
implies which side will hold authority once networking is introduced.

## Consequences

- The slice is playable and testable headlessly with zero server/Docker/
  networking setup, matching the user's explicit non-goals.
- When Phase 2 (networked multiplayer foundation) begins, `player.gd`'s
  movement logic will need to be split or wrapped so the server simulates
  and the client predicts/interpolates, per whatever authority model
  game-vision issue 03 settles on. This is expected rework, not an oversight.
- Nothing in this slice must be read as an implicit choice of client-
  authoritative movement for the shipped game; that decision remains open and
  is tracked in `docs/PROJECT-TRACKER.md`'s work queue.
