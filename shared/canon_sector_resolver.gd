extends RefCounted
class_name CanonSectorResolver
## Slice 098 (P-013): pure, deterministic replay of a sector's mutation log onto
## its canonical blueprint, producing the effective blueprint the server
## replicates so a loaded/revisited sector reflects durable changes. No store, no
## async — both processes could interpret it, so it lives in shared/, though the
## server is the one that applies it before replication.
##
## The only geometry-affecting kind today is destroy_structure: a structure whose
## derived CanonEntityGuid matches such a mutation's target_guid is removed. Other
## kinds (loot/defeat_leader/clear_camp) remain in the durable log but do not yet
## map to rendered geometry, so they are inert here. Removal is order-independent
## and idempotent, and the result stays schema-valid (structures are optional).

const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")

const MUTATION_DESTROY_STRUCTURE: String = "destroy_structure"


## Returns a duplicated blueprint with destroyed structures removed. A non-dict
## blueprint, a structureless sector, or a log with no destroy_structure entries
## returns the blueprint effectively unchanged (never mutated in place).
static func resolve_effective_blueprint(blueprint: Variant, mutations: Array) -> Variant:
	if not (blueprint is Dictionary):
		return blueprint
	var data: Dictionary = (blueprint as Dictionary).duplicate(true)
	if not (data.get("structures") is Array) or (data["structures"] as Array).is_empty():
		return data
	if not (data.get("sector_id") is String) or (data["sector_id"] as String).is_empty():
		return data
	var sector_id: String = data["sector_id"]

	var destroyed_guids: Dictionary = {}
	for mutation: Variant in mutations:
		if mutation is Dictionary and (mutation as Dictionary).get("mutation_kind") == MUTATION_DESTROY_STRUCTURE:
			var target_guid: Variant = (mutation as Dictionary).get("target_guid")
			if target_guid is String:
				destroyed_guids[target_guid] = true
	if destroyed_guids.is_empty():
		return data

	var live_structures: Array = []
	for structure: Variant in data["structures"]:
		if not (structure is Dictionary) or not ((structure as Dictionary).get("structure_id") is String):
			live_structures.append(structure)
			continue
		var guid: String = CanonEntityGuidScript.derive(sector_id, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, (structure as Dictionary)["structure_id"])
		if not destroyed_guids.has(guid):
			live_structures.append(structure)
	data["structures"] = live_structures
	return data
