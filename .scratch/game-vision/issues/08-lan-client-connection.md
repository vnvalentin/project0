Type: task
Status: unclaimed
Blocked by: 01, 02, 07

## Question
What is the smallest safe change that lets the Windows Godot client connect to the Linux Godot server over the local network while preserving the existing flat-plane visualization and avoiding movement synchronization, prediction, persistence, authentication, or deployment automation?

## Decision boundary
- Make the server bind address and client target host configurable without hard-coding a workstation-specific IP.
- Preserve localhost as the default for existing smoke tests.
- Permit an operator to bind the server to a LAN-reachable interface and provide the Linux server's LAN address to the Windows client.
- Keep the existing ENet port and visible connection status/player spawn behavior.
- Document the exact two-machine run procedure and the network exposure warning.

## Handoff workflow
Copilot owns the scope and acceptance criteria. Claude Code CLI owns implementation and executable validation. Copilot reviews the changed files and fresh smoke-test output before planning movement synchronization.
