Type: grilling
Status: resolved

## Question

How does a monster entity get instantiated from a validated sector
blueprint's spawn-point entities (exact format decided by the sibling
Starting Town map's schema-v2 ticket) into this map's monster state machine —
including a bounded max-concurrent-monster-count safeguard consistent with
`SectorBlueprintSchema.MAX_TILE_COUNT`-style bounds?

## Answer

- **Instantiation**: 1:1 mapping, one Monster per `spawn_point` entry, at
  server boot alongside the hub fixture's materialization (Starting Town
  ticket 03) — monsters are just another entity type read from that same
  static fixture, not a separately triggered system.
- **Death and respawn (revised per user direction — no permanent removal)**:
  a Monster's death starts a fixed `RESPAWN_COOLDOWN_TICKS` cooldown for its
  spawn point. When it elapses, a fresh full-HP Monster (same archetype)
  respawns at a **randomized position within a bounded area around the spawn
  point** (a new `RESPAWN_AREA_RADIUS_METERS` constant), not the exact same
  coordinate every time. The respawn emits a structured telemetry event
  (`spawn_id`, server tick, cooldown/radius values in effect), consistent
  with this map's telemetry-first standing requirement.
- **Max-concurrent-count safeguard**: reuses Starting Town ticket 01's
  `MAX_SPAWN_POINT_COUNT` bound per-sector — no separate global cap. A
  cross-sector combined cap is speculative today since only the hub sector
  generates spawn points; add one when a second spawn-bearing sector is
  actually scoped.
- **Surfaced but deferred (not decided here)**: the user raised a future
  "monster spawner" concept — a visible, destructible generator object
  (Gauntlet-style) that would own/control respawn instead of an invisible
  per-spawn-point timer. That's a distinct future decision (new entity kind,
  destruction rules, possibly its own HP) and is recorded in the map's Not
  yet specified rather than decided as part of this ticket.
