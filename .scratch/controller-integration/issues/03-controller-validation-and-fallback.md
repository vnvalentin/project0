Type: grilling
Status: unclaimed
Blocked by: 01-controller-placeholder-boundary.md, 02-controller-action-contract.md

## Question

What validation evidence and fallback behavior are required for the controller placeholder to be accepted without physical controller coverage or platform-specific assumptions?

## Decision boundary

- Define the narrowest executable Godot/GUT checks for action-map presence, axis bounds, and unchanged keyboard behavior.
- Decide observable behavior for no controller, disconnect, reconnect, and unsupported device input.
- Define the acceptance evidence needed before handing the implementation to Claude Code.
- Keep runtime claims limited to the environments actually tested.
