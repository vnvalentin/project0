extends GutTest
## Slice 095 (P-013): pure, deterministic, restart-stable GUIDs for the
## addressable entities of a canonical sector blueprint. No store, no async —
## the helper is exercised with plain Dictionary blueprints so identity is
## proven independently of persistence.

const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")


func _blueprint() -> Dictionary:
	return {
		"schema_version": 3,
		"sector_id": "sector-0-0",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
		"structures": [
			{"structure_id": "village_hall", "kind": "village_hall", "x": 0, "y": 0, "facing_degrees": 0},
			{"structure_id": "smithy_1", "kind": "smithy", "x": 3, "y": 2, "facing_degrees": 90},
		],
		"spawn_points": [
			{"spawn_id": "spawn_a", "x": 5, "y": 5},
		],
	}


func test_derive_is_deterministic() -> void:
	var a: String = CanonEntityGuidScript.derive("sector-0-0", "structure", "village_hall")
	var b: String = CanonEntityGuidScript.derive("sector-0-0", "structure", "village_hall")
	assert_eq(a, b, "the same tuple always derives the same GUID (restart-stable)")


func test_derive_distinguishes_entities() -> void:
	var hall: String = CanonEntityGuidScript.derive("sector-0-0", "structure", "village_hall")
	var smithy: String = CanonEntityGuidScript.derive("sector-0-0", "structure", "smithy_1")
	var other_sector: String = CanonEntityGuidScript.derive("sector-1-0", "structure", "village_hall")
	var spawn: String = CanonEntityGuidScript.derive("sector-0-0", "spawn_point", "village_hall")
	assert_ne(hall, smithy, "different entity ids derive different GUIDs")
	assert_ne(hall, other_sector, "the same entity id in a different sector is a different GUID")
	assert_ne(hall, spawn, "the same id in a different entity class is a different GUID")


func test_derive_is_bounded_and_prefixed() -> void:
	var guid: String = CanonEntityGuidScript.derive("sector-0-0", "structure", "village_hall")
	assert_true(guid.begins_with("structure-"), "the GUID is prefixed with its entity class for debuggability")
	assert_lt(guid.length(), 128, "the GUID stays well under the mutation log's MAX_ID_LENGTH")


func test_list_entities_enumerates_structures_and_spawns() -> void:
	var entities: Array = CanonEntityGuidScript.list_entities(_blueprint())
	assert_eq(entities.size(), 3, "two structures and one spawn point are addressable")
	var guids: Array = []
	for entity: Dictionary in entities:
		guids.append(entity["guid"])
	assert_true(guids.has(CanonEntityGuidScript.derive("sector-0-0", "structure", "village_hall")))
	assert_true(guids.has(CanonEntityGuidScript.derive("sector-0-0", "structure", "smithy_1")))
	assert_true(guids.has(CanonEntityGuidScript.derive("sector-0-0", "spawn_point", "spawn_a")))


func test_contains_guid_true_for_real_entity() -> void:
	var guid: String = CanonEntityGuidScript.derive("sector-0-0", "structure", "village_hall")
	assert_true(CanonEntityGuidScript.contains_guid(_blueprint(), guid))


func test_contains_guid_false_for_unknown() -> void:
	assert_false(CanonEntityGuidScript.contains_guid(_blueprint(), "structure-does-not-exist"))
	assert_false(CanonEntityGuidScript.contains_guid(_blueprint(), ""))


func test_list_entities_on_blueprint_without_entities_is_empty() -> void:
	var bare: Dictionary = {
		"schema_version": 1,
		"sector_id": "sector-0-0",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}
	assert_eq(CanonEntityGuidScript.list_entities(bare).size(), 0, "a tiles-only sector has no addressable entities")


func test_non_dictionary_blueprint_yields_no_entities() -> void:
	assert_eq(CanonEntityGuidScript.list_entities("not-a-dict").size(), 0)
	assert_false(CanonEntityGuidScript.contains_guid(null, "structure-x"))
