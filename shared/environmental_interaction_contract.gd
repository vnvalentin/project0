extends RefCounted
class_name EnvironmentalInteractionContract
## M0.4 shared wire contract for one human-selected environmental solution.
## The client submits a verb and physical request context; the server owns actor
## identity, position, line of sight, execution profile, mutation and outcome.

const SCHEMA_VERSION: int = 1
const VERB_LOCK_PICK: String = "lock_pick"
const VERB_INTERRUPT: String = "interrupt"
const SUPPORTED_VERBS: PackedStringArray = [VERB_LOCK_PICK, VERB_INTERRUPT]

const MAX_ID_LENGTH: int = 128
const MAX_REVISION: int = 1073741824
const MAX_CLIENT_SEQ: int = 1073741824
const MAX_DIRECTION_LENGTH: float = 1.0

const OUTCOME_OK: String = "ok"
const OUTCOME_INVALID: String = "invalid"

const _SERVER_OWNED_FIELDS: PackedStringArray = [
	"actor_player_id",
	"event_id",
	"server_tick",
	"success",
	"execution_profile",
	"applied_revision",
]


static func build_intent(
	sector_id: String,
	target_guid: String,
	verb: String,
	expected_revision: int,
	approach_direction: Vector3,
	client_seq: int
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"sector_id": sector_id,
		"target_guid": target_guid,
		"verb": verb,
		"expected_revision": expected_revision,
		"approach_direction": approach_direction,
		"client_seq": client_seq,
	}


## Parses an untrusted interaction request into the bounded shared shape.
## Physical authority remains server-side even though direction is carried for
## the server's execution calculation.
static func parse_intent(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return _invalid("intent must be a Dictionary")
	var data: Dictionary = value
	for field: String in _SERVER_OWNED_FIELDS:
		if data.has(field):
			return _invalid("intent must not carry server-owned field '%s'" % field)
	if data.get("schema_version") != SCHEMA_VERSION:
		return _invalid("unsupported schema_version")
	for field: String in ["sector_id", "target_guid"]:
		var identifier: Variant = data.get(field)
		if not (identifier is String) or String(identifier).is_empty() or String(identifier).length() > MAX_ID_LENGTH:
			return _invalid("%s must be a bounded non-empty string" % field)
	var verb: Variant = data.get("verb")
	if not (verb is String) or not SUPPORTED_VERBS.has(String(verb)):
		return _invalid("unsupported verb")
	if not _bounded_int(data.get("expected_revision"), MAX_REVISION):
		return _invalid("expected_revision is out of bounds")
	if not _bounded_int(data.get("client_seq"), MAX_CLIENT_SEQ):
		return _invalid("client_seq is out of bounds")
	var direction: Variant = data.get("approach_direction")
	if not (direction is Vector3) or not (direction as Vector3).is_finite():
		return _invalid("approach_direction must be finite Vector3")
	if (direction as Vector3).length() > MAX_DIRECTION_LENGTH:
		return _invalid("approach_direction exceeds unit length")
	return {
		"outcome": OUTCOME_OK,
		"intent": {
			"schema_version": SCHEMA_VERSION,
			"sector_id": String(data["sector_id"]),
			"target_guid": String(data["target_guid"]),
			"verb": String(verb),
			"expected_revision": int(data["expected_revision"]),
			"approach_direction": direction,
			"client_seq": int(data["client_seq"]),
		},
	}


static func _bounded_int(value: Variant, maximum: int) -> bool:
	return value is int and int(value) >= 0 and int(value) <= maximum


static func _invalid(detail: String) -> Dictionary:
	return {"outcome": OUTCOME_INVALID, "detail": detail}
