extends RefCounted
class_name StartingTownHubFixture
## Slice 016: the starting town hub as a hard-coded, schema-v2-shaped sector
## blueprint fixture. This is deliberately NOT live-generated — the hub must
## reliably contain a player's house pool plus the Smithy, Armor Shop, and Inn
## every run, so it bypasses Ollama / provisional_sector_generator.gd entirely
## and ships as static data validated by the same SectorBlueprintSchema the
## LLM path uses. See docs/slices/016-starting-town-hub-fixture.md and
## .scratch/starting-town/issues/03-hub-sector-identity-and-pinning.md
## (resolved). The 10-house pool matches the resolved 10-player max
## (.scratch/starting-town/issues/05-player-house-allocation.md); this slice
## authors that content but does NOT implement per-player allocation.
##
## Scope boundary: the spawn_points below are placed OUTSIDE the town wall ring
## (|coord| > _WALL_EXTENT) so monsters spawn in the wilds around town, never
## inside it (user caveat, 2026-09-12). No client replication, no geometry
## translation call, and no persistence — see the slice doc's non-goals.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

## Reserved literal sector id for the one hub every server instance starts
## with (CONTEXT.md "Hub sector"). A literal constant, matching the
## reserved-id pattern already used by TargetDummy ("target_dummy_0").
const SECTOR_ID: String = "starting_town_hub"

## Bounds of the interior floor area; the perimeter ring one step beyond is
## wall. Kept well inside SectorBlueprintSchema.MAX_COORDINATE_ABS (32) so the
## fixture stays within contract bounds with room to spare.
const _INTERIOR_EXTENT: int = 7
const _WALL_EXTENT: int = 8

## The 13 structures placed in the hub: 10 houses (the player pool) plus one
## each of smithy, armor_shop, inn. Every structure_id is unique and every
## (x, y) is a distinct interior floor cell (x != 0 and y != 0 so none sit on
## the central corridor cross). facing_degrees are all within [0, 360).
const _STRUCTURES: Array[Dictionary] = [
	{"structure_id": "house_01", "kind": "house", "x": -6, "y": 6, "facing_degrees": 180.0},
	{"structure_id": "house_02", "kind": "house", "x": -3, "y": 6, "facing_degrees": 180.0},
	{"structure_id": "house_03", "kind": "house", "x": 3, "y": 6, "facing_degrees": 180.0},
	{"structure_id": "house_04", "kind": "house", "x": 6, "y": 6, "facing_degrees": 180.0},
	{"structure_id": "house_05", "kind": "house", "x": -6, "y": 3, "facing_degrees": 90.0},
	{"structure_id": "house_06", "kind": "house", "x": 6, "y": 3, "facing_degrees": 270.0},
	{"structure_id": "house_07", "kind": "house", "x": -6, "y": -3, "facing_degrees": 90.0},
	{"structure_id": "house_08", "kind": "house", "x": 6, "y": -3, "facing_degrees": 270.0},
	{"structure_id": "house_09", "kind": "house", "x": -6, "y": -6, "facing_degrees": 0.0},
	{"structure_id": "house_10", "kind": "house", "x": 6, "y": -6, "facing_degrees": 0.0},
	{"structure_id": "smithy_01", "kind": "smithy", "x": -3, "y": -3, "facing_degrees": 0.0},
	{"structure_id": "armor_shop_01", "kind": "armor_shop", "x": 3, "y": -3, "facing_degrees": 0.0},
	{"structure_id": "inn_01", "kind": "inn", "x": 3, "y": 3, "facing_degrees": 180.0},
]

## Monster spawn markers, each placed OUTSIDE the town wall ring
## (|x| or |y| > _WALL_EXTENT, i.e. beyond the town boundary) so monsters spawn
## in the wilds around town and never inside it (user caveat, 2026-09-12). Well
## within SectorBlueprintSchema.MAX_COORDINATE_ABS (32); consumed by the Basic
## Monsters runtime (server/server_monster_manager.gd).
const _SPAWN_POINTS: Array[Dictionary] = [
	{"spawn_id": "wild_east", "x": 10, "y": 0},
	{"spawn_id": "wild_west", "x": -10, "y": 0},
	{"spawn_id": "wild_north", "x": 0, "y": 10},
	{"spawn_id": "wild_south", "x": 0, "y": -10},
]


## Returns a fresh copy of the hard-coded hub blueprint Dictionary (schema
## version 2). A new Dictionary/Array graph is built on every call so callers
## and tests can never mutate shared fixture state. Tiles are generated as a
## perimeter wall ring, a central corridor cross (x == 0 or y == 0), and floor
## everywhere else in between — a small, bounded, coherent footprint that
## contains every structure.
static func blueprint() -> Dictionary:
	var tiles: Array = []
	for x in range(-_WALL_EXTENT, _WALL_EXTENT + 1):
		for y in range(-_WALL_EXTENT, _WALL_EXTENT + 1):
			var kind: String
			if abs(x) == _WALL_EXTENT or abs(y) == _WALL_EXTENT:
				kind = "wall"
			elif x == 0 or y == 0:
				kind = "corridor"
			else:
				kind = "floor"
			tiles.append({"x": x, "y": y, "kind": kind})

	var structures: Array = []
	for structure: Dictionary in _STRUCTURES:
		structures.append(structure.duplicate(true))

	var spawn_points: Array = []
	for spawn_point: Dictionary in _SPAWN_POINTS:
		spawn_points.append(spawn_point.duplicate(true))

	return {
		"schema_version": 2,
		"sector_id": SECTOR_ID,
		"origin": {"x": 0, "y": 0},
		"tiles": tiles,
		"structures": structures,
		"spawn_points": spawn_points,
	}


## Fail-closed materialization seam. Validates `source` against the sector
## blueprint schema and returns a result the server acts on at boot:
##   {"ok": bool, "blueprint": Dictionary, "outcome": String, "detail": String}
## `ok == false` means the server MUST refuse to start. Kept pure/static so the
## fail-closed branch is unit-testable by passing a deliberately-corrupted
## Dictionary, without launching a live server process.
static func materialize(source: Dictionary) -> Dictionary:
	var result: Dictionary = SectorBlueprintSchemaScript.validate(source)
	var ok: bool = result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID
	return {
		"ok": ok,
		"blueprint": (result["blueprint"] as Dictionary) if ok else {},
		"outcome": result["outcome"],
		"detail": result["detail"],
	}
