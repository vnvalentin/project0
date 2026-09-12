Type: grilling
Status: claimed
Blocked by: 01

## Question
What is the smallest playable vertical slice that proves the core game direction while avoiding premature commitment to the full persistent LLM-generated world?

## User direction
The first playable slice is intentionally minimal: a player can log in or pass a local identity gate, enter a scene containing only a flat plane, and move around it. There is no map, generated world, world save, quest system, or LLM integration in this slice.

Implementation remains blocked until the repository foundation gate is closed.

## Planning and handoff workflow
Copilot resolves this ticket and writes the implementation brief. Claude Code CLI implements only that brief after the foundation gate is closed. Copilot then reviews the changed files and fresh validation output before another slice is planned.

## Required handoff contents
- User-visible outcome: login/local identity gate leads to a flat-plane movement scene.
- Public seam: the Godot project entry scene and the player movement input path.
- Non-goals: map, generated world, world save, quests, Ollama, SQLite canon, multiplayer prediction, and production art.
- Safety invariant: no persistent world data or external service calls are introduced by this slice.
- Validation: an exact Godot headless or editor command that proves the project parses and the scene can start.

## Decisions from first grilling round
- Login is a mock username/password gate only; it has no account backend and does not persist credentials.
- The movement scene uses a Zelda-like fixed 3/4 top-down camera over a flat 3D plane.
- The first movement input is keyboard WASD only.
