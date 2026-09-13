# Slice 025: Schema v3 organic vocabulary in the starting town

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city) and extends
[F-017](../FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points)
(schema) and [F-018](../FEATURE-LIST.md#f-018-client-side-sector-geometry-translation)
(geometry). Planning ticket: [Organic LLM Village map](../../.scratch/organic-village/map.md)
(Q3 vocabulary decision).

## SDD

Goal: Make the starting town read like an organic town rather than a gray
grid — paved plaza, path avenues, a gated wall, a grass border, an ornamental
pond, and flavor buildings (church, tavern, item shop, well) — by adding a
schema-versioned organic vocabulary and using it in the hub fixture. Cheap now
that Slice 024 decoupled tile count from physics bodies.

Public seams:

- `shared/sector_blueprint_schema.gd` — `SUPPORTED_SCHEMA_VERSIONS` gains `3`.
  New tile kinds `path/plaza/gate/water/grass` and structure kinds
  `church/item_shop/tavern/well` are added to the supported sets but
  **version-gated**: `_ORGANIC_TILE_KINDS` / `_ORGANIC_STRUCTURE_KINDS` require
  `schema_version >= ORGANIC_VOCABULARY_MIN_VERSION` (3). `schema_version` is now
  threaded into `_validate_tile` and `_validate_structures`/`_validate_structure`
  so a v1/v2 blueprint using an organic kind is rejected as
  `OUTCOME_UNSUPPORTED_KIND` with a version-explaining detail. v1/v2 keep their
  original vocabulary and stay valid.
- `shared/sector_geometry_lookup.gd` — dimensions for the five organic ground
  kinds (flat walkable slabs sharing the floor footprint; none solid) and scene
  paths for the four new structures.
- `client/structures/{church,tavern,item_shop,well}.tscn` — four new placeholder
  prefabs following the existing facade pattern (StaticBody3D + BoxMesh +
  `FacadeProximity` Area3D), sized distinctly (church tallest, well smallest)
  for a sense of scale.
- `server/starting_town_hub_fixture.gd` — emits `schema_version` 3; `_tile_kind`
  now returns the organic vocabulary via pure predicates (`_is_boundary`,
  `_is_gate`, `_is_wall`, `_touches_wall`, `_in_pond`): a 3-wide southern `gate`,
  a central `plaza`, radial `path` avenues, a `grass` ring inside the wall, a
  small `water` pond, and `floor` elsewhere. Adds four organic structures
  (`church_01`, `tavern_01`, `item_shop_01`, `well_01`) to the existing 13, for
  17 total.

Behavior:

- The client renders one merged ground mesh per organic kind
  (`Ground_path`/`Ground_plaza`/`Ground_gate`/`Ground_grass`/`Ground_water`) via
  the Slice 024 pass, plus the four new structure prefabs, with no per-tile
  bodies.
- A v3 blueprint may use the organic vocabulary; a v1/v2 blueprint may not
  (fails closed).
- The required structures (10 houses + smithy + armor shop + inn) are unchanged;
  monsters still spawn outside the town.

Implementation decisions:

- **Version-gated vocabulary, not a free-for-all.** Per `CLAUDE.md`'s versioning
  law, new vocabulary belongs to a new schema version with compatibility tests,
  rather than silently widening the accepted kinds for all versions. This keeps
  `schema_version` a meaningful compatibility signal for the future LLM path.
- **Organic ground reuses the merged-mesh path.** All new tile kinds are
  non-solid flat slabs, so they flow through the Slice 024 per-kind merged
  `ArrayMesh` with zero new geometry code — distinct `Ground_<kind>` nodes leave
  room for a future material/texture pass to color them.
- **Hand-authored, deterministic layout.** The vocabulary is exercised by a
  pure-function tile classifier (no data table), keeping the town easy to reason
  about and a reliable fallback for the later LLM-generation slice.

## BDD

### Organic vocabulary is version-gated

Given a blueprint using an organic tile or structure kind
When it declares `schema_version` 3
Then it validates; when it declares version 1 or 2 it is rejected as
`OUTCOME_UNSUPPORTED_KIND`, and the original floor/wall/corridor +
house/smithy/armor_shop/inn vocabulary stays valid in v1/v2.

### The hub uses the organic vocabulary

Given the enriched hub fixture
When its blueprint is built
Then it is schema v3, validates as `OUTCOME_VALID`, contains at least one
gate/plaza/path/grass/water tile (and no corridor), and has exactly one each of
church/tavern/item_shop/well plus the unchanged 10 houses + smithy + armor_shop
+ inn (17 total).

### The organic town renders end to end

Given the hub blueprint replicated to a client
When it is rendered
Then a merged ground mesh exists for each organic kind, the four new structure
prefabs instantiate, and there is still exactly one merged `Walls` body and no
per-tile body.

## TDD

- `tests/unit/test_sector_blueprint_schema_v3.gd` (new, 8 tests) — v3 supported;
  each organic tile/structure kind valid in v3; organic kinds rejected below v3
  (version gate); base vocabulary still valid in v1/v2; unknown kind still
  rejected; mixed v3 payload valid.
- `tests/unit/test_starting_town_hub_fixture.gd` — updated to schema v3 and 17
  structures, plus `test_fixture_uses_the_organic_v3_vocabulary` (all five
  organic tile kinds present, corridor gone).
- `tests/unit/test_sector_geometry_lookup.gd` — the drift tests auto-cover the
  expanded kind sets; `test_structure_scene_paths_resolve_to_existing_files` now
  iterates all supported structure kinds (verifying the four new prefabs load);
  `test_organic_tile_kinds_are_visual_ground_slabs` added.
- `tests/integration/test_blueprint_replication.gd` — asserts the organic
  `Ground_*` meshes render for the real hub.

## Validation

- `godot --headless --check-only -s shared/sector_blueprint_schema.gd` /
  `shared/sector_geometry_lookup.gd` / `server/starting_town_hub_fixture.gd` →
  exit 0.
- Focused: `test_sector_blueprint_schema_v3` 8/8, `test_sector_blueprint_schema_v2`
  16/16, `test_starting_town_hub_fixture` 9/9, `test_sector_geometry_lookup` 9/9,
  `test_blueprint_replication` 4/4, `test_sector_blueprint_contract` 7/7 — all
  exit 0.
- Full suite `scripts/run_gut_validation.sh` → 20 scripts, 156/156 tests, 640
  assertions, exit 0. Only the known-expected fail-closed rejection diagnostics
  and the pre-existing benign headless dummy-renderer `Parameter "m" is null`
  lines remain (see Slice 024).

## Non-goals (this slice)

- No LLM generation — the vocabulary is exercised by the hand-authored fixture;
  LLM layout generation with a required-structure guarantee is the next slice.
- No materials/textures — organic ground kinds are distinct nodes but share the
  gray placeholder slab; per-kind coloring is a future pass.
- No player rescale, camera, or movement changes; flavor buildings vary in size
  but the player and controls are untouched.
- No water/gate gameplay semantics (swimming, gated access) — `water`/`gate` are
  visual/vocabulary only this slice.
- No persistence.
