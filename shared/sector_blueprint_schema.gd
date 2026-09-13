extends RefCounted
class_name SectorBlueprintSchema
## Versioned strict JSON schema and validator for a JIT-generated sector
## blueprint (Slice 008, extended by Slice 014). Validates the parsed JSON
## *data* an Ollama response is expected to contain — this script has no
## HTTP, no async, and no dependency on LocalLLMClient, so it can be
## unit-tested with plain Dictionary/Array fixtures. See
## docs/slices/008-sector-blueprint-contract.md and
## docs/slices/014-sector-blueprint-schema-v2-structures.md.
##
## Scope (per .scratch/game-vision/issues/15-sector-blueprint-contract.md and
## .scratch/starting-town/issues/01-schema-v2-structures-and-spawn-points.md):
## coordinates, tiles (base floor/wall/corridor plus the schema-v3 organic
## vocabulary path/plaza/gate/water/grass), and (schema_version 2+, optional)
## structure placements and monster spawn markers. No geometry generation,
## gameplay state, or persistence — those remain explicit non-goals and are
## not validated or referenced here.

## Schema versions this validator accepts. A blueprint whose "schema_version"
## is not in this set is rejected as wrong-version rather than partially
## accepted. Version 1 is the original tiles-only shape (Slice 008); version 2
## additionally allows the optional "structures" and "spawn_points" arrays
## (Slice 014); version 3 adds the organic tile/structure vocabulary
## (Slice 025). All versions remain supported going forward — newer versions
## are not hard replacements, since ordinary non-town sectors keep generating
## tiles-only v1 payloads.
const SUPPORTED_SCHEMA_VERSIONS: PackedInt32Array = [1, 2, 3]

## Bounds the tile array so a single sector response cannot request unbounded
## work; this is a contract-validation bound only, not a gameplay/world-size
## design. Raised across the Organic Village effort (512 -> 2048 -> 4096) so a
## large, non-square starting village fits within one blueprint.
const MAX_TILE_COUNT: int = 4096
## Absolute coordinate bound. Raised to 48 for the ~3x-bigger village (town
## outline reaches +/-30; monster spawn markers sit in the fields beyond it).
const MAX_COORDINATE_ABS: int = 48

## Tile kinds a blueprint may place. The base kinds (floor/wall/corridor) are
## valid in every version; the organic vocabulary (path/plaza/gate/water/grass,
## Slice 025) is gated to schema v3+ by ORGANIC_VOCABULARY_MIN_VERSION.
const SUPPORTED_TILE_KINDS: PackedStringArray = ["floor", "wall", "corridor", "path", "plaza", "gate", "water", "grass"]
const _ORGANIC_TILE_KINDS: PackedStringArray = ["path", "plaza", "gate", "water", "grass"]

## Bounds structure kinds a blueprint may place. No footprint/size field
## exists per ticket 01 — a fixed-size prefab per kind is assigned by a
## future geometry-translation slice, out of scope here. The base kinds
## (house/smithy/armor_shop/inn) are valid in v2+; the organic settlement kinds
## (church/item_shop/tavern/well plus the villager npc_house and the village_hall
## leader's house) are gated to schema v3+.
const SUPPORTED_STRUCTURE_KINDS: PackedStringArray = ["house", "smithy", "armor_shop", "inn", "church", "item_shop", "tavern", "well", "npc_house", "village_hall"]
const _ORGANIC_STRUCTURE_KINDS: PackedStringArray = ["church", "item_shop", "tavern", "well", "npc_house", "village_hall"]

## The organic vocabulary (the new tile and structure kinds above) requires
## this schema version; using it in an older-versioned blueprint is rejected so
## versioning stays meaningful (v1/v2 payloads keep their original vocabulary).
const ORGANIC_VOCABULARY_MIN_VERSION: int = 3
const MAX_FACING_DEGREES: float = 360.0

## Bounds the spawn_points array. 16 is a small, auditable bound sized for
## the Starting Town hub sector's near-term needs (see Slice 014's SDD for
## the full justification); it is a contract-validation bound only, not a
## gameplay-balance constant.
const MAX_SPAWN_POINT_COUNT: int = 16

