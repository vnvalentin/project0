extends RefCounted
class_name ItemCapacityBindings
## Immutable supplied authored set. No registration, fallback or item authority.

const CapacityScript = preload("res://shared/item_capacity_profile.gd")
const DefinitionScript = preload("res://shared/item_definition.gd")

var _by_definition: Dictionary


func _init(by_definition: Dictionary) -> void:
	_by_definition = by_definition.duplicate(true)


static func from_wire_profiles(value: Variant) -> Dictionary:
	if not (value is Array):
		return _fail("malformed", "authored capacity profiles must be an array")
	var authored: Array = value
	var definitions: Dictionary = {}
	var profiles: Dictionary = {}
	for member: Variant in authored:
		var parsed: Dictionary = CapacityScript.from_wire_dict(member)
		if parsed.outcome != "ok":
			return _fail(String(parsed.outcome), String(parsed.detail))
		var profile: ItemCapacityProfile = parsed.profile
		var wire: Dictionary = profile.to_wire_dict()
		if _conflicts(definitions, wire.definition_id, wire.definition_revision, wire) \
			or _conflicts(profiles, wire.profile_id, wire.profile_revision, wire):
			return _fail("immutable_profile_conflict", "authored capacity pins have conflicting content")
		_bind(definitions, wire.definition_id, wire.definition_revision, wire)
		_bind(profiles, wire.profile_id, wire.profile_revision, wire)
	return {"outcome": "ok", "detail": "", "bindings": ItemCapacityBindings.new(definitions)}


func resolve(definition: ItemDefinition) -> Dictionary:
	if definition == null:
		return _resolution_fail("definition_mismatch", "capacity requires a valid bag definition")
	var checked: Dictionary = DefinitionScript.from_wire_dict(definition.to_wire_dict())
	if checked.outcome != "ok":
		return _resolution_fail("definition_mismatch", "capacity requires a valid bag definition")
	var validated: ItemDefinition = checked.definition
	var wire: Dictionary = validated.to_wire_dict()
	if wire.slot != "bags":
		return _resolution_fail("definition_mismatch", "capacity requires a valid bag definition")
	if not _by_definition.has(wire.definition_id):
		return _resolution_fail("missing_profile", "no capacity profile for exact definition pins")
	var revision_value: Variant = _by_definition[wire.definition_id]
	if not (revision_value is Dictionary):
		return _resolution_fail("definition_mismatch", "bound capacity profile does not match definition")
	var revisions: Dictionary = revision_value
	if not revisions.has(wire.definition_revision):
		return _resolution_fail("missing_profile", "no capacity profile for exact definition pins")
	var parsed: Dictionary = CapacityScript.from_wire_dict(revisions[wire.definition_revision])
	if parsed.outcome != "ok":
		return _resolution_fail("definition_mismatch", "bound capacity profile does not match definition")
	var profile: ItemCapacityProfile = parsed.profile
	var snapshot: Dictionary = profile.to_wire_dict()
	if snapshot.definition_id != wire.definition_id or snapshot.definition_revision != wire.definition_revision:
		return _resolution_fail("definition_mismatch", "bound capacity profile does not match definition")
	return {"outcome": "ok", "detail": "", "profile": profile}


static func _conflicts(mapping: Dictionary, identity: String, revision: String, wire: Dictionary) -> bool:
	if not mapping.has(identity):
		return false
	var revisions: Dictionary = mapping[identity]
	return revisions.has(revision) and revisions[revision] != wire


static func _bind(mapping: Dictionary, identity: String, revision: String, wire: Dictionary) -> void:
	var revisions: Dictionary = mapping.get(identity, {})
	revisions[revision] = wire.duplicate(true)
	mapping[identity] = revisions


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "bindings": null}


static func _resolution_fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "profile": null}
