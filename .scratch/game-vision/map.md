## Destination
Produce a validated handoff-ready plan for a networked Godot 4 3D 3/4-view action-adventure with a server-authoritative multiplayer model, local Ollama-driven JIT world generation, and persistent SQLite canonical world state.

The map is complete when the product boundary, first playable slice, networking contract, generation blueprint, canon persistence model, and deployment boundaries are decided well enough for implementation tickets to be created safely.

## Notes
- Domain: game architecture, multiplayer simulation, Godot 4, GDScript 2.0 strict typing, local Ollama inference, Docker-hosted headless server, SQLite persistence.
- Standing constraints: Windows workstation is the visual client/editor environment; Linux is the authoritative host; Ollama runs locally on the Tesla P100; generated sectors become canonical only after server validation and persistence.
- Planning mode: this Wayfinder effort produces decisions and implementation-ready handoff material. It does not create product code while the foundation gate is open.
- Tracker: local markdown issues under `.scratch/game-vision/issues/`.
- Delivery workflow: Copilot owns grilling, domain decisions, scope, acceptance criteria, and the implementation handoff. Claude Code CLI owns the subsequent code edits and executable validation. Copilot reviews the CLI result against the handoff before the next planning decision.
- Handoff rule: no Claude Code implementation session starts until the relevant ticket has a recorded decision, public seam, non-goals, safety invariants, validation command, and explicit handoff brief.

## Decisions so far

- [Windows client package](.scratch/game-vision/issues/12-windows-client-package.md): a portable Windows export was produced and launched outside the editor/source share, then connected over LAN; installer, signing, and auto-update remain out of scope.

## Not yet specified
- The smallest first playable slice that proves the player experience without prematurely building the full generated world.
- The authoritative boundary between client input/prediction and server simulation/replication.
- The JSON blueprint schema, validation policy, retry/fallback behavior, and determinism expectations for Ollama-generated sectors.
- The SQLite schema and transaction boundary that turns generated sectors into immutable-or-event-mutated canon.
- The Docker, GPU, Ollama, Remote-SSH, and Windows-client development boundary and its runtime validation.
- The exact format for reporting Claude Code implementation results back into the relevant slice record.
- The first networked connection proof: a headless Godot server, one ENet client, and a visible connected Player on the flat plane.
- The smallest safe LAN configuration for the Windows client to reach the Linux server without changing gameplay authority.
- The smallest server-authoritative movement proof for one connected Player.
- The smallest prediction, reconciliation, and authoritative snapshot smoothing proof for that Player.
- The smallest distributable Windows client package that lets testers run the client without the editor or source share.
- The smallest two-client replication proof for distinct authoritative Players and disconnect cleanup.

## Out of scope
- Training or fine-tuning an LLM.
- Cloud-hosted inference or cloud-owned canonical world state.
- Final art production, full quest content, and production-scale world balancing.
- Implementation code before the foundation gate is closed.
- Unplanned implementation by Copilot inside a planning session.
- Client prediction, interpolation, synchronized movement, reconnect, and remote deployment in the first connection proof.
- Internet exposure, authentication, firewall automation, and production deployment in the LAN connection slice.
- Client prediction, reconciliation, interpolation, remote-player replication, and persistent movement state in the first authoritative movement slice.
- Remote-player replication, persistence, reconnect, and production anti-cheat policy in the prediction slice.
- Installer technology, auto-update, code signing, public distribution, matchmaking, and production authentication in the first package slice.