## Validation outcome codes. Kept as String constants (rather than an enum)
## so they serialize directly into telemetry/result dictionaries without a
## separate lookup step.
const OUTCOME_VALID: String = "valid"
const OUTCOME_MALFORMED_JSON: String = "malformed_json"
const OUTCOME_INCOMPLETE: String = "incomplete"
const OUTCOME_UNSUPPORTED_KIND: String = "unsupported_kind"
const OUTCOME_WRONG_SCHEMA_VERSION: String = "wrong_schema_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"


## Public seam. Validates already-parsed JSON data (a Variant, as returned by
## JSON.parse_string()) against the sector blueprint contract.
## Returns a Dictionary: {"outcome": String, "detail": String, "blueprint": Variant}
## "blueprint" is the validated Dictionary only when outcome == OUTCOME_VALID,
## otherwise null. Fails closed: any ambiguity or missing data is rejected,
## never guessed or partially accepted.
static func validate(parsed_data: Variant) -> Dictionary:
	if parsed_data == null or not (parsed_data is Dictionary):
		return _result(OUTCOME_MALFORMED_JSON, "Top-level JSON value is not an object.")

	var data: Dictionary = parsed_data

	if not data.has("schema_version"):
		return _result(OUTCOME_INCOMPLETE, "Missing required field: schema_version.")
	if not (data["schema_version"] is int) and not (data["schema_version"] is float):
		return _result(OUTCOME_INCOMPLETE, "schema_version must be a number.")
	var schema_version: int = int(data["schema_version"])
	if not SUPPORTED_SCHEMA_VERSIONS.has(schema_version):
		return _result(OUTCOME_WRONG_SCHEMA_VERSION, "Expected schema_version in %s, got %d." % [SUPPORTED_SCHEMA_VERSIONS, schema_version])

	for required_field: String in ["sector_id", "origin", "tiles"]:
		if not data.has(required_field):
			return _result(OUTCOME_INCOMPLETE, "Missing required field: %s." % required_field)

	if not (data["sector_id"] is String) or (data["sector_id"] as String).is_empty():
		return _result(OUTCOME_INCOMPLETE, "sector_id must be a non-empty string.")

	var origin_check: Dictionary = _validate_coordinate(data["origin"], "origin")
	if origin_check["outcome"] != OUTCOME_VALID:
		return origin_check

	if not (data["tiles"] is Array):
		return _result(OUTCOME_INCOMPLETE, "tiles must be an array.")
	var tiles: Array = data["tiles"]
	if tiles.is_empty():
		return _result(OUTCOME_INCOMPLETE, "tiles must contain at least one entry.")
	if tiles.size() > MAX_TILE_COUNT:
		return _result(OUTCOME_INCOMPLETE, "tiles exceeds the maximum of %d entries." % MAX_TILE_COUNT)

	for index in tiles.size():
		var tile_check: Dictionary = _validate_tile(tiles[index], index, schema_version)
		if tile_check["outcome"] != OUTCOME_VALID:
			return tile_check

	if data.has("structures"):
		var structures_check: Dictionary = _validate_structures(data["structures"], schema_version)
		if structures_check["outcome"] != OUTCOME_VALID:
			return structures_check

	if data.has("spawn_points"):
		var spawn_points_check: Dictionary = _validate_spawn_points(data["spawn_points"])
		if spawn_points_check["outcome"] != OUTCOME_VALID:
			return spawn_points_check

	return _result(OUTCOME_VALID, "", data)


## "structures" is optional for both schema versions (absent or empty is
## valid); when present, every entry is validated with the same fail-closed
## style as tiles. structure_id must be unique within the blueprint so every
## future consumer (geometry translation, house allocation) can address one
## structure unambiguously.
static func _validate_structures(value: Variant, schema_version: int) -> Dictionary:
	if not (value is Array):
		return _result(OUTCOME_INCOMPLETE, "structures must be an array.")
	var structures: Array = value

	var seen_ids: Dictionary = {}
	for index in structures.size():
		var entry_check: Dictionary = _validate_structure(structures[index], index, seen_ids, schema_version)
		if entry_check["outcome"] != OUTCOME_VALID:
			return entry_check

	return _result(OUTCOME_VALID, "")


