Type: task
Status: resolved
Blocked by: 09, 11

## Question
What is the smallest multi-peer gameplay slice that lets two packaged or editor Windows clients connect to the Linux server, see distinct Player representations, and observe each other's server-authoritative movement without adding persistence, authentication, matchmaking, or generated world content?

## Decision boundary
- Support exactly two connected clients for the first multi-peer proof.
- Assign each peer a distinct Player representation and ownership.
- Replicate authoritative positions so each client sees the other Player move.
- Preserve local prediction/reconciliation for each owning client.
- Clean up a disconnected Player representation on both remaining clients.
- Keep localhost/LAN configuration and the portable client package unchanged.

## Non-goals
- Matchmaking, authentication, reconnect, persistence, world generation, quests,
  Ollama, SQLite, Docker, production anti-cheat, and arbitrary player counts.

## Acceptance evidence
- Two real client processes connect to one Linux server.
- Both clients see two distinct Player representations.
- Movement from Client A appears on Client B and vice versa through server authority.
- Disconnect cleanup removes the departed Player without crashing the remaining client.
- Slices 001 through 006 remain green.

## Handoff workflow
Copilot owns the decision and acceptance criteria. Claude Code CLI owns the bounded implementation and executable validation. Copilot reviews the two-client runtime result before planning beyond two peers.

## Answer

The user confirmed the physical two-window Windows client run: two clients
connected to the Linux server simultaneously and displayed two distinct Player
representations. This validates the multi-peer connection/visual path. The
headless Slice 007 smoke test also covers bidirectional authoritative movement
and disconnect cleanup. Future work is limited to broader peer counts,
authentication, reconnect, and production multiplayer hardening.
