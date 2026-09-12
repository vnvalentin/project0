Type: task
Status: resolved
Blocked by: 09

## Question
How should the client use the red local Player as a responsive predicted representation while consuming server-authoritative snapshots to reconcile drift and smoothly render the blue networked Player, without adding remote-player replication or persistence?

## Decision boundary
- Keep the red local Player responsive to local WASD immediately.
- Tag each locally sent input intent with a sequence number.
- Include the latest processed input sequence in server position snapshots.
- Reconcile the red local Player only when the server snapshot differs from the predicted state; do not replace the authoritative server with client position.
- Smooth the blue networked Player toward authoritative snapshots using interpolation or bounded smoothing.
- Preserve the existing server movement authority and localhost/LAN connection behavior.
- No remote-player replication, persistence, authentication, reconnect, collision authority, or production networking architecture in this slice.

## Acceptance evidence
- A real two-process smoke test proves input sequence ordering and authoritative acknowledgement.
- A bounded injected correction converges the red predicted Player to the server snapshot.
- The blue Player reaches the authoritative position without teleporting for ordinary snapshot deltas.
- Slice 001, Slice 002, Slice 003, and Slice 004 regressions remain green.

## Handoff workflow
Copilot owns the decision and scope. Claude Code CLI owns implementation and executable validation. Copilot reviews the result before any broader multiplayer work.
