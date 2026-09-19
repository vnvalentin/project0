extends RefCounted
class_name NakamaPresence
## Slice 171: bounded, server-authored presence snapshot for the shared v1
## playtest world. This contract carries presentation/routing state only.

const SCHEMA_VERSION: int = 1
const MAX_ENTRIES: int = 10
const MAX_ID_LENGTH: int = 256
const OUTCOME_OK: String = "ok"
const REASON_MALFORMED: String = "malformed"
const REASON_TOO_MANY: String = "too_many_entries"


static func build(entries: Array[Dictionary], available: bool = true) -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"world_id": "starting_town_shared",
		"available": available,
		"entries": entries.duplicate(true),
	}


static func entry(peer_id: int, account_id: String, character_id: String, display_name: String, status: String = "online") -> Dictionary:
	return {
		"peer_id": peer_id,
		"account_id": account_id,
		"character_id": character_id,
		"display_name": display_name,
		"status": status,
	}


static func validate(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary:
		return {"outcome": REASON_MALFORMED}
	var value: Dictionary = snapshot
	if int(value.get("version", 0)) != SCHEMA_VERSION:
		return {"outcome": REASON_MALFORMED}
	if String(value.get("world_id", "")).is_empty() or not (value.get("entries", null) is Array):
		return {"outcome": REASON_MALFORMED}
	var entries: Array = value["entries"]
	if entries.size() > MAX_ENTRIES:
		return {"outcome": REASON_TOO_MANY}
	var seen: Dictionary = {}
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			return {"outcome": REASON_MALFORMED}
		var peer_entry: Dictionary = raw_entry
		var peer_id: int = int(peer_entry.get("peer_id", -1))
		var account_id: String = String(peer_entry.get("account_id", ""))
		var character_id: String = String(peer_entry.get("character_id", ""))
		if peer_id <= 0 or seen.has(peer_id) or not _valid_id(account_id) or not _valid_id(character_id):
			return {"outcome": REASON_MALFORMED}
		seen[peer_id] = true
	return {"outcome": OUTCOME_OK, "snapshot": value}


static func _valid_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and value.length() <= MAX_ID_LENGTH