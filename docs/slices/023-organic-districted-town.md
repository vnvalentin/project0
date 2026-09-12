# Slice 023: Bigger organic districted starting town

Tracker context: Phase 8 — JIT world generation and local inference; opens
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city) and
supersedes the Slice 016 square hub ([F-019](../FEATURE-LIST.md#f-019-starting-town-hub-fixture)).
Planning tickets: [Organic LLM Village map](../../.scratch/organic-village/map.md)
(decisions Q1–Q5 resolved). First of that map's four delivery slices — the
instant visible win and the future LLM fallback base.

## SDD

Goal: Replace the small 17×17 square hub with a substantially larger, organic,
DISTRICTED walled town that still renders through the existing per-tile geometry
pipeline (no schema-vocabulary or geometry change yet), keeping every required
structure and keeping monsters outside the enlarged boundary.

Public seams:

- `server/starting_town_hub_fixture.gd` (`class_name StartingTownHubFixture`,
  `RefCounted`) — `blueprint()` now generates an organic octagon town: a square
  of radius `_TOWN_RADIUS` (16) with its corners clipped along
  `|x| + |y| <= _TOWN_DIAGONAL` (22), enclosed by a wall with a 3-wide southern
  **gate**, radial **corridor avenues** (the `x == 0` / `y == 0` cross), and a
  central paved **plaza** (`|x| <= _PLAZA_HALF` and `|y| <= _PLAZA_HALF`). Two
  new pure static helpers, `_in_town(x, y)` and `_tile_kind(x, y)`, express the
  outline and per-tile kind. The 13 structures are re-placed into districts (a
  northern residential ring of 10 houses; a southern trade quarter with the
  Smithy, Armor Shop, and Inn near the gate road), each on a distinct interior
  floor cell. Spawn points move out to ±22. `materialize()` and `SECTOR_ID` are
  unchanged.
- `shared/sector_blueprint_schema.gd` — `MAX_TILE_COUNT` raised from 512 to
  2048 so the larger (~869-tile) town validates. All other bounds unchanged;
  the town stays well inside `MAX_COORDINATE_ABS` (32).
- `server/server_monster_manager.gd` — `TOWN_EXCLUSION_HALF_EXTENT` raised from
  8.5 to 18.0 to sit just outside the enlarged octagon (on-axis radius 16), so
  no monster spawns or respawns inside the bigger town.
- `client/gameplay.tscn` — the `FlatPlane` ground `BoxMesh`/`BoxShape3D` grow
  from 20×20 to 60×60 (±30) to cover the town plus the ±22 monster fields and
  ±24 respawn ring.
- `tests/unit/test_starting_town_hub_fixture.gd` — the spawn-outside assertion
  now checks against the new town outline (radius 16, `> 16`).

Behavior:

- **Bigger, non-square footprint**: the town is an octagon spanning ±16 on-axis
  (~33 tiles wide) with clipped corners, versus the old ±8 square — roughly a
  3.4× larger walled area that reads as rounded/districted rather than a hard
  square.
- **One gate**: only the southern wall opens (a 3-cell gap at `x ∈ {-1, 0, 1}`);
  every other boundary cell is wall. The `y == 0` / `x == 0` avenues still run
  through the interior but terminate at the wall on the other three sides.
- **Districts**: 10 houses cluster along the northern half; the Smithy, Armor
  Shop, and Inn cluster in the southern trade quarter by the gate road. Every
  structure sits on an interior floor cell (never on an avenue, the plaza, or a
  wall).
- **Monsters stay out**: spawn points are authored at ±22 (outside the ±18
  exclusion box) and every respawn is clamped outside it, unchanged in mechanism
  from Slice 022.

Implementation decisions:

- **Existing pipeline, on purpose**: this slice reuses the current floor/wall/
  corridor tile kinds and the four structure kinds and the one-StaticBody3D-
  per-tile translator, so it renders immediately with zero geometry or schema-
  vocabulary risk. The town is deliberately bounded (~869 tiles / bodies) well
  under true Qeynos/Midgar city scale; that scale waits for the geometry pass +
  LLM (Slices 024–025). See [DT-008](../TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-does-not-scale-to-city-size).
- **Octagon via two pure predicates**: the outline and tile kind are pure
  functions of `(x, y)` with no per-cell data table, so the shape is easy to
  reason about, re-tune, and (later) hand off to the LLM as a validation target.
- **`_TOWN_RADIUS` drives everything**: the monster exclusion and the fixture
  test reference the same conceptual radius, so the "monsters outside town"
  invariant scales with the town rather than a magic number. Deriving the
  exclusion directly from the blueprint bounds is deferred to Slice 026.

## BDD

### Bigger organic town validates and renders

Given the enlarged hub fixture
When `blueprint()` is materialized and validated through `SectorBlueprintSchema`
Then it is `OUTCOME_VALID` (tile count under the raised `MAX_TILE_COUNT`), and
the server-to-client replication path renders one body per tile plus one prefab
per structure with no rejection.

### Required structures preserved in districts

Given the enlarged hub fixture
When its structures are inspected
Then exactly 10 houses plus one Smithy, one Armor Shop, and one Inn exist, every
`structure_id` and `(x, y)` is unique, and every structure sits on an interior
floor cell (not an avenue, plaza, or wall).

### Monsters stay outside the bigger town

Given the enlarged town outline (radius 16) and the ±18 exclusion box
When monsters spawn at boot and respawn after defeat
Then every monster position is outside the town on every spawn and respawn.

## TDD

- `tests/unit/test_starting_town_hub_fixture.gd` (8 tests) — structure counts,
  unique ids/positions, interior-floor placement, schema validity, and the
  updated spawn-outside-the-town-outline (`> 16`) assertion. All pass against
  the enlarged town.
- `tests/unit/test_server_monster_manager.gd` (7 tests) — initial-spawn and
  respawn outside the (now ±18) exclusion box; reads `TOWN_EXCLUSION_HALF_EXTENT`
  so it auto-follows the new value. All pass.
- `tests/integration/test_blueprint_replication.gd` (4 tests) — the client
  renders the full enlarged blueprint (auto-computed child count) with the four
  rejection paths still failing closed. All pass.

## Validation

- `godot --headless --check-only -s server/starting_town_hub_fixture.gd` → exit
  0 (fixture parses with the new octagon helpers).
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_starting_town_hub_fixture -gexit` → 8/8 tests, 50 assertions,
  exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_server_monster_manager -gexit` → 7/7 tests, 136 assertions,
  exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
  -gselect=test_blueprint_replication -gexit` → 4/4 tests, 14 assertions, exit 0.
- `scripts/run_gut_validation.sh` → 19 scripts, 140/140 tests, 510 assertions,
  exit 0; `build/validation/gut.xml` refreshed. Only the pre-existing expected
  fail-closed diagnostics remain (`NetworkClient: rejecting sector blueprint …`
  for the unsupported-kind and missing-schema-version rejection tests, and the
  malformed-JSON parse errors from the LLM-client contract tests). No new
  `Failed` / `Parse Error` / `SCRIPT ERROR` / `out_of_bounds` lines.

## Non-goals (this slice)

- No new schema vocabulary (path/plaza/gate/water/grass tiles or church/
  item_shop/tavern/well structures) — Slice 024.
- No geometry change (floors stay one collider body per tile) and no building/
  player rescale — Slice 024.
- No LLM generation — the town is still hand-authored; the LLM path and
  required-structure guarantee are Slice 025.
- No derivation of the monster exclusion from the blueprint bounds — still a
  constant (`TOWN_EXCLUSION_HALF_EXTENT`) — Slice 026.
- No persistence/Canon; nothing is stored.
