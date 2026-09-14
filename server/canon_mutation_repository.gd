extends RefCounted
class_name CanonMutationRepository
## Slice 050 (P-013): server-only durable Canon mutation log. Player-driven
## changes to an already-canonical sector (Slice 045) are appended here as an
## immutable, event-id-keyed log. The per-sector revision is derived from the
## log (MAX(applied_revision)), so there is no second mutable source of truth to
## drift and restart recovery is a pure read.
##
## Server-only per CLAUDE.md: shared/ and client/ MUST NEVER reference this
## class or the SqliteStore/godot-sqlite engine it uses. Every method returns a
## bounded structured result and fails closed — a malformed, stale, forged, or
## non-canon mutation is rejected before any write, never guessed into shape.
##
## This slice owns the mutation store, idempotency, optimistic revision, and
## boundary validation only. Assigning stable GUIDs to blueprint entities,
## proving the physical event occurred, gameplay authorization of the actor, the
## network DTO that carries a mutation intent, and replay into live scene state
## are explicit non-goals here (see docs/slices/050-canon-mutation-persistence.md).

const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")

const OUTCOME_OK: String = "ok"
const OUTCOME_IDEMPOTENT: String = "idempotent"
const OUTCOME_CONFLICT: String = "conflict"
const OUTCOME_REVISION_MISMATCH: String = "revision_mismatch"
const OUTCOME_SECTOR_NOT_CANON: String = "sector_not_canon"
const OUTCOME_INVALID_EVENT: String = "invalid_event"

## Mutation event schema versions this build accepts. A different version is
## rejected rather than partially interpreted.
const SUPPORTED_SCHEMA_VERSIONS: PackedInt32Array = [1]

## Bounded mutation vocabulary. Kinds outside this set are rejected so the
## contract stays meaningful; it grows with an explicit schema version, matching
## the "balance is versioned data" rule in CLAUDE.md.
const SUPPORTED_MUTATION_KINDS: PackedStringArray = ["loot", "defeat_leader", "destroy_structure", "clear_camp"]

## Bounds so a single event cannot carry unbounded identifiers or payloads.
const MAX_ID_LENGTH: int = 128
const MAX_SERVER_TICK: int = 4611686018427387904 # 2^62; a finite tick ceiling.
const MAX_REVISION: int = 1073741824 # 2^30; far above any realistic sector churn.
const MAX_PAYLOAD_JSON_LENGTH: int = 4096

const _ID_FIELDS: PackedStringArray = ["event_id", "sector_id", "target_guid", "actor_player_id"]

var _store: SqliteStore = null
var _canon: CanonRepository = null


func _init(store: SqliteStore, canon: CanonRepository) -> void:
	_store = store
	_canon = canon


