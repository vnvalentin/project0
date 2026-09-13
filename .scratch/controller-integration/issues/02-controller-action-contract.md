Type: grilling
Status: unclaimed
Blocked by: 01-controller-placeholder-boundary.md

## Question

Given the chosen placeholder boundary, how should controller axes, buttons, dead zones, and action aliases map onto the existing `InputMap` actions so movement, attack, prediction, and reconciliation retain identical public seams?

## Decision boundary

- Decide digital-versus-analog semantics and normalization for `move_forward`, `move_back`, `move_left`, and `move_right`.
- Decide the first controller action for the existing `attack` input.
- Preserve the existing client-to-server intent shape and authoritative resolution.
- Leave menu navigation, rebinding, glyphs, vibration, and additional actions out unless they are necessary to avoid an ambiguous contract.
