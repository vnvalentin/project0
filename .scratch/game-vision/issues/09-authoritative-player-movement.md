Type: task
Status: unclaimed
Blocked by: 01, 02, 07, 08

## Question
What is the smallest server-authoritative movement slice that lets the connected client send WASD intent to the Linux server, lets the server update one player's position, and displays that authoritative position in the blue networked Player representation without adding prediction, interpolation, persistence, authentication, reconnect, or a full multiplayer authority model?

## Decision boundary
- Client sends directional input intent only; it does not send a requested position.
- Server owns the networked Player position and applies a fixed movement speed per server tick.
- Server sends the resulting position back to the owning client.
- The blue networked Player displays the authoritative result; the existing red local Player remains unchanged for regression compatibility in this slice.
- No client prediction, reconciliation, interpolation, remote-player replication, collision authority, anti-cheat policy, or persistence is included yet.

## Handoff workflow
Copilot owns scope and acceptance criteria. Claude Code CLI owns implementation and executable validation. Copilot reviews the result before the next networking decision.
