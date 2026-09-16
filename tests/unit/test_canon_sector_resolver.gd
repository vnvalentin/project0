extends GutTest
## Slice 098 (P-013): pure replay of a sector's mutation log onto its canonical
## blueprint. The geometry-affecting kind today is destroy_structure; the
## resolver removes the matching structure and leaves everything else intact.

const CanonSectorResolverScript: Script = preload("res://shared/canon_sector_resolver.gd")
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
	}


func _guid(structure_id: String) -> String:
	return CanonEntityGuidScript.derive("sector-0-0", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, structure_id)


func _destroy(structure_id: String) -> Dictionary:
	return {"mutation_kind": "destroy_structure", "target_guid": _guid(structure_id)}


func _structure_ids(blueprint: Dictionary) -> Array:
	var ids: Array = []
	for structure: Dictionary in blueprint.get("structures", []):
		ids.append(structure["structure_id"])
	return ids


func test_no_mutations_returns_blueprint_unchanged() -> void:
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_blueprint(), [])
	assert_eq(_structure_ids(effective), ["village_hall", "smithy_1"])


func test_destroy_structure_removes_the_matching_structure() -> void:
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_blueprint(), [_destroy("smithy_1")])
	assert_eq(_structure_ids(effective), ["village_hall"], "the destroyed structure is gone; the rest remain")


func test_resolver_does_not_mutate_the_input_blueprint() -> void:
	var original: Dictionary = _blueprint()
	CanonSectorResolverScript.resolve_effective_blueprint(original, [_destroy("smithy_1")])
	assert_eq(_structure_ids(original), ["village_hall", "smithy_1"], "the source blueprint is not modified in place")


func test_non_matching_target_leaves_all_structures() -> void:
	var stray: Dictionary = {"mutation_kind": "destroy_structure", "target_guid": "structure-does-not-exist"}
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_blueprint(), [stray])
	assert_eq(_structure_ids(effective), ["village_hall", "smithy_1"])


func test_multiple_destroys_remove_each() -> void:
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_blueprint(), [_destroy("village_hall"), _destroy("smithy_1")])
	assert_eq(_structure_ids(effective), [], "both destroyed structures are removed")


func test_non_geometry_kinds_are_inert() -> void:
	var mutations: Array = [
		{"mutation_kind": "defeat_leader", "target_guid": _guid("village_hall")},
		{"mutation_kind": "loot", "target_guid": _guid("smithy_1")},
	]
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_blueprint(), mutations)
	assert_eq(_structure_ids(effective), ["village_hall", "smithy_1"], "non-destroy kinds do not change geometry")


func test_tiles_only_blueprint_is_unchanged() -> void:
	var bare: Dictionary = {
		"schema_version": 1,
		"sector_id": "sector-0-0",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(bare, [_destroy("village_hall")])
	assert_eq(effective.get("structures", []), [])


func test_non_dictionary_blueprint_is_returned_as_is() -> void:
	assert_eq(CanonSectorResolverScript.resolve_effective_blueprint("nope", [_destroy("x")]), "nope")