static func _validate_structure(value: Variant, index: int, seen_ids: Dictionary, schema_version: int) -> Dictionary:
	if not (value is Dictionary):
		return _result(OUTCOME_INCOMPLETE, "structures[%d] must be an object." % index)
	var structure: Dictionary = value

	if not structure.has("structure_id"):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].structure_id is required." % index)
	if not (structure["structure_id"] is String) or (structure["structure_id"] as String).is_empty():
		return _result(OUTCOME_INCOMPLETE, "structures[%d].structure_id must be a non-empty string." % index)
	var structure_id: String = structure["structure_id"]
	if seen_ids.has(structure_id):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].structure_id '%s' duplicates an earlier entry." % [index, structure_id])
	seen_ids[structure_id] = true

	if not structure.has("kind"):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].kind is required." % index)
	if not (structure["kind"] is String):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].kind must be a string." % index)
	var kind: String = structure["kind"]
	if not SUPPORTED_STRUCTURE_KINDS.has(kind):
		return _result(OUTCOME_UNSUPPORTED_KIND, "structures[%d].kind '%s' is not a supported kind (%s)." % [index, kind, ", ".join(SUPPORTED_STRUCTURE_KINDS)])
	if _ORGANIC_STRUCTURE_KINDS.has(kind) and schema_version < ORGANIC_VOCABULARY_MIN_VERSION:
		return _result(OUTCOME_UNSUPPORTED_KIND, "structures[%d].kind '%s' requires schema_version >= %d (blueprint is version %d)." % [index, kind, ORGANIC_VOCABULARY_MIN_VERSION, schema_version])

	for axis: String in ["x", "y"]:
		if not structure.has(axis):
			return _result(OUTCOME_INCOMPLETE, "structures[%d].%s is required." % [index, axis])
		if not (structure[axis] is int) and not (structure[axis] is float):
			return _result(OUTCOME_INCOMPLETE, "structures[%d].%s must be a number." % [index, axis])
		if absf(float(structure[axis])) > MAX_COORDINATE_ABS:
			return _result(OUTCOME_OUT_OF_BOUNDS, "structures[%d].%s exceeds the absolute bound of %d." % [index, axis, MAX_COORDINATE_ABS])

	if not structure.has("facing_degrees"):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].facing_degrees is required." % index)
	if not (structure["facing_degrees"] is int) and not (structure["facing_degrees"] is float):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].facing_degrees must be a number." % index)
	var facing_degrees: float = float(structure["facing_degrees"])
	if facing_degrees < 0.0 or facing_degrees >= MAX_FACING_DEGREES:
		return _result(OUTCOME_OUT_OF_BOUNDS, "structures[%d].facing_degrees must be in [0, %s)." % [index, MAX_FACING_DEGREES])

	return _result(OUTCOME_VALID, "")


## "spawn_points" is optional for both schema versions (absent or empty is
## valid); bounded by MAX_SPAWN_POINT_COUNT. No monster kind field exists yet
## per ticket 01 — deliberately deferred to the future Basic Monsters slice.
static func _validate_spawn_points(value: Variant) -> Dictionary:
	if not (value is Array):
		return _result(OUTCOME_INCOMPLETE, "spawn_points must be an array.")
	var spawn_points: Array = value

	if spawn_points.size() > MAX_SPAWN_POINT_COUNT:
		return _result(OUTCOME_INCOMPLETE, "spawn_points exceeds the maximum of %d entries." % MAX_SPAWN_POINT_COUNT)

	for index in spawn_points.size():
		var entry_check: Dictionary = _validate_spawn_point(spawn_points[index], index)
		if entry_check["outcome"] != OUTCOME_VALID:
			return entry_check

	return _result(OUTCOME_VALID, "")


