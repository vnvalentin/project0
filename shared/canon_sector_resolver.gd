extends RefCounted
class_name CanonSectorResolver
## Slice 098 (P-013): pure, deterministic replay of a sector's mutation log onto
## its canonical blueprint, producing the effective blueprint the server
## replicates so a loaded/revisited sector reflects durable changes. No store, no
## async — both processes could interpret it, so it lives in shared/, though the
## server is the one that applies it before replication.
##
## Geometry-affecting mutations include destroying a structure and unlocking a
## gate. Other kinds (loot/defeat_leader/clear_camp) remain in the durable log
## but do not yet map to rendered geometry, so they are inert here. Replay is
## order-independent and idempotent, and the result stays schema-valid.

const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")

const MUTATION_DESTROY_STRUCTURE: String = "destroy_structure"
const MUTATION_UNLOCK_GATE: String = "unlock_gate"


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
	var unlocked_guids: Dictionary = {}
	for mutation: Variant in mutations:
		if not mutation is Dictionary:
			continue
		var mutation_data: Dictionary = mutation
		var target_guid: Variant = mutation_data.get("target_guid")
		if target_guid is String and mutation_data.get("mutation_kind") == MUTATION_DESTROY_STRUCTURE:
				destroyed_guids[target_guid] = true
		if target_guid is String and mutation_data.get("mutation_kind") == MUTATION_UNLOCK_GATE:
			if bool(mutation_data.get("payload", {}).get("unlocked", false)):
				unlocked_guids[target_guid] = true
	if destroyed_guids.is_empty() and unlocked_guids.is_empty():
		return data

	var live_structures: Array = []
	for structure: Variant in data["structures"]:
		if not (structure is Dictionary) or not ((structure as Dictionary).get("structure_id") is String):
			live_structures.append(structure)
			continue
		var record: Dictionary = structure
		var guid: String = CanonEntityGuidScript.guid_for_entity(record, sector_id, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, record["structure_id"])
		if destroyed_guids.has(guid):
			continue
		if unlocked_guids.has(guid):
			var effective_record: Dictionary = record.duplicate(true)
			effective_record["unlocked"] = true
			live_structures.append(effective_record)
			continue
		live_structures.append(structure)
	data["structures"] = live_structures
	return data
