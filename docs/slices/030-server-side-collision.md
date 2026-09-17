# Slice 030: Server-side wall and building collision
GitHub issue: #95

Tracker context: Phase 10 — Authoritative runtime and action input; adds
[F-027](../FEATURE-LIST.md#f-027-server-authoritative-movement-collision),
extends the movement authority of
[IP-001](../FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer),
and makes the village of
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city) physically
solid. Originating from the "is the village walkable?" review: the server owned
position by pure integration with *no collision*, so the player walked through
everything.

## SDD

Goal: Make walls and buildings solid — the server-authoritative movement must
keep the player out of wall tiles and building footprints (with wall-sliding),
so the village can actually be walked around in.

Public seams:

- `shared/sector_collision_map.gd` (`class_name SectorCollisionMap`,
  `RefCounted`) — built from a validated blueprint via `_init(blueprint)`. It
  precomputes a blocked grid-cell set: every `wall` tile, plus each structure's
  footprint (its anchor expanded by the per-kind half-extent). `is_blocked(cell)`
  answers solidity; `resolve_move(from, to)` returns a collision-resolved
  position using **axis-separated sliding** (if the destination cell is solid,
  try X-only then Z-only so the player slides along the wall; if both are
  blocked, stay put). Walkable ground kinds (floor/corridor/path/plaza/gate/
  grass/water) stay open. Pure and deterministic — no SceneTree.
- `shared/sector_geometry_lookup.gd` — adds `structure_footprint(kind) -> Vector2i`
  (per-kind collision half-extent in grid cells, mirroring each prefab's BoxMesh
  width/depth; e.g. a 3×3 house is `(1,1)`, the 5×7 village hall is `(2,3)`).
- `server/server_player_state.gd` — a new injected `_collision_map` and
  `set_collision_map()`; the authoritative movement integration now computes the
  desired step, then `position = collision_map.resolve_move(position, desired)`.
  With no map injected (tests/standalone) movement stays free — backward
  compatible.
- `server/server_main.gd` — builds `_town_collision` from the validated hub at
  boot (logging the solid-cell count) and injects it into every peer's
  `ServerPlayerState` on connect.

Behavior:

- The player is a point at grid-cell resolution: because `roundi(0.5) == 1`, a
  move that would round into a solid cell is rejected on that axis, so the
  player **stops with its centre on the solid cell's face** rather than inside
  it. Sub-cell/radius precision is a documented future refinement.
- The southern gate stays passable (it is a `gate` tile, not `wall`); the
  perimeter wall, the interior walls, and every building footprint are solid.
- Diagonal movement into a wall slides along it (one axis blocked, the other
  free).

Implementation decisions:

- **Grid-cell blocking from blueprint data.** The server has no rendered
  geometry, only the blueprint. Deriving solids from `wall` tiles + structure
  footprints keeps collision server-authoritative and needs no physics engine,
  and it is trivially unit-testable with plain Dictionaries.
- **Footprints live in the shared lookup.** The per-kind half-extents mirror the
  client prefab sizes and sit beside the scene-path/dimension tables, with a
  note to keep them in sync with `client/structures/<kind>.tscn`.
- **Point-at-cell, not a physics body.** Deterministic, cheap, and precise
  enough for placeholder box art (the player stops at the cell face). A
  radius/sub-cell pass can refine it later without changing the seam.
- **Injected, nullable.** `ServerPlayerState` takes the map by injection and
  treats `null` as free movement, so every existing movement test and the
  standalone/test path are unaffected.

## BDD

### Walls and buildings are solid

Given the hub collision map
When `is_blocked` is queried
Then wall tiles and every building-footprint cell are solid, while floor/path/
plaza/gate/grass/water are open, and the southern gate opening is passable.

### Authoritative movement is blocked

Given a `ServerPlayerState` with an injected collision map
When the player drives movement into a wall or building
Then the integrated position stops at the solid cell's face and never enters it;
with no map injected, movement is unchanged (free).

### Movement slides along walls

Given a diagonal move into a wall column
When it is resolved
Then the blocked axis is held while the free axis continues (the player slides).

## TDD

- `tests/unit/test_sector_collision_map.gd` (6) — wall/ground solidity, house
  footprint block, free move in open space, stop-at-wall-face, slide-along-wall,
  and the real hub (gate passable, perimeter wall solid).
- `tests/unit/test_server_player_state_collision.gd` (4) — free movement without
  a map; blocked by a wall (stops at the face); blocked by a building footprint;
  slides diagonally along a tall wall. Drives the real
  `ServerPlayerState._physics_process` (the `CONNECTION_CONNECTED` RPC guard
  makes that safe with no live server).
- `tests/unit/test_sector_geometry_lookup.gd` — `structure_footprint` defined for
  every kind, with the house/village_hall/unknown values checked.

## Validation

- Parse-check the four edited/new scripts → exit 0.
- Focused: `test_sector_collision_map` 6/6, `test_server_player_state_collision`
  4/4, `test_sector_geometry_lookup` 10/10 — exit 0.
- Full suite `scripts/run_gut_validation.sh` → 24 scripts, 188/188 tests, 777
  assertions, exit 0. Only the known-expected fail-closed rejection diagnostics
  and the pre-existing benign headless `Parameter "m" is null` lines remain.
- Live confirmation (player physically blocked in a running client) requires a
  server restart to pick up this code, then a client walk — not yet performed.

## Non-goals (this slice)

- No sub-cell/radius precision (the player is a point that stops at the cell
  face; box art overlaps by up to half a cell). A radius pass is future work.
- No vertical/height collision, ramps, doors, or enterable interiors (facades
  stay enter/exit-only).
- Water and grass remain walkable (only walls and buildings are solid).
- No client-side prediction of collision — the client still renders the
  authoritative position; prediction may briefly show a corrected overlap.
- No monster-vs-geometry collision (monsters roam the open fields).
