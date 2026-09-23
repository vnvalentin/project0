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
## (Slice 025); version 4 adds required parametric geometry fields on
## `house`-kind structures (Feature #710). All versions remain supported
## going forward — newer versions are not hard replacements, since ordinary
## non-town sectors keep generating tiles-only v1 payloads.
const SUPPORTED_SCHEMA_VERSIONS: PackedInt32Array = [1, 2, 3, 4]
const SPATIAL_SCHEMA_PATH: String = "res://shared/spatial_schema_v1.json"
const SPATIAL_SCHEMA_ID: String = "project0://schemas/spatial_schema_v1.json"

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

## Schema v4 gates required parametric geometry fields (footprint_width,
## footprint_depth, roof_style) on `house`-kind structures, replacing fixed
## per-kind prefab selection with schema-driven procedural generation
## (Feature #710, Epic #713). Other kinds are unaffected and keep the
## existing enum+prefab path; earlier schema versions keep the pre-v4 shape
## (backward compatibility).
const PROCEDURAL_GEOMETRY_MIN_VERSION: int = 4

## Bounds for house footprint dimensions, in world units (1 unit = 1 yard,
## ADR-0003 imperial world scale). 3 matches today's placeholder
## client/structures/house.tscn box; 12 stays well inside the 440-unit
## sector edge. A contract-validation bound only, not a gameplay-balance
## constant.
const MIN_FOOTPRINT_UNITS: float = 3.0
const MAX_FOOTPRINT_UNITS: float = 12.0

## Roof styles a procedurally-generated house may specify (Feature #710).
const SUPPORTED_ROOF_STYLES: PackedStringArray = ["gable_roof", "hip_roof", "flat_roof"]

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
	var contract: Dictionary = _load_contract()
	if contract.is_empty():
		return _result(OUTCOME_INCOMPLETE, "spatial_schema_v1.json is missing or invalid.")
	if parsed_data == null or not (parsed_data is Dictionary):
		return _result(OUTCOME_MALFORMED_JSON, "Top-level JSON value is not an object.")

	var data: Dictionary = parsed_data

	if not data.has("schema_version"):
		return _result(OUTCOME_INCOMPLETE, "Missing required field: schema_version.")
	if not (data["schema_version"] is int) and not (data["schema_version"] is float):
		return _result(OUTCOME_INCOMPLETE, "schema_version must be a number.")
	if data["schema_version"] is float and not is_equal_approx(data["schema_version"], roundf(data["schema_version"])):
		return _result(OUTCOME_WRONG_SCHEMA_VERSION, "schema_version must be an integer.")
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


## Generated model payloads cross both the Project0 semantic contract and the
## checked-in literal JSON Schema before downstream assembly. Canonical
## blueprints use validate() because their large tile arrays have already
## crossed this admission gate.
static func validate_generated(parsed_data: Variant) -> Dictionary:
	var semantic_result: Dictionary = validate(parsed_data)
	if semantic_result["outcome"] != OUTCOME_VALID:
		return semantic_result
	var contract: Dictionary = _load_contract()
	var literal_schema_error: String = _literal_schema_error(parsed_data, contract, contract, "$")
	if not literal_schema_error.is_empty():
		return _result(OUTCOME_INCOMPLETE, "Literal schema rejected payload at %s" % literal_schema_error)
	return semantic_result


static func contract_is_available() -> bool:
	return not _load_contract().is_empty()


static func _load_contract() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPATIAL_SCHEMA_PATH))
	if parsed is Dictionary and parsed.get("$id") == SPATIAL_SCHEMA_ID:
		return parsed
	return {}


