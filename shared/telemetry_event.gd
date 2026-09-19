extends RefCounted
class_name TelemetryEvent
## Slice 159 (telemetry map #282, decision #283): the shared envelope every
## telemetry event uses, plus its mechanical privacy/size validation.
##
## Pure and side-effect free: this only shapes and validates a Dictionary. It
## never opens a database, sends an RPC, or reads the system clock itself
## (callers supply `emitted_at_unix`, always server wall-clock, never a
## client-supplied value) — those belong to the sink/transport slices.
##
## `schema_version` is scoped per `event_type`, not global: each event family
## owns its own monotonically increasing int. `validate()` never rejects an
## event solely for carrying an unrecognized `schema_version` — callers should
## store it raw rather than drop it (fail-closed-but-non-blocking, matching
## `EmbodimentTuning.resolve()`'s unsupported-version handling elsewhere in
## this codebase). `validate()` only rejects structurally malformed, oversized,
## or privacy-denylisted events.

## Hard cap on a serialized event's size. Enforced by the sink at write time;
## `validate()` estimates it from the payload's string representation.
const MAX_SERIALIZED_BYTES: int = 2048

## Payload string values at or above this length are treated as free-text and
## rejected, since free-text is the likeliest carrier of sensitive player input.
const MAX_STRING_VALUE_LENGTH: int = 200

## Case-insensitive substrings that may never appear in a payload key. Catches
## the sensitive-field shapes the "never raw IP/credentials/secrets" rule bans.
const _DENYLISTED_KEY_SUBSTRINGS: PackedStringArray = [
	"password", "token", "secret", "credential", "ip_address", "ip", "cookie",
]

const OUTCOME_ACCEPTED: String = "ACCEPTED"
## Missing/wrong-typed required envelope field.
const OUTCOME_MALFORMED: String = "MALFORMED"
## Estimated serialized size exceeds MAX_SERIALIZED_BYTES.
const OUTCOME_REJECTED_SIZE: String = "REJECTED_SIZE"
## A payload key/value matched the privacy denylist.
const OUTCOME_REJECTED_PRIVACY: String = "REJECTED_PRIVACY"

const _REQUIRED_STRING_FIELDS: PackedStringArray = ["event_type"]
const _REQUIRED_INT_FIELDS: PackedStringArray = [
	"schema_version", "emitted_at_unix", "server_tick", "peer_id",
]
const _NULLABLE_STRING_FIELDS: PackedStringArray = [
	"account_id", "character_id", "session_id",
]


## Builds one envelope Dictionary. `account_id`/`character_id`/`session_id`
## default to "" (nullable — pre-auth events have none yet). `payload` is the
## event-specific bounded Dictionary; callers still MUST run `validate()`
## before handing the result to a sink.
static func build(
	event_type: String,
	schema_version: int,
	emitted_at_unix: int,
	server_tick: int,
	peer_id: int,
	payload: Dictionary,
	account_id: String = "",
	character_id: String = "",
	session_id: String = "",
) -> Dictionary:
	return {
		"event_type": event_type,
		"schema_version": schema_version,
		"emitted_at_unix": emitted_at_unix,
		"server_tick": server_tick,
		"peer_id": peer_id,
		"account_id": account_id,
		"character_id": character_id,
		"session_id": session_id,
		"payload": payload,
	}


## Validates envelope shape, size, and privacy bounds. Never inspects
## `schema_version` for "known-ness" — an unrecognized version is the sink's
## "store raw" concern, not a validation failure.
static func validate(event: Dictionary) -> Dictionary:
	for field: String in _REQUIRED_STRING_FIELDS:
		if not (event.get(field) is String) or (event[field] as String).is_empty():
			return _result(OUTCOME_MALFORMED, "Missing or empty required field '%s'." % field)

	for field: String in _REQUIRED_INT_FIELDS:
		if not (event.get(field) is int):
			return _result(OUTCOME_MALFORMED, "Missing or non-int required field '%s'." % field)

	for field: String in _NULLABLE_STRING_FIELDS:
		if event.has(field) and not (event[field] is String):
			return _result(OUTCOME_MALFORMED, "Field '%s' must be a String when present." % field)

	if not (event.get("payload") is Dictionary):
		return _result(OUTCOME_MALFORMED, "Field 'payload' must be a Dictionary.")

	var payload: Dictionary = event["payload"]
	var privacy_result: Dictionary = _validate_payload_privacy(payload)
	if privacy_result["outcome"] != OUTCOME_ACCEPTED:
		return privacy_result

	if _estimated_serialized_bytes(event) > MAX_SERIALIZED_BYTES:
		return _result(OUTCOME_REJECTED_SIZE, "Estimated serialized size exceeds %d bytes." % MAX_SERIALIZED_BYTES)

	return _result(OUTCOME_ACCEPTED, "")


static func _validate_payload_privacy(payload: Dictionary) -> Dictionary:
	for key: Variant in payload.keys():
		if not (key is String):
			continue
		var lower_key: String = (key as String).to_lower()
		for denylisted: String in _DENYLISTED_KEY_SUBSTRINGS:
			if lower_key.contains(denylisted):
				return _result(OUTCOME_REJECTED_PRIVACY, "Payload key '%s' matches the privacy denylist." % key)

		var value: Variant = payload[key]
		if value is String and (value as String).length() >= MAX_STRING_VALUE_LENGTH:
			return _result(OUTCOME_REJECTED_PRIVACY, "Payload value at key '%s' looks like free text (>= %d chars)." % [key, MAX_STRING_VALUE_LENGTH])

	return _result(OUTCOME_ACCEPTED, "")


static func _estimated_serialized_bytes(event: Dictionary) -> int:
	return JSON.stringify(event).to_utf8_buffer().size()


static func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}
