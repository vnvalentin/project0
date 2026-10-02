extends GutTest
## #849 pure public contract; identity fixture independently calculated by RFC UUIDv5.

const Contract: Script = preload("res://shared/interior_anchor_contract.gd")


func test_blank_identifiers_are_not_accepted_as_anchor_references() -> void:
	for field: String in ["exterior_sector_id", "exterior_entity_guid", "plot_id", "streaming_reference"]:
		var descriptor: Dictionary = _descriptor()
		descriptor[field] = " \t "
		assert_eq(Contract.parse_server_descriptor(descriptor)["outcome"], "invalid_anchor", field)


func _descriptor() -> Dictionary:
	return {
		"schema_version": 1,
		"exterior_sector_id": "sector-0-0",
		"exterior_entity_guid": "e4c0d17b-697f-5a6c-a379-7dab847fca3b",
		"plot_id": "plot-village-hall",
		"entry_position": [0, 0, 0], "cell_coordinate": [0, 0, 0],
		"bounds_min": [-2, -1, -2], "bounds_max": [2, 3, 2],
		"streaming_reference": "interior/village-hall/0-0-0",
	}


func test_pinned_identity_matches_known_uuid_and_snapshots_do_not_alias() -> void:
	var descriptor: Dictionary = _descriptor()
	var parsed: Dictionary = Contract.parse_server_descriptor(descriptor)
	assert_eq(parsed["outcome"], "ok")
	var anchor: InteriorAnchorContract.AnchorValue = parsed["anchor"]
	# Independently calculated with RFC4122 UUIDv5 / Python standard uuid module.
	assert_eq(anchor.interior_id, "8b916e9a-bf39-57a1-8f68-21d0c1e9ddf1")
	var retained: Dictionary = anchor.to_dict()
	var serialized: String = JSON.stringify(retained)
	assert_eq(Contract.parse_record(JSON.parse_string(serialized))["anchor"].to_dict(), retained)
	descriptor["entry_position"][0] = 999
	var returned: Dictionary = anchor.to_dict()
	returned["bounds_max"][0] = 999
	assert_eq(anchor.to_dict(), retained)
	var forged: Dictionary = retained.duplicate(true)
	forged["interior_id"] = "client-selected-interior"
	assert_eq(Contract.parse_record(forged)["outcome"], "invalid_anchor")
	forged = retained.duplicate(true)
	forged["revision"] = 2
	assert_eq(Contract.parse_record(forged)["outcome"], "invalid_anchor")
