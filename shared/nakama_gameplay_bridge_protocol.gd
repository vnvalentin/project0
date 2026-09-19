extends RefCounted
class_name NakamaGameplayBridgeProtocol
## Slice 170: transport-neutral protocol contract for the future Nakama socket
## adapter. This file contains no Nakama SDK or network authority.

const SCHEMA_VERSION: int = 1
const MAX_ID_LENGTH: int = 256
const MAX_PAYLOAD_JSON_LENGTH: int = 2048

const KIND_INPUT: String = "input"
const KIND_STATE: String = "state"
const KIND_PRESENCE: String = "presence"
const KIND_ERROR: String = "error"

const OUTCOME_OK: String = "ok"
const REASON_MALFORMED: String = "malformed"
const REASON_UNSUPPORTED_VERSION: String = "unsupported_version"
const REASON_UNSUPPORTED_KIND: String = "unsupported_kind"
const REASON_INVALID_IDENTITY: String = "invalid_identity"
const REASON_INVALID_SEQUENCE: String = "invalid_sequence"
const REASON_INVALID_PAYLOAD: String = "invalid_payload"
const REASON_AUTHORITY_FIELD: String = "authority_field_forbidden"

const _KINDS: Array[String] = [KIND_INPUT, KIND_STATE, KIND_PRESENCE, KIND_ERROR]


static func build_input(nakama_user_id: String, character_id: String, sequence: int, payload: Dictionary) -> Dictionary:
	return _build(KIND_INPUT, nakama_user_id, character_id, sequence, payload)


static func build_state(nakama_user_id: String, character_id: String, server_tick: int, position: Vector3, payload: Dictionary = {}) -> Dictionary:
	var state_payload: Dictionary = payload.duplicate(true)
	state_payload["position"] = {"x": position.x, "y": position.y, "z": position.z}
	state_payload["server_tick"] = server_tick
	return _build(KIND_STATE, nakama_user_id, character_id, server_tick, state_payload)


static func build_presence(nakama_user_id: String, character_id: String, status: String) -> Dictionary:
	return _build(KIND_PRESENCE, nakama_user_id, character_id, 0, {"status": status})


static func build_error(code: String, detail: String) -> Dictionary:
	return _build(KIND_ERROR, "", "", 0, {"code": code, "detail": detail})


static func validate(message: Variant, expected_kind: String = "") -> Dictionary:
	if not (message is Dictionary):
		return _reject(REASON_MALFORMED)
	var envelope: Dictionary = message
	if int(envelope.get("version", 0)) != SCHEMA_VERSION:
		return _reject(REASON_UNSUPPORTED_VERSION)
	var kind: String = String(envelope.get("kind", ""))
	if not _KINDS.has(kind) or (not expected_kind.is_empty() and kind != expected_kind):
		return _reject(REASON_UNSUPPORTED_KIND)
	var user_id: String = String(envelope.get("nakama_user_id", ""))
	var character_id: String = String(envelope.get("character_id", ""))
	if kind != KIND_ERROR and not _valid_id(user_id):
		return _reject(REASON_INVALID_IDENTITY)
	if kind != KIND_ERROR and not _valid_id(character_id):
		return _reject(REASON_INVALID_IDENTITY)
	var sequence: int = int(envelope.get("sequence", 0))
	if kind == KIND_INPUT and sequence <= 0:
		return _reject(REASON_INVALID_SEQUENCE)
	var payload: Variant = envelope.get("payload", null)
	if not (payload is Dictionary) or JSON.stringify(payload).length() > MAX_PAYLOAD_JSON_LENGTH:
		return _reject(REASON_INVALID_PAYLOAD)
	if kind == KIND_INPUT:
		for forbidden: String in ["position", "server_tick", "outcome", "damage", "authoritative"]:
			if payload.has(forbidden):
				return _reject(REASON_AUTHORITY_FIELD)
	return {"outcome": OUTCOME_OK, "message": envelope}


static func _build(kind: String, nakama_user_id: String, character_id: String, sequence: int, payload: Dictionary) -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"kind": kind,
		"nakama_user_id": nakama_user_id,
		"character_id": character_id,
		"sequence": sequence,
		"payload": payload.duplicate(true),
	}


static func _valid_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and value.length() <= MAX_ID_LENGTH


static func _reject(reason: String) -> Dictionary:
	return {"outcome": reason}