static func _validate_spawn_point(value: Variant, index: int) -> Dictionary:
	if not (value is Dictionary):
		return _result(OUTCOME_INCOMPLETE, "spawn_points[%d] must be an object." % index)
	var spawn_point: Dictionary = value

	if not spawn_point.has("spawn_id"):
		return _result(OUTCOME_INCOMPLETE, "spawn_points[%d].spawn_id is required." % index)
	if not (spawn_point["spawn_id"] is String) or (spawn_point["spawn_id"] as String).is_empty():
		return _result(OUTCOME_INCOMPLETE, "spawn_points[%d].spawn_id must be a non-empty string." % index)

	for axis: String in ["x", "y"]:
		if not spawn_point.has(axis):
			return _result(OUTCOME_INCOMPLETE, "spawn_points[%d].%s is required." % [index, axis])
		if not (spawn_point[axis] is int) and not (spawn_point[axis] is float):
			return _result(OUTCOME_INCOMPLETE, "spawn_points[%d].%s must be a number." % [index, axis])
		if absf(float(spawn_point[axis])) > MAX_COORDINATE_ABS:
			return _result(OUTCOME_OUT_OF_BOUNDS, "spawn_points[%d].%s exceeds the absolute bound of %d." % [index, axis, MAX_COORDINATE_ABS])

	return _result(OUTCOME_VALID, "")


static func _validate_coordinate(value: Variant, field_name: String) -> Dictionary:
	if not (value is Dictionary):
		return _result(OUTCOME_INCOMPLETE, "%s must be an object." % field_name)
	var coordinate: Dictionary = value
	for axis: String in ["x", "y"]:
		if not coordinate.has(axis):
			return _result(OUTCOME_INCOMPLETE, "%s.%s is required." % [field_name, axis])
		if not (coordinate[axis] is int) and not (coordinate[axis] is float):
			return _result(OUTCOME_INCOMPLETE, "%s.%s must be a number." % [field_name, axis])
		if absf(float(coordinate[axis])) > MAX_COORDINATE_ABS:
			return _result(OUTCOME_OUT_OF_BOUNDS, "%s.%s exceeds the absolute bound of %d." % [field_name, axis, MAX_COORDINATE_ABS])
	return _result(OUTCOME_VALID, "")


static func _validate_tile(value: Variant, index: int, schema_version: int) -> Dictionary:
	if not (value is Dictionary):
		return _result(OUTCOME_INCOMPLETE, "tiles[%d] must be an object." % index)
	var tile: Dictionary = value

	for axis: String in ["x", "y"]:
		if not tile.has(axis):
			return _result(OUTCOME_INCOMPLETE, "tiles[%d].%s is required." % [index, axis])
		if not (tile[axis] is int) and not (tile[axis] is float):
			return _result(OUTCOME_INCOMPLETE, "tiles[%d].%s must be a number." % [index, axis])
		if absf(float(tile[axis])) > MAX_COORDINATE_ABS:
			return _result(OUTCOME_OUT_OF_BOUNDS, "tiles[%d].%s exceeds the absolute bound of %d." % [index, axis, MAX_COORDINATE_ABS])

	if not tile.has("kind"):
		return _result(OUTCOME_INCOMPLETE, "tiles[%d].kind is required." % index)
	if not (tile["kind"] is String):
		return _result(OUTCOME_INCOMPLETE, "tiles[%d].kind must be a string." % index)
	var kind: String = tile["kind"]
	if not SUPPORTED_TILE_KINDS.has(kind):
		return _result(OUTCOME_UNSUPPORTED_KIND, "tiles[%d].kind '%s' is not a supported kind (%s)." % [index, kind, ", ".join(SUPPORTED_TILE_KINDS)])
	if _ORGANIC_TILE_KINDS.has(kind) and schema_version < ORGANIC_VOCABULARY_MIN_VERSION:
		return _result(OUTCOME_UNSUPPORTED_KIND, "tiles[%d].kind '%s' requires schema_version >= %d (blueprint is version %d)." % [index, kind, ORGANIC_VOCABULARY_MIN_VERSION, schema_version])

	return _result(OUTCOME_VALID, "")


static func _result(outcome: String, detail: String, blueprint: Variant = null) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
		"blueprint": blueprint,
	}
