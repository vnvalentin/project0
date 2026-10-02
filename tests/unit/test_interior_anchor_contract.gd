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
