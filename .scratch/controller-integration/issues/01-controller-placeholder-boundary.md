Type: grilling
Status: unclaimed

## Question

What is the smallest controller integration placeholder that is useful to the current client while preserving existing keyboard/mouse behavior and the server-authoritative input boundary?

## Decision boundary

- Decide the first supported device class and connection assumptions.
- Decide which existing named actions must have controller bindings in the placeholder.
- Keep the scope at the Godot client input/presentation boundary.
- Exclude server protocol changes, persistence, rebinding UI, vibration, final prompts, and platform certification unless the decision shows one is required for a safe placeholder.
