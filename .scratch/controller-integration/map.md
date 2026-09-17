## Destination

Produce a validated, handoff-ready plan for a controller integration placeholder in the Godot client: preserve keyboard/mouse behavior, route supported controller input through the existing named actions, and define the smallest safe implementation seam without changing server authority or network contracts.

The map is complete when the supported controller scope, action contract, fallback behavior, and executable validation evidence are clear enough to create an implementation ticket safely.

## What Good Looks Like

- [ ] Supported controller families and connection states are decided for the first placeholder.
- [ ] Controller input maps to the existing named actions without changing server authority or network contracts.
- [ ] Keyboard/mouse behavior remains unchanged and fallback/disconnect behavior is specified.
- [ ] A realistic validation path exists for the first controller implementation slice.

## Notes

- Domain: Godot 4 client input, networked movement and action presentation, GDScript 2.0 strict typing.
- Existing seam: `client/player.gd` reads named `InputMap` actions; `project.godot` currently defines keyboard/mouse bindings for movement and attack.
- Planning mode: this map produces decisions and implementation-ready handoff material only. It does not add controller bindings or product code.
- Safety boundary: controller input may produce the same client intents as existing input devices, but it must not add client authority or bypass server validation.
- Tracker: local Markdown issues under `.scratch/controller-integration/issues/`.
- Consult the `grilling` and `domain-modeling` skills for each decision ticket.

## Decisions so far

## Not yet specified

- Which controller families and connection states are in scope for the first placeholder.
- Whether the placeholder includes only movement and attack parity or also menu navigation, prompts, rebinding, vibration, and device-specific glyphs.
- The dead-zone, axis normalization, conflict resolution, disconnect, and reconnect behavior needed once the boundary is chosen.
- The level of physical-device or automated validation available for the first implementation slice.

## Out of scope

- Replacing Godot's input system or introducing a third-party input library.
- Server protocol changes, new authoritative actions, persistence, matchmaking, or authentication.
- Final controller UX, platform certification, accessibility review, vibration design, and production device coverage.
