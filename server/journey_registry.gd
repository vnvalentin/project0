extends RefCounted
class_name JourneyRegistry
## Slice 1143: server-owned in-memory journey ownership for shared-world entry.
## A journey survives a clean peer disconnect for a bounded reclaim window, but
## only a validated server-side Character identity can claim it.

const OUTCOME_OK: String = "ok"
const REASON_INVALID_CHARACTER: String = "invalid_character"
const REASON_CHARACTER_ACTIVE: String = "character_active"
const REASON_JOURNEY_EXPIRED: String = "journey_expired"
const REASON_PEER_MISMATCH: String = "peer_mismatch"
const RECLAIM_WINDOW_SECONDS: int = 300

var _journeys_by_id: Dictionary = {}
var _journey_id_by_character: Dictionary = {}
var _next_id: int = 1
signal evidence(kind: String, payload: Dictionary)


func enter(character_id: String, peer_id: int, now_unix: int) -> Dictionary:
	if character_id.strip_edges().is_empty() or peer_id < 1:
		return _rejection(REASON_INVALID_CHARACTER, character_id, peer_id)
	_cleanup_expired(now_unix)
	var journey_id: String = String(_journey_id_by_character.get(character_id, ""))
	if journey_id.is_empty():
		journey_id = _new_journey_id()
		_journeys_by_id[journey_id] = {
			"journey_id": journey_id,
			"character_id": character_id,
			"peer_id": peer_id,
			"active": true,
			"disconnected_at": 0,
		}
		_journey_id_by_character[character_id] = journey_id
		return _accepted("entry", journey_id, character_id, peer_id)

	var journey: Dictionary = _journeys_by_id[journey_id]
	if bool(journey.get("active", false)):
		if int(journey.get("peer_id", -1)) == peer_id:
			return _accepted("entry", journey_id, character_id, peer_id)
		return _rejection(REASON_CHARACTER_ACTIVE, character_id, peer_id, journey_id)

	var disconnected_at: int = int(journey.get("disconnected_at", 0))
	if disconnected_at <= 0 or now_unix - disconnected_at > RECLAIM_WINDOW_SECONDS:
		_journeys_by_id.erase(journey_id)
		_journey_id_by_character.erase(character_id)
		return _rejection(REASON_JOURNEY_EXPIRED, character_id, peer_id, journey_id)
	journey["peer_id"] = peer_id
	journey["active"] = true
	journey["disconnected_at"] = 0
	return _accepted("reclaim", journey_id, character_id, peer_id)


func mark_disconnected(character_id: String, peer_id: int, now_unix: int) -> Dictionary:
	var journey_id: String = String(_journey_id_by_character.get(character_id, ""))
	if journey_id.is_empty() or not _journeys_by_id.has(journey_id):
		return _rejection(REASON_INVALID_CHARACTER, character_id, peer_id)
	var journey: Dictionary = _journeys_by_id[journey_id]
	if not bool(journey.get("active", false)) or int(journey.get("peer_id", -1)) != peer_id:
		return _rejection(REASON_PEER_MISMATCH, character_id, peer_id, journey_id)
	journey["active"] = false
	journey["disconnected_at"] = now_unix
	return _accepted("disconnect", journey_id, character_id, peer_id)


func cleanup(now_unix: int) -> Array[Dictionary]:
	var cleaned: Array[Dictionary] = []
	for journey_id: String in _journeys_by_id.keys():
		var journey: Dictionary = _journeys_by_id[journey_id]
		if bool(journey.get("active", false)):
			continue
		if now_unix - int(journey.get("disconnected_at", 0)) <= RECLAIM_WINDOW_SECONDS:
			continue
		var record: Dictionary = {"journey_id": journey_id, "character_id": String(journey["character_id"])}
		cleaned.append(record)
		evidence.emit("cleanup", record)
		_journeys_by_id.erase(journey_id)
		_journey_id_by_character.erase(String(journey["character_id"]))
	return cleaned


func _cleanup_expired(now_unix: int) -> void:
	cleanup(now_unix)


func _new_journey_id() -> String:
	var journey_id: String = "journey-%d" % _next_id
	_next_id += 1
	return journey_id


func _accepted(kind: String, journey_id: String, character_id: String, peer_id: int) -> Dictionary:
	var result: Dictionary = {
		"outcome": OUTCOME_OK,
		"kind": kind,
		"journey_id": journey_id,
		"character_id": character_id,
		"peer_id": peer_id,
	}
	evidence.emit(kind, {"journey_id": journey_id, "character_id": character_id, "peer_id": peer_id})
	return result


func _rejection(reason: String, character_id: String, peer_id: int, journey_id: String = "") -> Dictionary:
	var result: Dictionary = {
		"outcome": reason,
		"reason": reason,
		"journey_id": journey_id,
		"character_id": character_id,
		"peer_id": peer_id,
	}
	evidence.emit("rejection", {"reason": reason, "journey_id": journey_id, "character_id": character_id, "peer_id": peer_id})
	return result