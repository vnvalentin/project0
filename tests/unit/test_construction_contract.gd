extends GutTest
## #840 pure closed construction contract; public-seam construction request tracers.

const CONTRACT_PATH: String = "res://shared/construction_contract.gd"
const LOCKED_VERBS: PackedStringArray = [
	"PLACE", "REMOVE", "ROTATE", "ANCHOR", "CONNECT", "REPAIR",
	"UPGRADE", "CLAIM", "PERMIT", "BLUEPRINT", "MEASURE", "INSPECT",
]


func test_place_request_preserves_pins_and_detaches_client_values() -> void:
	if not ResourceLoader.exists(CONTRACT_PATH):
		assert_true(false, "closed construction contract public seam is not implemented")
		return
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	assert_true(contract.has_method("parse_client_request"))
	if not contract.has_method("parse_client_request"):
		return
	var raw: Dictionary = _request()
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "ok")
	if parsed.get("outcome") != "ok":
		return
	var request: Dictionary = parsed["request"]
	assert_eq(request, {
		"schema_version": 1, "client_sequence": 7, "verb": "PLACE", "expected_revision": 0,
		"target": {"sector_id": "sector-0-0", "structure_guid": "fixture-structure-hall"},
		"grid": {"grid_id": "fixture-grid", "grid_revision": 1, "position": [-2, 0, 3]},
		"orientation_degrees": 90.0,
		"blueprint": {"schema_version": 1, "blueprint_id": "fixture-bridge", "blueprint_revision": "fixture-v1"},
		"materials": [{"instance_id": "fixture-material-1", "definition_id": "fixture-wood", "definition_revision": "fixture-v1", "instance_revision": 0, "quantity": 2}],
	})
	assert_true(request["orientation_degrees"] is float)
	raw["grid"]["position"][0] = 99
	raw["blueprint"]["blueprint_revision"] = "forged-v2"
	raw["materials"][0]["quantity"] = 99
	assert_eq(request["grid"]["position"], [-2, 0, 3])
	assert_eq(request["blueprint"]["blueprint_revision"], "fixture-v1")
	assert_eq(request["materials"][0]["quantity"], 2)


func test_cancel_action_is_excluded_from_the_closed_verb_set() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	var raw: Dictionary = _request()
	raw["verb"] = "CANCEL_ACTION"
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))


func test_all_locked_verbs_are_accepted() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	for verb: String in LOCKED_VERBS:
		var raw: Dictionary = _request()
		raw["verb"] = verb
		var parsed: Dictionary = contract.call("parse_client_request", raw)
		assert_eq(parsed.get("outcome"), "ok", "locked verb should parse: " + verb)


func test_nested_object_values_are_rejected() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	var raw: Dictionary = _request()
	raw["target"]["metadata"] = {"owner": RefCounted.new()}
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))


func test_cross_field_container_alias_is_rejected() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	var raw: Dictionary = _request()
	var shared_metadata: Array[String] = ["fixture"]
	raw["target"]["metadata"] = shared_metadata
	raw["grid"]["metadata"] = shared_metadata
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))
	var cyclic_metadata: Dictionary = {}
	cyclic_metadata["self"] = cyclic_metadata
	raw = _request()
	raw["target"]["metadata"] = cyclic_metadata
	parsed = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))
	cyclic_metadata.clear()


func test_request_depth_is_bounded() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	var raw: Dictionary = _request()
	var nested_value: Variant = "leaf"
	for _index in range(33):
		nested_value = [nested_value]
	raw["target"]["metadata"] = nested_value
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))


func test_request_node_count_is_bounded() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	var raw: Dictionary = _request()
	var metadata: Array[int] = []
	metadata.resize(4096)
	raw["target"]["metadata"] = metadata
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))


func test_request_container_count_is_bounded() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	var raw: Dictionary = _request()
	var metadata: Array = []
	for _index in range(257):
		metadata.append([])
	raw["target"]["metadata"] = metadata
	var parsed: Dictionary = contract.call("parse_client_request", raw)
	assert_eq(parsed.get("outcome"), "invalid_request")
	assert_null(parsed.get("request"))


func test_orientation_must_be_finite_and_canonical_degrees() -> void:
	var contract: Script = load(CONTRACT_PATH)
	assert_not_null(contract)
	if contract == null:
		return
	for angle: float in [-1.0, 360.0, INF, -INF, NAN]:
		var raw: Dictionary = _request()
		raw["orientation_degrees"] = angle
		var parsed: Dictionary = contract.call("parse_client_request", raw)
		assert_eq(parsed.get("outcome"), "invalid_request")
		assert_null(parsed.get("request"))
	for angle: float in [0.0, 359.999]:
		var raw: Dictionary = _request()
		raw["orientation_degrees"] = angle
		var parsed: Dictionary = contract.call("parse_client_request", raw)
		assert_eq(parsed.get("outcome"), "ok")
		if parsed.get("outcome") == "ok":
			assert_true(parsed["request"]["orientation_degrees"] is float)


func _request() -> Dictionary:
	return {
		"schema_version": 1, "client_sequence": 7, "verb": "PLACE", "expected_revision": 0,
		"target": {"sector_id": "sector-0-0", "structure_guid": "fixture-structure-hall"},
		"grid": {"grid_id": "fixture-grid", "grid_revision": 1, "position": [-2, 0, 3]},
		"orientation_degrees": 90,
		"blueprint": {"schema_version": 1, "blueprint_id": "fixture-bridge", "blueprint_revision": "fixture-v1"},
		"materials": [{"instance_id": "fixture-material-1", "definition_id": "fixture-wood", "definition_revision": "fixture-v1", "instance_revision": 0, "quantity": 2}],
	}
