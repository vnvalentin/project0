Type: task
Status: unclaimed
Blocked by: 02, 07, 08

## Question
What is the smallest client-presentation layer that makes the current login, connection, flat-plane, and Player interaction visibly understandable in a real Godot window without adding world content or changing network behavior?

## Decision boundary
- Improve only the identity gate and gameplay presentation.
- Show a clear project title, name-entry state, connection state, movement hint, and a simple local/networked Player legend.
- Keep the flat plane, fixed 3/4 camera, red local Player, and blue networked Player.
- Use Godot-native UI and materials; no production art pipeline or external assets.
- Do not change movement, networking, server authority, persistence, or world systems.
- Keep the UI usable at ordinary desktop window sizes and preserve headless scene validation.

## Handoff workflow
Copilot owns this presentation scope. Claude Code CLI may edit only the client presentation scenes/scripts named in the handoff, then returns visual/runtime validation. Copilot reviews before the next UI or gameplay slice.
