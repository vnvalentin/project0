extends RefCounted
class_name CanonMutationIntent
## Slice 096 (P-013): the pure, versioned, bounded client->server contract for a
## Canon mutation request. This is the ActionIntent half of the CLAUDE.md
## intent/resolution split for world mutation: a client expresses *what it wants*
## (which sector, entity, kind, believed revision, client sequence, payload) and
## nothing else. Every server-owned outcome/identity field (event_id,
## actor_player_id, server_tick, applied_revision) is refused fail-closed so a
## client can never dictate who acted, the event identity, or the result.
##
## Pure and dependency-free: no store, no RPC, no server-only type — both the
## client (build) and the server (parse) interpret it identically, so it lives
## in shared/.

const SCHEMA_VERSION: int = 1

## The mutation vocabulary a client may request. The server-only
## CanonMutationRepository re-validates this against its own authoritative set;
## this constant is the wire-level early reject and must stay a subset of it.
const SUPPORTED_MUTATION_KINDS: PackedStringArray = ["loot", "defeat_leader", "destroy_structure", "clear_camp"]

const MAX_ID_LENGTH: int = 128
const MAX_REVISION: int = 1073741824 # 2^30, matches the mutation repository bound.
const MAX_CLIENT_SEQ: int = 1073741824
const MAX_PAYLOAD_JSON_LENGTH: int = 4096

## Fields a client is forbidden from supplying; their presence marks a forged
## intent (the server owns identity, the actor, the clock, and the result).
const _SERVER_OWNED_FIELDS: PackedStringArray = ["event_id", "actor_player_id", "server_tick", "applied_revision"]

const OUTCOME_OK: String = "ok"
const OUTCOME_INVALID: String = "invalid"


## Client-side constructor for the wire dictionary.
static func build(sector_id: String, target_guid: String, mutation_kind: String, expected_revision: int, client_seq: int, payload: Dictionary) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"sector_id": sector_id,
		"target_guid": target_guid,
		"mutation_kind": mutation_kind,
		"expected_revision": expected_revision,
		"client_seq": client_seq,
		"payload": payload,
	}


## Fail-closed validation of an untrusted intent into a bounded typed shape.
## Returns {"outcome": OUTCOME_OK, "intent": Dictionary} or
## {"outcome": OUTCOME_INVALID, "detail": String}.
static func parse(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return _invalid("Intent must be a Dictionary.")
	var dict: Dictionary = value

	for forbidden: String in _SERVER_OWNED_FIELDS:
		if dict.has(forbidden):
			return _invalid("Intent must not carry server-owned field '%s'." % forbidden)

	if not (dict.get("schema_version") is int) or int(dict["schema_version"]) != SCHEMA_VERSION:
		return _invalid("Unsupported or missing schema_version.")

	for field: String in ["sector_id", "target_guid"]:
		if not (dict.get(field) is String) or (dict[field] as String).is_empty() or (dict[field] as String).length() > MAX_ID_LENGTH:
			return _invalid("Field '%s' must be a 1..%d character string." % [field, MAX_ID_LENGTH])

	if not (dict.get("mutation_kind") is String) or not SUPPORTED_MUTATION_KINDS.has(dict["mutation_kind"]):
		return _invalid("Unsupported or missing mutation_kind.")

	if not _bounded_int(dict.get("expected_revision"), MAX_REVISION):
		return _invalid("expected_revision must be an integer in 0..%d." % MAX_REVISION)
	if not _bounded_int(dict.get("client_seq"), MAX_CLIENT_SEQ):
		return _invalid("client_seq must be an integer in 0..%d." % MAX_CLIENT_SEQ)

	if not (dict.get("payload") is Dictionary):
		return _invalid("payload must be a Dictionary.")
	if JSON.stringify(dict["payload"]).length() > MAX_PAYLOAD_JSON_LENGTH:
		return _invalid("payload exceeds %d serialized characters." % MAX_PAYLOAD_JSON_LENGTH)

	return {
		"outcome": OUTCOME_OK,
		"intent": {
			"schema_version": SCHEMA_VERSION,
			"sector_id": dict["sector_id"],
			"target_guid": dict["target_guid"],
			"mutation_kind": dict["mutation_kind"],
			"expected_revision": int(dict["expected_revision"]),
			"client_seq": int(dict["client_seq"]),
			"payload": dict["payload"],
		},
	}


static func _bounded_int(value: Variant, maximum: int) -> bool:
	return value is int and int(value) >= 0 and int(value) <= maximum


static func _invalid(detail: String) -> Dictionary:
	return {"outcome": OUTCOME_INVALID, "detail": detail}
