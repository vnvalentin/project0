extends GutTest
## #840 pure closed construction contract; first public-seam tracer only.

const CONTRACT_PATH: String = "res://shared/construction_contract.gd"


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


func _request() -> Dictionary:
	return {
		"schema_version": 1, "client_sequence": 7, "verb": "PLACE", "expected_revision": 0,
		"target": {"sector_id": "sector-0-0", "structure_guid": "fixture-structure-hall"},
		"grid": {"grid_id": "fixture-grid", "grid_revision": 1, "position": [-2, 0, 3]},
		"orientation_degrees": 90,
		"blueprint": {"schema_version": 1, "blueprint_id": "fixture-bridge", "blueprint_revision": "fixture-v1"},
		"materials": [{"instance_id": "fixture-material-1", "definition_id": "fixture-wood", "definition_revision": "fixture-v1", "instance_revision": 0, "quantity": 2}],
	}