static func _literal_schema_error(value: Variant, schema: Dictionary, root: Dictionary, path: String) -> String:
	if schema.has("$ref"):
		var definition_name: String = str(schema["$ref"]).get_file()
		var definitions: Dictionary = root.get("$defs", {})
		if not definitions.has(definition_name):
			return "%s unknown schema reference %s." % [path, schema["$ref"]]
		return _literal_schema_error(value, definitions[definition_name], root, path)

	var expected_type: String = schema.get("type", "")
	if not expected_type.is_empty() and not _matches_literal_type(value, expected_type):
		return "%s expected %s." % [path, expected_type]
	if schema.has("enum") and not _literal_enum_has(schema["enum"], value):
		return "%s is outside the allowed values." % path

	if value is String and schema.has("minLength") and (value as String).length() < int(schema["minLength"]):
		return "%s is shorter than minLength." % path
	if (value is int or value is float):
		var number: float = float(value)
		if schema.has("minimum") and number < float(schema["minimum"]):
			return "%s is below minimum." % path
		if schema.has("maximum") and number > float(schema["maximum"]):
			return "%s exceeds maximum." % path
		if schema.has("exclusiveMaximum") and number >= float(schema["exclusiveMaximum"]):
			return "%s reaches exclusiveMaximum." % path

	if value is Dictionary:
		var object: Dictionary = value
		for required_field: Variant in schema.get("required", []):
			if not object.has(required_field):
				return "%s%s is required." % [path, required_field]
		var properties: Dictionary = schema.get("properties", {})
		for property_name: Variant in properties:
			if object.has(property_name):
				var property_error: String = _literal_schema_error(object[property_name], properties[property_name], root, "%s%s." % [path, property_name])
				if not property_error.is_empty():
					return property_error

	if value is Array:
		var array: Array = value
		if schema.has("minItems") and array.size() < int(schema["minItems"]):
			return "%s has fewer than minItems." % path
		if schema.has("maxItems") and array.size() > int(schema["maxItems"]):
			return "%s exceeds maxItems." % path
		if schema.has("items"):
			for index: int in array.size():
				var item_error: String = _literal_schema_error(array[index], schema["items"], root, "%s%d." % [path, index])
				if not item_error.is_empty():
					return item_error

	return ""


static func _literal_enum_has(allowed_values: Array, value: Variant) -> bool:
	for allowed: Variant in allowed_values:
		if allowed == value:
			return true
		if (allowed is int or allowed is float) and (value is int or value is float) and is_equal_approx(float(allowed), float(value)):
			return true
	return false


static func _matches_literal_type(value: Variant, expected_type: String) -> bool:
	match expected_type:
		"object":
			return value is Dictionary
		"array":
			return value is Array
		"string":
			return value is String
		"integer":
			return value is int or (value is float and is_equal_approx(value, roundf(value)))
		"number":
			return value is int or value is float
	return false


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

	if kind == "house" and schema_version >= PROCEDURAL_GEOMETRY_MIN_VERSION:
		var footprint_check: Dictionary = _validate_house_footprint(structure, index)
		if footprint_check["outcome"] != OUTCOME_VALID:
			return footprint_check

	return _result(OUTCOME_VALID, "")


## Required only for `house`-kind entries at schema_version >=
## PROCEDURAL_GEOMETRY_MIN_VERSION (Feature #710, Epic #713). Earlier
## versions and every other structure kind are unaffected — they keep
## selecting a fixed per-kind prefab (backward compatibility).
static func _validate_house_footprint(structure: Dictionary, index: int) -> Dictionary:
	for field: String in ["footprint_width", "footprint_depth"]:
		if not structure.has(field):
			return _result(OUTCOME_INCOMPLETE, "structures[%d].%s is required for procedurally-generated houses." % [index, field])
		if not (structure[field] is int) and not (structure[field] is float):
			return _result(OUTCOME_INCOMPLETE, "structures[%d].%s must be a number." % [index, field])
		var value: float = float(structure[field])
		if value < MIN_FOOTPRINT_UNITS or value > MAX_FOOTPRINT_UNITS:
			return _result(OUTCOME_OUT_OF_BOUNDS, "structures[%d].%s must be in [%s, %s]." % [index, field, MIN_FOOTPRINT_UNITS, MAX_FOOTPRINT_UNITS])

	if not structure.has("roof_style"):
		return _result(OUTCOME_INCOMPLETE, "structures[%d].roof_style is required for procedurally-generated houses." % index)
	if not (structure["roof_style"] is String) or not SUPPORTED_ROOF_STYLES.has(structure["roof_style"]):
		return _result(OUTCOME_UNSUPPORTED_KIND, "structures[%d].roof_style '%s' is not a supported style (%s)." % [index, structure.get("roof_style"), ", ".join(SUPPORTED_ROOF_STYLES)])

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
