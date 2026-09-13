extends RefCounted
class_name StartingTownHubFixture
## Slice 016 (enriched by Slice 025): the starting town hub as a hard-coded,
## schema-v3-shaped sector blueprint fixture using the organic tile/structure
## vocabulary. This is deliberately NOT live-generated — the hub must
## reliably contain a player's house pool plus the Smithy, Armor Shop, and Inn
## every run, so it bypasses Ollama / provisional_sector_generator.gd entirely
## and ships as static data validated by the same SectorBlueprintSchema the
## LLM path uses. See docs/slices/016-starting-town-hub-fixture.md and
## .scratch/starting-town/issues/03-hub-sector-identity-and-pinning.md
## (resolved). The 10-house pool matches the resolved 10-player max
## (.scratch/starting-town/issues/05-player-house-allocation.md); this slice
## authors that content but does NOT implement per-player allocation.
##
## Scope boundary: the spawn_points below are placed OUTSIDE the town outline
## (beyond _TOWN_RADIUS) so monsters spawn in the fields around the city, never
## inside it (user caveat). No client replication, no geometry translation
## call, and no persistence — see the slice doc's non-goals.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

## Reserved literal sector id for the one hub every server instance starts
## with (CONTEXT.md "Hub sector"). A literal constant, matching the
## reserved-id pattern already used by TargetDummy ("target_dummy_0").
const SECTOR_ID: String = "starting_town_hub"

## The organic town is an octagon: a square of radius _TOWN_RADIUS with its
## corners clipped along |x| + |y| <= _TOWN_DIAGONAL, so the city reads as
## rounded/districted rather than a hard square. Both are well inside
## SectorBlueprintSchema.MAX_COORDINATE_ABS (32). _PLAZA_HALF sizes the central
## paved plaza.
const _TOWN_RADIUS: int = 16
const _TOWN_DIAGONAL: int = 22
const _PLAZA_HALF: int = 2

## The 17 structures placed in the city, clustered into districts: a northern
## residential ring of 10 houses, a southern trade quarter (smithy, armor shop,
## inn near the gate road), and four organic flavor buildings (a church, a
## tavern, an item shop, and a well). Every structure_id is unique and every
## (x, y) is a distinct interior cell with x != 0 and y != 0 (so none sit on the
## radial path avenues) and none inside the central plaza.
const _STRUCTURES: Array[Dictionary] = [
	{"structure_id": "house_01", "kind": "house", "x": -11, "y": 6, "facing_degrees": 180.0},
	{"structure_id": "house_02", "kind": "house", "x": -8, "y": 9, "facing_degrees": 180.0},
	{"structure_id": "house_03", "kind": "house", "x": -4, "y": 11, "facing_degrees": 180.0},
	{"structure_id": "house_04", "kind": "house", "x": -12, "y": 2, "facing_degrees": 90.0},
	{"structure_id": "house_05", "kind": "house", "x": -6, "y": 5, "facing_degrees": 90.0},
	{"structure_id": "house_06", "kind": "house", "x": 4, "y": 11, "facing_degrees": 180.0},
	{"structure_id": "house_07", "kind": "house", "x": 8, "y": 9, "facing_degrees": 180.0},
	{"structure_id": "house_08", "kind": "house", "x": 11, "y": 6, "facing_degrees": 270.0},
	{"structure_id": "house_09", "kind": "house", "x": 12, "y": 2, "facing_degrees": 270.0},
	{"structure_id": "house_10", "kind": "house", "x": 6, "y": 5, "facing_degrees": 270.0},
	{"structure_id": "smithy_01", "kind": "smithy", "x": -5, "y": -6, "facing_degrees": 0.0},
	{"structure_id": "armor_shop_01", "kind": "armor_shop", "x": 5, "y": -6, "facing_degrees": 0.0},
	{"structure_id": "inn_01", "kind": "inn", "x": -3, "y": -10, "facing_degrees": 0.0},
	{"structure_id": "church_01", "kind": "church", "x": -2, "y": 12, "facing_degrees": 180.0},
	{"structure_id": "tavern_01", "kind": "tavern", "x": 2, "y": -12, "facing_degrees": 0.0},
	{"structure_id": "item_shop_01", "kind": "item_shop", "x": 9, "y": -3, "facing_degrees": 270.0},
	{"structure_id": "well_01", "kind": "well", "x": 3, "y": 4, "facing_degrees": 0.0},
]

