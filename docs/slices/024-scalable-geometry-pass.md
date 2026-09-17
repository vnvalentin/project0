# Slice 024: Scalable geometry pass (merged ground mesh + merged wall colliders)
GitHub issue: #95

Tracker context: Phase 8 — JIT world generation and local inference; remediates
[DT-008](../TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-does-not-scale-to-city-size)
and evolves [F-018](../FEATURE-LIST.md#f-018-client-side-sector-geometry-translation),
unblocking the scale destination of
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city).
Planning ticket: [Organic LLM Village map](../../.scratch/organic-village/map.md)
(the geometry-pass half of its Slice 024 item).

## SDD

Goal: Replace the one-`StaticBody3D`-per-tile translation strategy — which does
not scale to city size (DT-008) — with a merged pass so the whole town renders
with a single physics body and a handful of meshes, independent of tile count.
No schema-vocabulary or gameplay change.

Public seams:

- `client/sector_geometry_translator.gd` (`SectorGeometryTranslator.translate`)
  — same signature, new strategy:
  - **Ground (floor/corridor):** all tiles of a non-solid kind are combined into
    ONE merged `ArrayMesh` rendered by a single `MeshInstance3D` named
    `Ground_<kind>` (one draw call per kind, NO physics body). The Gameplay
    `FlatPlane` remains the walkable collision surface, so the old per-tile floor
    colliders were redundant.
  - **Walls (solid):** contiguous horizontal runs of wall tiles are greedy-merged
    per row into box colliders + meshes under a single shared `Walls`
    `StaticBody3D` (a wall of N tiles becomes a handful of colliders on ONE body
    instead of N bodies).
  - **Structures:** unchanged — one prefab instance each (`Structure_<id>`).
- `shared/sector_geometry_lookup.gd` — adds `tile_is_solid(kind)` (wall is solid;
  floor/corridor are visual ground) so the translator classifies tiles without
  hard-coding kind strings.

Behavior:

- A floor-only sector of any size produces **zero physics bodies** (one merged
  `ArrayMesh`).
- A row of N contiguous wall tiles produces **one** merged collider spanning the
  run; separated runs in the same row produce one collider each.
- The starting town (~869 tiles) renders with **one** `StaticBody3D` (`Walls`)
  plus per-kind ground meshes plus the 13 structure instances — versus ~869
  `StaticBody3D` before.

Implementation decisions:

- **`ArrayMesh` (static batching) over `MultiMesh` for ground.** Town ground is
  static and identical per kind; a single merged `ArrayMesh` is the textbook
  static-batching answer (one draw call, no per-instance transform storage) and
  uses the same `MeshInstance3D` + `Mesh` node type the rest of the client uses.
  The base unit-box surface arrays are cached per kind
  (`_ground_base_arrays_cache`) and reused to build each sector's mesh.
- **Greedy horizontal wall-run merge.** Per row, consecutive wall x-cells merge
  into one box collider. This eliminates the dominant per-tile body cost while
  staying simple and deterministic. Merging vertical/2-D runs further (to shrink
  the collision-shape count on vertical wall columns) is a possible future
  optimization; it is not required to resolve DT-008's body-count concern, since
  every wall tile now shares ONE body regardless.
- **Ground is visual-only.** Collision for walking is the existing `FlatPlane`;
  the merged ground carries no colliders. Walls keep collision.

## BDD

### Ground renders as merged meshes with no bodies

Given a sector with floor/corridor tiles
When it is translated
Then each non-solid kind becomes one `Ground_<kind>` `MeshInstance3D` (a single
merged `ArrayMesh` surface) and no floor/corridor physics body is created.

### Walls merge into one body

Given a sector with wall tiles
When it is translated
Then all walls live under one `Walls` `StaticBody3D`, and each contiguous
horizontal run is a single merged box collider (5 contiguous tiles → 1 collider;
two separated runs in a row → 2 colliders).

### The whole town uses one physics body

Given the real starting town hub blueprint
When it is replicated and rendered at the client
Then it produces exactly ONE `StaticBody3D` (`Walls`), per-kind ground meshes,
and one instance per structure — never one body per tile — and no legacy
`Tile_*` node remains.

## TDD

- `tests/unit/test_sector_geometry_lookup.gd` — adds
  `test_wall_is_solid_and_ground_kinds_are_not` (wall solid; floor/corridor and
  unsupported kinds not solid).
- `tests/integration/test_sector_geometry_translation.gd` — rewritten for the
  merged strategy: ground renders as per-kind merged `ArrayMesh` `MeshInstance3D`
  with no collider children (AABB-verified extent), walls render as merged
  colliders taller than the ground, the container-children count excludes
  per-tile bodies, plus new scale-proof tests
  (`test_floor_only_sector_produces_zero_physics_bodies`,
  `test_contiguous_wall_run_merges_into_one_collider`,
  `test_gapped_wall_tiles_in_a_row_merge_into_separate_colliders`).
- `tests/integration/test_blueprint_replication.gd` — updated to assert the hub
  renders with one merged `Walls` body, merged `Ground_*` meshes, all structures,
  and no `Tile_*` nodes.

## Validation

- `godot --headless --check-only -s client/sector_geometry_translator.gd` → exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
  -gselect=test_sector_geometry_translation -gexit` → 8/8 tests, 35 assertions,
  exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
  -gselect=test_blueprint_replication -gexit` → 4/4 tests, 35 assertions, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_sector_geometry_lookup -gexit` → 8/8 tests, exit 0.
- `scripts/run_gut_validation.sh` → 19 scripts, 146/146 tests, 558 assertions,
  exit 0; `build/validation/gut.xml` refreshed.

Known-benign diagnostic: the full run prints a small number of
`ERROR: Parameter "m" is null.` lines from Godot's headless *dummy* renderer
(`mesh_get_surface_count`, `servers/rendering/dummy/storage/mesh_storage.h`)
during physics-frame node teardown. This is a **pre-existing** headless-only
artifact — the unchanged `tests/integration/test_facade_enter_exit.gd` also
emits it — not a Slice 024 regression and not a functional error (all 146 tests
pass, exit 0). It does not occur under a real (non-dummy) renderer, which is
where this client code runs in production.

## Non-goals (this slice)

- No new schema vocabulary or structure kinds (schema v3 is a later slice).
- No building/player rescale.
- No LLM generation.
- No further (vertical/2-D) wall-collider merge beyond horizontal runs.
- No material/texture work; ground and walls stay untextured placeholder boxes.
