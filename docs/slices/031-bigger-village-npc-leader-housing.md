# Slice 031: Bigger rural village with NPC and leader housing

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city) and extends
[F-017](../FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points)
(bounds + vocabulary) and [F-018](../FEATURE-LIST.md#f-018-client-side-sector-geometry-translation)
(prefabs/lookup). Planning ticket: [Organic LLM Village map](../../.scratch/organic-village/map.md).

## SDD

Goal (user request): make the starting town **at least 3x bigger** and give it
**more than player housing** — villager (NPC) homes and a **village leader's
house** — for a small rural village feel (Qeynos / Adventures of Elliot), with
no nobles.

Public seams:

- `server/starting_town_hub_fixture.gd` — the octagon village grows from radius
  16 to **30** (`_TOWN_DIAGONAL` 22→42, ~3.5x area, ~3037 tiles), the plaza to
  `_PLAZA_HALF` 4, and `_SECONDARY_STREET` (±14) adds cross-streets so the town
  reads as a district grid rather than one square. `_STRUCTURES` grows from 17
  to **28**: the 10 player houses, **10 villager homes (`npc_house`)** in
  east/west rings, the **village leader's hall (`village_hall`)** by the plaza,
  the trade quarter (smithy/armor_shop/item_shop/inn), tavern, church, and the
  plaza well. Spawn markers move out to ±38 (beyond the bigger wall).
- `shared/sector_blueprint_schema.gd` — `MAX_TILE_COUNT` 2048→**4096** and
  `MAX_COORDINATE_ABS` 32→**48** for the larger footprint; `npc_house` and
  `village_hall` are added to the v3 organic structure vocabulary (still
  version-gated, still backward compatible with v1/v2).
- `shared/sector_geometry_lookup.gd` + `client/structures/{npc_house,village_hall}.tscn`
  — two new placeholder prefabs (villager house; a larger rural leader's hall,
  modest, not a manor).
- `server/server_monster_manager.gd` — `TOWN_EXCLUSION_HALF_EXTENT` 18→**32**
  (just outside radius 30) so monsters still spawn only in the fields.
- `client/gameplay.tscn` — the ground plane grows to 100×100.
- `server/town_layout_provider.gd` — `default_town_prompt()` updated for the
  bigger bounds (±30) and the new `npc_house`/`village_hall` kinds; the required
  guarantee is unchanged (10 player houses + smithy + armor_shop + inn).

Behavior:

- The village is ~3.5x the previous area with a gated wall, main + secondary
  streets, a central plaza + well, a grass ring, and a pond.
- Player housing stays exactly 10 `house` structures (the only pool
  `HouseAllocator` hands to players — it filters `kind == "house"`, so the 10
  `npc_house` are never allocated to a player).
- One `village_hall` (the rural leader's house) sits by the plaza.
- Monsters still spawn only outside the (now larger) village.

Implementation decisions:

- **`npc_house`/`village_hall` extend the v3 organic vocabulary** rather than
  minting a schema v4. They are the same conceptual tier (organic settlement
  buildings) as the v3 flavor kinds, and adding accepted kinds is forward
  compatible — no previously-valid blueprint changes meaning. A new schema
  version is reserved for contract-shape changes (new fields/arrays), not more
  building kinds.
- **NPC housing is a distinct kind, not extra `house`.** The required-structure
  guarantee and the player house pool both key on `house`, so villager homes had
  to be their own kind to avoid inflating the player pool or the guarantee.
- **Deterministic hand-authored layout.** All 28 positions are unique interior
  cells authored as data; the schema validation + fixture tests guard bounds,
  uniqueness, and required structures. Merged geometry (Slice 024) keeps the
  ~3037-tile village at one wall body + per-kind ground meshes, so the size is
  cheap.

## BDD

### The village is bigger with the new housing

Given the enriched hub fixture
When its blueprint is built
Then it is schema v3, validates, spans radius 30 (~3.5x area), and has exactly
10 `house`, 10 `npc_house`, and 1 `village_hall` (28 structures total).

### The new kinds are version-gated and render

Given `npc_house`/`village_hall`
When used in a v3 blueprint they validate; in v1/v2 they are rejected; and when
the hub is replicated the two new prefabs instantiate.

### Player pool and monster exclusion still hold

Given the bigger village
When the house pool is built and monsters spawn
Then only the 10 `house` structures are the player pool, and every monster
spawns outside the radius-30 village.

## TDD

- `tests/unit/test_starting_town_hub_fixture.gd` — updated counts (10 house / 10
  npc_house / 1 village_hall / 28 total) and the spawn-outside threshold (> 30).
- `tests/unit/test_sector_blueprint_schema_v3.gd` — `npc_house`/`village_hall`
  added to the organic-kind validity test.
- `tests/unit/test_sector_geometry_lookup.gd` — the drift + scene-path tests
  auto-cover the two new prefabs (verifying they exist/load).
- `tests/integration/test_blueprint_replication.gd` — renders the bigger village
  (structure count auto-adapts to 28; the new prefabs must instantiate).
- `tests/unit/test_server_monster_manager.gd` — reads the raised exclusion and
  the ±38 spawns; all outside-town assertions still hold.
- `scripts/sector_blueprint_fixtures.gd` — the two out-of-bounds contract
  fixtures moved from coordinate 33 to 49 (a direct consequence of raising
  `MAX_COORDINATE_ABS` to 48; 33 is now in-bounds).

## Validation

- Parse-check schema/fixture/provider → exit 0.
- Focused: fixture 9/9, schema v3 8/8, lookup 9/9, monster manager 7/7, provider
  8/8, replication 4/4, contract 7/7 — all exit 0.
- Full suite `scripts/run_gut_validation.sh` → 22 scripts, 168/168 tests, 710
  assertions, exit 0. Only the known-expected fail-closed rejection diagnostics
  and the pre-existing benign headless `Parameter "m" is null` lines remain.

## Non-goals (this slice)

- No NPC behaviour/AI, dialogue, or occupancy — `npc_house`/`village_hall` are
  visual buildings only (facades stay enter/exit-only).
- No player/building rescale beyond the new prefabs' sizes.
- No LLM boot wiring (the fixture remains the boot default; the guarantee seam
  from Slice 026 already accepts the new kinds).
- No persistence.
- No monster-exclusion-from-bounds derivation — still a constant (a later slice).