## Monster spawn markers, each placed OUTSIDE the town wall ring
## (|x| or |y| > _WALL_EXTENT, i.e. beyond the town boundary) so monsters spawn
## in the wilds around town and never inside it (user caveat, 2026-09-12). Well
## within SectorBlueprintSchema.MAX_COORDINATE_ABS (32); consumed by the Basic
## Monsters runtime (server/server_monster_manager.gd).
const _SPAWN_POINTS: Array[Dictionary] = [
	{"spawn_id": "wild_east", "x": 22, "y": 0},
	{"spawn_id": "wild_west", "x": -22, "y": 0},
	{"spawn_id": "wild_north", "x": 0, "y": 22},
	{"spawn_id": "wild_south", "x": 0, "y": -22},
]


## Returns a fresh copy of the hard-coded hub blueprint Dictionary (schema
## version 3). A new Dictionary/Array graph is built on every call so callers
## and tests can never mutate shared fixture state. The town is an organic
## octagon (a square with clipped corners) enclosed by a wall with a southern
## gate, radial path avenues, a central paved plaza, a grass ring inside the
## wall, and a small ornamental pond — using the schema-v3 organic vocabulary.
static func blueprint() -> Dictionary:
	var tiles: Array = []
	for x in range(-_TOWN_RADIUS, _TOWN_RADIUS + 1):
		for y in range(-_TOWN_RADIUS, _TOWN_RADIUS + 1):
			if not _in_town(x, y):
				continue
			tiles.append({"x": x, "y": y, "kind": _tile_kind(x, y)})

	var structures: Array = []
	for structure: Dictionary in _STRUCTURES:
		structures.append(structure.duplicate(true))

	var spawn_points: Array = []
	for spawn_point: Dictionary in _SPAWN_POINTS:
		spawn_points.append(spawn_point.duplicate(true))

	return {
		"schema_version": 3,
		"sector_id": SECTOR_ID,
		"origin": {"x": 0, "y": 0},
		"tiles": tiles,
		"structures": structures,
		"spawn_points": spawn_points,
	}


## The organic town outline: a square of radius _TOWN_RADIUS with its corners
## clipped along the |x| + |y| <= _TOWN_DIAGONAL diagonal, so the city reads as
## rounded/districted rather than a hard square.
static func _in_town(x: int, y: int) -> bool:
	return maxi(absi(x), absi(y)) <= _TOWN_RADIUS and (absi(x) + absi(y)) <= _TOWN_DIAGONAL


## Tile kind at (x, y) for the organic v3 town: a walled octagon with a 3-wide
## southern gate, a central paved plaza, radial path avenues, a small ornamental
## pond, and a grass ring hugging the inside of the wall. Everything else is
## floor.
static func _tile_kind(x: int, y: int) -> String:
	if _is_gate(x, y):
		return "gate"
	if _is_boundary(x, y):
		return "wall"
	if absi(x) <= _PLAZA_HALF and absi(y) <= _PLAZA_HALF:
		return "plaza"
	if x == 0 or y == 0:
		return "path"
	if _in_pond(x, y):
		return "water"
	if _touches_wall(x, y):
		return "grass"
	return "floor"


static func _is_boundary(x: int, y: int) -> bool:
	return not (_in_town(x + 1, y) and _in_town(x - 1, y) and _in_town(x, y + 1) and _in_town(x, y - 1))


## The 3-wide southern gate opening in the wall (the town entrance).
static func _is_gate(x: int, y: int) -> bool:
	return _is_boundary(x, y) and y < 0 and absi(x) <= 1


static func _is_wall(x: int, y: int) -> bool:
	return _in_town(x, y) and _is_boundary(x, y) and not _is_gate(x, y)


## True for an interior cell one step inside the wall ring (any 4-neighbor is a
## wall) — the grass border.
static func _touches_wall(x: int, y: int) -> bool:
	if _is_boundary(x, y):
		return false
	return _is_wall(x + 1, y) or _is_wall(x - 1, y) or _is_wall(x, y + 1) or _is_wall(x, y - 1)


## A small 2x2 ornamental pond in a southwest district gap, clear of every
## structure and of the plaza/avenues.
static func _in_pond(x: int, y: int) -> bool:
	return x >= -8 and x <= -7 and y >= -3 and y <= -2


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
