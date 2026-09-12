Type: grilling
Status: resolved

## Question

Each connecting player gets their own unique house at a unique position in
the starting town (user decision, 2026-09-12). Given house ownership is
session-scoped only (no save/persistence system exists yet — see
`client/player_identity.gd`), how are house slots modeled and allocated:
- Is the town's blueprint authored/generated with a fixed pool of N house
  structure entities (bounded, matching `MAX_TILE_COUNT`-style caps), or does
  the schema need to support a variable/growing count of houses?
- What happens when the Nth+1 player connects and no house slot remains?
- On disconnect, does the house slot immediately free for reuse, or stay
  reserved for a return within the same session per the "Not yet specified"
  reconnect question on the map?

## Answer

- **Pool size**: fixed at **10** house Structures baked into the hub fixture
  (ticket 03), matching the server's existing 10-player max. No dynamic
  growth — the fixture is static data.
- **Over-capacity**: unreachable in steady state since max players is already
  10; house allocation adds only a defensive fail-closed fallback (reject +
  log, never crash or double-assign) in case that invariant is ever violated
  elsewhere.
- **Disconnect**: house slot frees **immediately**, first-available
  reassignment for the next connecting player. No reservation window — there
  is no identity/session system yet to reliably recognize "the same player
  reconnecting" (this map's persistence dependency is explicitly out of
  scope), so reserving would just leak allocations as players churn. This
  resolves the map's earlier reconnect fog note.

