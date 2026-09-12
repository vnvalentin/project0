# Slice 015: Client-side sector geometry translation

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-018](../FEATURE-LIST.md#f-018-client-side-sector-geometry-translation).
Planning tickets: [Starting Town map](../../.scratch/starting-town/map.md),
[issue 02 — Geometry translation strategy](../../.scratch/starting-town/issues/02-geometry-translation-strategy.md)
(resolved). Consumes the schema this slice's prior slice validated:
[Slice 014 — Sector blueprint schema v2](014-sector-blueprint-schema-v2-structures.md).

## SDD

Goal: Translate an already-validated sector blueprint Dictionary (the shape
returned by `SectorBlueprintSchema.validate()`, schema v1 or v2) into 3D scene
geometry on the client, entirely client-side, with no network transport,
gameplay authority, or persistence work. Per resolved ticket 02: tiles become
procedural per-kind boxes extending the existing `FlatPlane`/`BoxMesh` pattern;
structures become authored per-kind placeholder prefab scenes instanced the
same way `client/target_dummy.tscn` is instanced in `client/gameplay.tscn`.

Public seams:

- `shared/sector_geometry_lookup.gd` — pure `RefCounted` lookup helper, no
  scene-tree/rendering/Node dependency. Maps tile `kind` (`"floor"`, `"wall"`,
  `"corridor"`) to mesh/collision box dimensions (`Vector3`), and structure
  `kind` (`"house"`, `"smithy"`, `"armor_shop"`, `"inn"`) to a `PackedScene`
  resource path (`String`). Unsupported kinds return an explicit failure
  marker rather than a guessed default, matching this repo's fail-closed
  convention. Unit-testable with plain Dictionary/String fixtures.
- `client/sector_geometry_translator.gd` — client-side translator. Takes an
  already-validated blueprint `Dictionary` and a parent `Node3D`, and
  instantiates one `StaticBody3D` + `MeshInstance3D` + `CollisionShape3D` per
  tile entry (procedural boxes built from `SectorGeometryLookup` dimensions,
  positioned at the tile's grid `x`/`y`) and one `PackedScene.instantiate()`
  per structure entry (positioned/rotated from `x`, `y`, `facing_degrees`
  converted to a `Transform3D`), all parented under the given `Node3D`. Does
  not validate the blueprint itself — the caller is responsible for only
  passing a Dictionary that already passed `SectorBlueprintSchema.validate()`.
- `client/structures/house.tscn`, `client/structures/smithy.tscn`,
  `client/structures/armor_shop.tscn`, `client/structures/inn.tscn` — minimal
  placeholder structure scenes (`StaticBody3D` + `BoxMesh` +
  `CollisionShape3D` + a distinct `StandardMaterial3D` albedo color each),
  following the same placeholder-art convention as `FlatPlane`, `Player`, and
  `TargetDummy` in `client/gameplay.tscn`.
- `tests/unit/test_sector_geometry_lookup.gd` — fast unit tests for the pure
  lookup helper (Dictionary/String fixtures only, no scene tree).
- `tests/integration/test_sector_geometry_translation.gd` — GUT integration
  test that runs the translator against a fixture blueprint inside a real
  `SceneTree`/`Node3D`, asserting expected child node count/types/positions.

Safety invariant: this slice performs no network I/O, no gameplay-state
mutation, and no Canon/SQLite work. It assumes a validated blueprint Dictionary
is already in the caller's hand (e.g. a test fixture or a future caller); it
does not implement how that Dictionary reaches the client over the network,
does not materialize the hub sector fixture at server boot, does not add
facade proximity-trigger/enter-exit UI behavior, does not allocate player
houses, and does not instantiate monsters/spawn points.

Implementation decisions:

- `SectorGeometryLookup` is `RefCounted`, not a `Node`, so it carries no
  scene-tree dependency and is directly constructible/callable from a plain
  GUT unit test. It exposes static lookup functions (mirroring
  `SectorBlueprintSchema`'s static-function style) rather than instance state,
  since the mapping tables are fixed data, not per-call state.
- Wall tiles get a taller box (extends upward) than floor/corridor tiles,
  matching ticket 02's decision that walls must read as taller than
  floor/corridor at a glance even as placeholder geometry. Floor and corridor
  share the same thin slab dimensions as the existing `FlatPlane` pattern
  (`BoxMesh`/`BoxShape3D` sized `(1, 0.2, 1)` per grid cell) since neither
  ticket 01 nor 02 distinguishes their traversal geometry.
  `SectorBlueprintSchema.SUPPORTED_TILE_KINDS` and
  `SUPPORTED_STRUCTURE_KINDS` are the single source of truth for which kinds
  exist; `SectorGeometryLookup`'s tables are asserted (via unit test) to cover
  exactly those sets so the two files cannot silently drift.
- Unsupported tile/structure kinds return a null/empty result from the lookup
  helper rather than throwing or asserting, so a caller can decide how to
  fail closed (log + skip, in the translator's case) without a runtime crash
  taking down the whole translation pass mid-sector. This mirrors this slice's
  assumption that the input already passed schema validation — reaching an
  unsupported kind here would indicate a schema/lookup drift bug, not
  untrusted network input, so the translator logs and skips that single
  entry rather than failing the whole sector.
- The translator names each instantiated tile node
  `Tile_<kind>_<x>_<y>` and each structure node `Structure_<structure_id>`,
  so tests and future callers (e.g. a future facade `Area3D` slice) can find
  a specific node deterministically instead of relying on child order.
- `facing_degrees` converts to a `Transform3D` via `Basis.from_euler` around
  the Y axis (`deg_to_rad(facing_degrees)`), consistent with how
  `client/player.gd` already derives a facing `Basis` from a direction/angle.
- Placeholder structure scenes reuse the flat, single-`StaticBody3D`-node
  shape already established by `client/target_dummy.tscn`, differing only in
  mesh/collision box size and a distinct `StandardMaterial3D.albedo_color` per
  kind, matching CLAUDE.md's "do not attempt real art" instruction and this
  repo's existing placeholder-art convention.
- No new ADR: this slice adds a rendering/presentation seam entirely on the
  client side, introduces no new authority boundary, and does not change
  which process owns any world-state decision (CLAUDE.md's Runtime Ownership
  and ADR 0002 already establish that geometry translation is client-only,
  disposable presentation).

## BDD

### Valid blueprint tiles translate to procedural boxes

Given an already-validated blueprint Dictionary with one `floor`, one `wall`,
and one `corridor` tile at distinct grid positions
When `SectorGeometryTranslator` translates it under a parent `Node3D`
Then the parent gains one `StaticBody3D` per tile, each with a
`MeshInstance3D` and `CollisionShape3D` sized per `SectorGeometryLookup`,
positioned at the tile's grid `x`/`y`, and the wall tile's box is taller than
the floor/corridor boxes.

### Valid blueprint structures translate to placeholder prefabs

Given an already-validated blueprint Dictionary with one structure of each
supported kind (`house`, `smithy`, `armor_shop`, `inn`) at distinct
`x`/`y`/`facing_degrees`
When `SectorGeometryTranslator` translates it under a parent `Node3D`
Then the parent gains one instantiated node per structure, each loaded from
that kind's `PackedScene` path, positioned at the structure's `x`/`y` and
rotated to match `facing_degrees`.

### Unsupported kind does not crash translation

Given a lookup request for a tile or structure `kind` outside
`SectorBlueprintSchema`'s supported sets
When `SectorGeometryLookup` is queried directly, or when the translator
encounters such an entry
Then the lookup returns an explicit failure/empty result and the translator
skips only that entry, leaving every other valid entry translated.

### Pure lookup helper needs no scene tree

Given plain Dictionary/String fixtures naming a tile or structure kind
When `SectorGeometryLookup`'s static functions are called directly in a unit
test
Then they return the expected dimensions or scene path without instancing any
Node or requiring a `SceneTree`.

## TDD evidence

`tests/unit/test_sector_geometry_lookup.gd` exercises `SectorGeometryLookup`
directly with plain Dictionary/String fixtures: dimensions for each supported
tile kind (asserting the wall box is taller than floor/corridor), scene paths
for each supported structure kind (asserting each resolved path exists on
disk), and explicit failure/empty results for unsupported tile and structure
kinds, plus a coverage assertion that the lookup's supported kind sets exactly
match `SectorBlueprintSchema.SUPPORTED_TILE_KINDS` /
`SUPPORTED_STRUCTURE_KINDS`.

`tests/integration/test_sector_geometry_translation.gd` runs
`SectorGeometryTranslator` against a fixture blueprint Dictionary (one of each
tile kind, one of each structure kind) parented under a real `Node3D` added to
the test's scene tree, and asserts: total child count, per-tile node
type/shape/position, the wall-vs-floor height difference, per-structure node
presence/position/rotation, and that every structure scene actually
instantiates (no missing/broken `PackedScene` path).

## ADR decision

No new ADR. See "Implementation decisions" above for the rationale — this
slice is a client-only presentation seam consuming an already-validated
contract; it introduces no new authority, ownership, or persistence boundary
beyond what CLAUDE.md and ADR 0002 already establish.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_sector_geometry_lookup -gexit`: PASS, 7/7 tests, 22
  assertions, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
  -gselect=test_sector_geometry_translation -gexit`: PASS, 4/4 tests, 18
  assertions, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 88/88 tests, 228 assertions, exit 0;
  telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`. All prior slices' suites
  (including Slice 008's 7/7 and Slice 014's 16/16) pass unchanged, confirming
  this slice's new client-only translation seam introduced no regression.

## Explicit non-goals and next boundary

This slice does not implement the server-to-client blueprint replication
contract (how a validated blueprint Dictionary actually reaches a connected
client — noted as unresolved in the Starting Town map's "Not yet specified"
section), the hub sector fixture/materialization at server boot (ticket 03,
future slice), facade `Area3D` proximity-trigger/enter-exit UI behavior
(ticket 04, future slice — this slice only places structure geometry, it adds
no interaction), player house allocation (ticket 05, future slice), any
monster/spawn-point instantiation (Basic Monsters map, future slice), or any
SQLite/Canon persistence. The next Starting Town slice must decide the
blueprint replication contract before hub materialization can call this
translator with real server-sent data instead of a test fixture.
