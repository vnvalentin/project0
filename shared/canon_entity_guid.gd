extends RefCounted
class_name CanonEntityGuid
## Slice 095 (P-013): pure, deterministic, restart-stable identity for the
## addressable entities of a canonical sector blueprint. Both the server (which
## admits mutations) and the client (which will later render/replay them) must
## agree on entity identity, so the *algorithm* lives in shared/. This helper
## has no store, no HTTP, no async, and references no server-only or client-only
## type — it reads validated blueprint Dictionaries only.
##
## A GUID is a SHA-256 digest of the canonical (sector_id, entity_class,
## entity_id) tuple, prefixed with the entity class for debuggability. Using
## SHA-256 (not Godot's engine hash()) keeps identity stable across restarts and
## across Godot versions, which matters because mutation events reference these
## GUIDs in durable Canon.

const ENTITY_CLASS_STRUCTURE: String = "structure"
const ENTITY_CLASS_SPAWN_POINT: String = "spawn_point"
const NAMESPACE_DNS_UUID: String = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
const NAMESPACE_URL_UUID: String = "6ba7b811-9dad-11d1-80b4-00c04fd430c8"

## Length of the hex digest kept after the class prefix. 32 hex chars = 128 bits
## of the SHA-256, collision-resistant for world-entity counts and far under the
## mutation log's MAX_ID_LENGTH (128).
const _DIGEST_LENGTH: int = 32

## Field separator that cannot appear in a JSON string id, so distinct tuples
## can never collide into the same canonical form.
const _SEPARATOR: String = "\u0001"


## The stable GUID for one addressable entity. Deterministic: a pure function of
## the tuple, with no clock, randomness, or stored column.
static func derive(sector_id: String, entity_class: String, entity_id: String) -> String:
	var canonical: String = "%s%s%s%s%s" % [sector_id, _SEPARATOR, entity_class, _SEPARATOR, entity_id]
	return "%s-%s" % [entity_class, canonical.sha256_text().substr(0, _DIGEST_LENGTH)]


static func derive_rfc4122_v5(sector_id: String, entity_class: String, entity_id: String) -> String:
	var canonical: String = "project0%s%s%s%s%s" % [
		_SEPARATOR,
		sector_id,
		_SEPARATOR,
		entity_class,
		_SEPARATOR + entity_id,
	]
	return uuid_v5(NAMESPACE_URL_UUID, canonical)


static func uuid_v5(namespace_uuid: String, name: String) -> String:
	var namespace_bytes: PackedByteArray = _uuid_to_bytes(namespace_uuid)
	if namespace_bytes.size() != 16:
		return ""

	var hashing_context: HashingContext = HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA1) != OK:
		return ""
	hashing_context.update(namespace_bytes)
	hashing_context.update(name.to_utf8_buffer())
	var digest: PackedByteArray = hashing_context.finish().slice(0, 16)
	digest[6] = (digest[6] & 0x0f) | 0x50
	digest[8] = (digest[8] & 0x3f) | 0x80

	var hex: String = digest.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]


static func _uuid_to_bytes(uuid: String) -> PackedByteArray:
	var compact: String = uuid.replace("-", "")
	if compact.length() != 32 or not compact.is_valid_hex_number():
		return PackedByteArray()
	var bytes: PackedByteArray = PackedByteArray()
	for index: int in range(0, compact.length(), 2):
		bytes.append(compact.substr(index, 2).hex_to_int())
	return bytes


## Every addressable entity in a validated blueprint, each as
## {guid, entity_class, entity_id, kind}. A tiles-only sector (or any non-object
## input) yields an empty array; identity derives from the blueprint's own
## sector_id, so it needs no external context.
static func list_entities(blueprint: Variant) -> Array:
	var entities: Array = []
	if not (blueprint is Dictionary):
		return entities
	var data: Dictionary = blueprint
	if not (data.get("sector_id") is String) or (data["sector_id"] as String).is_empty():
		return entities
	var sector_id: String = data["sector_id"]

	if data.get("structures") is Array:
		for entry: Variant in data["structures"]:
			_append_entity(entities, entry, "structure_id", ENTITY_CLASS_STRUCTURE, sector_id)
	if data.get("spawn_points") is Array:
		for entry: Variant in data["spawn_points"]:
			_append_entity(entities, entry, "spawn_id", ENTITY_CLASS_SPAWN_POINT, sector_id)

	return entities


## Whether a GUID addresses a real entity in this blueprint.
static func contains_guid(blueprint: Variant, guid: Variant) -> bool:
	if not (guid is String) or (guid as String).is_empty():
		return false
	for entity: Dictionary in list_entities(blueprint):
		if entity["guid"] == guid:
			return true
	return false


static func _append_entity(entities: Array, entry: Variant, id_field: String, entity_class: String, sector_id: String) -> void:
	if not (entry is Dictionary):
		return
	var record: Dictionary = entry
	if not (record.get(id_field) is String) or (record[id_field] as String).is_empty():
		return
	var entity_id: String = record[id_field]
	var kind: Variant = record.get("kind")
	entities.append({
		"guid": derive(sector_id, entity_class, entity_id),
		"entity_class": entity_class,
		"entity_id": entity_id,
		"kind": kind if kind is String else "",
	})
