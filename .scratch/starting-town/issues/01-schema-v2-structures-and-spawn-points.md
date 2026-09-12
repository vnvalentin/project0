Type: grilling
Status: resolved

## Question

What exact fields and entity-kind vocabulary does sector blueprint schema
version 2 need to represent building placements (house / smithy / armor_shop
/ inn) and monster spawn markers, while preserving version 1's fail-closed,
bounded validation style (see `shared/sector_blueprint_schema.gd`:
`CURRENT_SCHEMA_VERSION`, `SUPPORTED_TILE_KINDS`, `MAX_TILE_COUNT`,
`MAX_COORDINATE_ABS`)?

Sub-questions to resolve here:
- Is a "structure" a new top-level array (`structures: [...]`) alongside
  `tiles`, or a new tile `kind` value reusing the existing `tiles` array?
- What per-structure fields are required (e.g. `structure_id`, `kind`,
  position, facing/orientation, a bounded footprint size)?
- Is a monster spawn point its own array (`spawn_points: [...]`) with a
  bounded max count, separate from structures?
- How does `schema_version = 2` reject a `schema_version = 1` payload (and
  vice versa) under the existing `OUTCOME_WRONG_SCHEMA_VERSION` contract —
  does v1 stay supported for non-town sectors, or is v2 a hard replacement?

## Answer

- **Canonical term**: **Structure** (not "building" — kept neutral so a
  future non-building placeable, e.g. a well or gate, can reuse the same
  shape). Recorded in `CONTEXT.md`.
- **Shape**: a new top-level `structures: [...]` array, separate from
  `tiles`. Each entry:
  `{ "structure_id": String (non-empty, unique within sector), "kind": String
  (bounded by a new SUPPORTED_STRUCTURE_KINDS allowlist: "house", "smithy",
  "armor_shop", "inn"), "x": int, "y": int (bounded like tile coordinates via
  MAX_COORDINATE_ABS), "facing_degrees": number (bounded [0, 360)) }`. No
  footprint/size field — a fixed-size prefab per `kind` (decided by ticket 02)
  is sufficient since ticket 04 already scoped structures to facades with no
  interior.
- **Spawn points**: a separate `spawn_points: [...]` array (not a kind of
  Structure — not rendered/enterable, and conflating fields would leak
  monster-only concerns into building validation). Each entry:
  `{ "spawn_id": String, "x": int, "y": int }`. Monster archetype/kind is
  deliberately deferred to the Basic Monsters map. Bounded by a new
  `MAX_SPAWN_POINT_COUNT` constant (exact value, e.g. 16, tuned at
  implementation time, not decided here).
- **Version transition**: v1 and v2 are both accepted going forward —
  `CURRENT_SCHEMA_VERSION`-style validation becomes a supported-set/range
  check rather than strict equality. Ordinary non-town sectors keep
  generating tiles-only v1 payloads (empty/absent `structures`/
  `spawn_points`); only town-like sectors need v2's new arrays. Wrong/
  unsupported versions outside the accepted set still reject via
  `OUTCOME_WRONG_SCHEMA_VERSION`.