## Creates the append-only mutation log and its per-sector lookup index.
func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	var create_table: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS canon_mutations (
			event_id TEXT PRIMARY KEY,
			sector_id TEXT NOT NULL,
			target_guid TEXT NOT NULL,
			mutation_kind TEXT NOT NULL,
			payload_json TEXT NOT NULL,
			actor_player_id TEXT NOT NULL,
			server_tick INTEGER NOT NULL,
			expected_revision INTEGER NOT NULL,
			applied_revision INTEGER NOT NULL,
			schema_version INTEGER NOT NULL,
			created_at INTEGER NOT NULL
		);
	""")
	if create_table["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, "Mutation schema failed: %s" % create_table["detail"])
	var create_index: Dictionary = _store.query(
		"CREATE INDEX IF NOT EXISTS idx_canon_mutations_sector ON canon_mutations (sector_id, applied_revision);"
	)
	if create_index["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, "Mutation index failed: %s" % create_index["detail"])
	return _result(OUTCOME_OK, "Mutation schema ready.")


## Validates and appends one mutation. Idempotent on event_id, optimistic on the
## sector revision, and fail-closed: a non-canon sector, a stale revision, a
## forged idempotency key, or a malformed event is rejected without any write.
func apply_mutation(event: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")

	var validation: Dictionary = _validate_event(event)
	if validation["outcome"] != OUTCOME_OK:
		return validation
	var validated: Dictionary = validation["event"]
	var sector_id: String = validated["sector_id"]
	var event_id: String = validated["event_id"]
	var payload_json: String = validated["payload_json"]

	# The target sector must already be immutable Canon (Slice 045).
	if _canon.get_canonical_sector(sector_id)["outcome"] != CanonRepositoryScript.OUTCOME_OK:
		return _result(OUTCOME_SECTOR_NOT_CANON, "Sector '%s' is not Canon; cannot mutate it." % sector_id)

	# Idempotency / forgery guard on the server-owned event_id.
	var existing: Dictionary = _store.query_with_bindings(
		"SELECT event_id, sector_id, target_guid, mutation_kind, payload_json, actor_player_id, server_tick, expected_revision, applied_revision, schema_version, created_at FROM canon_mutations WHERE event_id = ?;",
		[event_id]
	)
	if existing["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, existing["detail"])
	if not (existing["rows"] as Array).is_empty():
		var stored_row: Dictionary = existing["rows"][0]
		if _same_content(stored_row, validated, payload_json):
			return {
				"outcome": OUTCOME_IDEMPOTENT,
				"detail": "Mutation '%s' was already applied." % event_id,
				"applied_revision": int(stored_row["applied_revision"]),
				"mutation": _record_from_row(stored_row),
			}
		return {
			"outcome": OUTCOME_CONFLICT,
			"detail": "Event id '%s' was already used for different content." % event_id,
			"applied_revision": int(stored_row["applied_revision"]),
			"mutation": _record_from_row(stored_row),
		}

	# Optimistic concurrency against the derived current revision.
	var current_revision: int = _current_revision(sector_id)
	if int(validated["expected_revision"]) != current_revision:
		return {
			"outcome": OUTCOME_REVISION_MISMATCH,
			"detail": "Sector '%s' is at revision %d, event expected %d." % [sector_id, current_revision, int(validated["expected_revision"])],
			"current_revision": current_revision,
		}

	var applied_revision: int = current_revision + 1
	var created_at: int = Time.get_unix_time_from_system()
	var transaction_result: Dictionary = _store.transaction(func() -> bool:
		var insert: Dictionary = _store.query_with_bindings(
			"INSERT INTO canon_mutations (event_id, sector_id, target_guid, mutation_kind, payload_json, actor_player_id, server_tick, expected_revision, applied_revision, schema_version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			[
				event_id, sector_id, validated["target_guid"], validated["mutation_kind"], payload_json,
				validated["actor_player_id"], int(validated["server_tick"]), int(validated["expected_revision"]),
				applied_revision, int(validated["schema_version"]), created_at,
			]
		)
		return insert["outcome"] == SqliteStore.OUTCOME_OK
	)
	if transaction_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, "Mutation apply failed: %s" % transaction_result["detail"])
	return {
		"outcome": OUTCOME_OK,
		"detail": "Mutation '%s' applied at revision %d." % [event_id, applied_revision],
		"applied_revision": applied_revision,
	}


## The current revision of a sector, derived from the append-only log. A canon
## sector with no mutations is at revision 0.
func get_sector_revision(sector_id: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (sector_id is String) or (sector_id as String).is_empty():
		return {"outcome": OUTCOME_INVALID_EVENT, "detail": "sector_id must be a non-empty string.", "revision": 0}
	return {"outcome": OUTCOME_OK, "detail": "", "revision": _current_revision(sector_id)}


## The ordered mutation history for a sector, for replay/load after restart.
func list_mutations(sector_id: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open.", "mutations": []}
	if not (sector_id is String) or (sector_id as String).is_empty():
		return {"outcome": OUTCOME_INVALID_EVENT, "detail": "sector_id must be a non-empty string.", "mutations": []}
	var select_result: Dictionary = _store.query_with_bindings(
		"SELECT event_id, sector_id, target_guid, mutation_kind, payload_json, actor_player_id, server_tick, expected_revision, applied_revision, schema_version, created_at FROM canon_mutations WHERE sector_id = ? ORDER BY applied_revision ASC;",
		[sector_id]
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return {"outcome": SqliteStore.OUTCOME_QUERY_FAILED, "detail": select_result["detail"], "mutations": []}
	var mutations: Array = []
	for row: Dictionary in select_result["rows"]:
		mutations.append(_record_from_row(row))
	return {"outcome": OUTCOME_OK, "detail": "", "mutations": mutations}


func _current_revision(sector_id: String) -> int:
	var result: Dictionary = _store.query_with_bindings(
		"SELECT MAX(applied_revision) AS rev FROM canon_mutations WHERE sector_id = ?;",
		[sector_id]
	)
	if result["outcome"] != SqliteStore.OUTCOME_OK or (result["rows"] as Array).is_empty():
		return 0
	var rev: Variant = result["rows"][0]["rev"]
	return 0 if rev == null else int(rev)


## Validates the untrusted event dictionary into a bounded typed shape. Returns
## {"outcome": OUTCOME_OK, "event": Dictionary, "payload_json": String} on
## success (folded into "event"), or {"outcome": OUTCOME_INVALID_EVENT, ...}.
func _validate_event(event: Variant) -> Dictionary:
	if not (event is Dictionary):
		return _result(OUTCOME_INVALID_EVENT, "Event must be a Dictionary.")
	var dict: Dictionary = event

	if not dict.has("schema_version") or not (dict["schema_version"] is int) or not SUPPORTED_SCHEMA_VERSIONS.has(int(dict["schema_version"])):
		return _result(OUTCOME_INVALID_EVENT, "Unsupported or missing schema_version.")

	for field: String in _ID_FIELDS:
		if not dict.has(field) or not (dict[field] is String):
			return _result(OUTCOME_INVALID_EVENT, "Field '%s' must be a string." % field)
		var value: String = dict[field]
		if value.is_empty() or value.length() > MAX_ID_LENGTH:
			return _result(OUTCOME_INVALID_EVENT, "Field '%s' must be 1..%d characters." % [field, MAX_ID_LENGTH])

	if not dict.has("mutation_kind") or not (dict["mutation_kind"] is String) or not SUPPORTED_MUTATION_KINDS.has(dict["mutation_kind"]):
		return _result(OUTCOME_INVALID_EVENT, "Unsupported or missing mutation_kind.")

	if not _is_bounded_int(dict.get("server_tick"), MAX_SERVER_TICK):
		return _result(OUTCOME_INVALID_EVENT, "server_tick must be an integer in 0..%d." % MAX_SERVER_TICK)
	if not _is_bounded_int(dict.get("expected_revision"), MAX_REVISION):
		return _result(OUTCOME_INVALID_EVENT, "expected_revision must be an integer in 0..%d." % MAX_REVISION)

	if not dict.has("payload") or not (dict["payload"] is Dictionary):
		return _result(OUTCOME_INVALID_EVENT, "payload must be a Dictionary.")
	var payload_json: String = JSON.stringify(dict["payload"])
	if payload_json.length() > MAX_PAYLOAD_JSON_LENGTH:
		return _result(OUTCOME_INVALID_EVENT, "payload exceeds %d serialized characters." % MAX_PAYLOAD_JSON_LENGTH)

	var validated: Dictionary = {
		"schema_version": int(dict["schema_version"]),
		"event_id": dict["event_id"],
		"sector_id": dict["sector_id"],
		"target_guid": dict["target_guid"],
		"mutation_kind": dict["mutation_kind"],
		"actor_player_id": dict["actor_player_id"],
		"server_tick": int(dict["server_tick"]),
		"expected_revision": int(dict["expected_revision"]),
		"payload_json": payload_json,
	}
	return {"outcome": OUTCOME_OK, "detail": "", "event": validated, "payload_json": payload_json}


func _is_bounded_int(value: Variant, maximum: int) -> bool:
	return value is int and int(value) >= 0 and int(value) <= maximum


func _same_content(row: Dictionary, validated: Dictionary, payload_json: String) -> bool:
	return (
		row["sector_id"] == validated["sector_id"]
		and row["target_guid"] == validated["target_guid"]
		and row["mutation_kind"] == validated["mutation_kind"]
		and row["payload_json"] == payload_json
		and row["actor_player_id"] == validated["actor_player_id"]
		and int(row["server_tick"]) == int(validated["server_tick"])
		and int(row["expected_revision"]) == int(validated["expected_revision"])
		and int(row["schema_version"]) == int(validated["schema_version"])
	)


func _record_from_row(row: Dictionary) -> Dictionary:
	return {
		"event_id": row["event_id"],
		"sector_id": row["sector_id"],
		"target_guid": row["target_guid"],
		"mutation_kind": row["mutation_kind"],
		"payload": JSON.parse_string(row["payload_json"]),
		"actor_player_id": row["actor_player_id"],
		"server_tick": int(row["server_tick"]),
		"expected_revision": int(row["expected_revision"]),
		"applied_revision": int(row["applied_revision"]),
		"schema_version": int(row["schema_version"]),
		"created_at": int(row["created_at"]),
	}


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}
