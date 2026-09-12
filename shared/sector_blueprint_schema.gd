extends RefCounted
class_name SectorBlueprintSchema
## Versioned strict JSON schema and validator for a JIT-generated sector
## blueprint (Slice 008). Validates the parsed JSON *data* an Ollama response
## is expected to contain — this script has no HTTP, no async, and no
## dependency on LocalLLMClient, so it can be unit-tested with plain
## Dictionary/Array fixtures. See docs/slices/008-sector-blueprint-contract.md.
##
## Scope (per .scratch/game-vision/issues/15-sector-blueprint-contract.md):
## coordinates and floor/wall/corridor tiles only. No entities, items, quests,
## geometry generation, or persistence — those remain explicit non-goals for
## this slice and are not validated or referenced here.

## Bumped whenever the required shape of a sector blueprint changes in a way
## that is not backward compatible. A blueprint whose own "schema_version"
## does not equal this constant is rejected as wrong-version rather than
## partially accepted.
const CURRENT_SCHEMA_VERSION: int = 1

## Bounds the tile array so a single sector response cannot request unbounded
## work; this is a contract-validation bound only, not a gameplay/world-size
## design (no sector geometry is generated in this slice).
const MAX_TILE_COUNT: int = 512
const MAX_COORDINATE_ABS: int = 32

const SUPPORTED_TILE_KINDS: PackedStringArray = ["floor", "wall", "corridor"]

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
	if schema_version != CURRENT_SCHEMA_VERSION:
		return _result(OUTCOME_WRONG_SCHEMA_VERSION, "Expected schema_version %d, got %d." % [CURRENT_SCHEMA_VERSION, schema_version])

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
		var tile_check: Dictionary = _validate_tile(tiles[index], index)
		if tile_check["outcome"] != OUTCOME_VALID:
			return tile_check

	return _result(OUTCOME_VALID, "", data)


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


static func _validate_tile(value: Variant, index: int) -> Dictionary:
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

	return _result(OUTCOME_VALID, "")


static func _result(outcome: String, detail: String, blueprint: Variant = null) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
		"blueprint": blueprint,
	}
