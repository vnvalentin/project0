extends RefCounted
class_name VesselRepository
## Slice 143 (Phase 15 follow-on, P-016): server-only durable persistence for a
## Character's earned vessel (VesselProgressionState). Consumes the shared
## SqliteStore engine seam (server/sqlite_store.gd) unmodified, mirroring
## CanonRepository/AccountCharacterRepository. shared/ and client/ MUST NEVER
## reference this class or the SQLite engine it uses. Every method returns a
## bounded, structured result Dictionary and never raises, matching SqliteStore's
## fail-closed contract style.
##
## Unlike the immutable Canon, a vessel is MUTABLE earned state (it changes as the
## Character trains), so save_vessel upserts by character_id rather than refusing a
## second write. A loaded blob is revalidated at this boundary through
## VesselProgressionState.from_wire_dict against the current tuning (schema,
## structure, node bounds, and the fixed budget) so a corrupt or mistuned row
## fails closed instead of resurrecting an invalid vessel. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md and issues
## #219/#223.

const VesselScript: Script = preload("res://shared/vessel_progression_state.gd")

const OUTCOME_OK: String = "ok"
const OUTCOME_NOT_FOUND: String = "not_found"
const OUTCOME_INVALID_VESSEL: String = "invalid_vessel"

var _store: SqliteStore = null


func _init(store: SqliteStore) -> void:
	_store = store


## Creates the mutable per-Character vessel table.
func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	var schema_result: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS character_vessels (
			character_id TEXT PRIMARY KEY,
			vessel_json TEXT NOT NULL,
			schema_version INTEGER NOT NULL,
			tuning_version TEXT NOT NULL,
			updated_at INTEGER NOT NULL
		);
	""")
	if schema_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, "Vessel schema failed: %s" % schema_result["detail"])
	return _result(OUTCOME_OK, "Vessel schema ready.")


## Durably stores (or replaces) a Character's vessel. Idempotent per character_id:
## re-saving after a training gain overwrites the prior row atomically. The vessel
## is serialized through its own to_wire_dict; no derived/effective state is ever
## persisted.
func save_vessel(character_id: Variant, vessel: Object) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (character_id is String) or (character_id as String).is_empty():
		return _result(OUTCOME_INVALID_VESSEL, "character_id must be a non-empty string.")
	if vessel == null:
		return _result(OUTCOME_INVALID_VESSEL, "vessel must not be null.")
	var wire: Dictionary = vessel.to_wire_dict()
	var vessel_json: String = JSON.stringify(wire)
	var updated_at: int = Time.get_unix_time_from_system()
	var transaction_result: Dictionary = _store.transaction(func() -> bool:
		var upsert: Dictionary = _store.query_with_bindings(
			"""
			INSERT INTO character_vessels (character_id, vessel_json, schema_version, tuning_version, updated_at)
			VALUES (?, ?, ?, ?, ?)
			ON CONFLICT(character_id) DO UPDATE SET
				vessel_json = excluded.vessel_json,
				schema_version = excluded.schema_version,
				tuning_version = excluded.tuning_version,
				updated_at = excluded.updated_at;
			""",
			[character_id, vessel_json, int(wire["schema_version"]), String(wire["tuning_version"]), updated_at]
		)
		return upsert["outcome"] == SqliteStore.OUTCOME_OK
	)
	if transaction_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, "Vessel save failed: %s" % transaction_result["detail"])
	return _result(OUTCOME_OK, "Vessel for '%s' persisted." % character_id)


## Loads a Character's durable vessel after restart, revalidated against the
## current tuning (fail-closed on schema/structure/bounds/budget), or returns
## OUTCOME_NOT_FOUND. Returns {outcome, detail, vessel}.
func load_vessel(character_id: Variant, tuning: Object) -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open.", "vessel": null}
	if not (character_id is String) or (character_id as String).is_empty():
		return {"outcome": OUTCOME_NOT_FOUND, "detail": "character_id must be a non-empty string.", "vessel": null}
	var select_result: Dictionary = _store.query_with_bindings(
		"SELECT vessel_json FROM character_vessels WHERE character_id = ?;",
		[character_id]
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return {"outcome": SqliteStore.OUTCOME_QUERY_FAILED, "detail": select_result["detail"], "vessel": null}
	if (select_result["rows"] as Array).is_empty():
		return {"outcome": OUTCOME_NOT_FOUND, "detail": "No vessel exists for '%s'." % character_id, "vessel": null}
	var row: Dictionary = select_result["rows"][0]
	var parsed: Variant = JSON.parse_string(row["vessel_json"])
	var validation: Dictionary = VesselScript.from_wire_dict(parsed, tuning)
	if validation["outcome"] != VesselScript.OUTCOME_OK:
		return {
			"outcome": OUTCOME_INVALID_VESSEL,
			"detail": "Stored vessel for '%s' failed validation: %s" % [character_id, validation["detail"]],
			"vessel": null,
		}
	return {"outcome": OUTCOME_OK, "detail": "", "vessel": validation["vessel"]}


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}
