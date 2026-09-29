extends RefCounted
class_name CharacterStatRepository
## Experiment 1 for Epic #1292: server-only durable persistence for the
## authoritative GameState stat aggregate. Uses the shared SqliteStore seam,
## parameter-bound SQL, atomic per-character upserts, and fail-closed reload.

const GameStateScript: Script = preload("res://shared/game_state.gd")

const OUTCOME_OK: String = "ok"
const OUTCOME_NOT_FOUND: String = "not_found"
const OUTCOME_INVALID_SNAPSHOT: String = "snapshot_rejected_invalid"

var _store: SqliteStore = null


func _init(store: SqliteStore) -> void:
	_store = store


func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	var schema_result: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS character_stats (
			character_id TEXT PRIMARY KEY,
			schema_version INTEGER NOT NULL,
			tuning_version TEXT NOT NULL,
			stats_json TEXT NOT NULL,
			updated_at INTEGER NOT NULL
		);
	""")
	if schema_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, "Character stat schema failed: %s" % schema_result["detail"])
	return _result(OUTCOME_OK, "Character stat schema ready.")


## Replaces the complete validated snapshot atomically for one character.
func save_stats(character_id: Variant, state: Object, tuning: Object) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (character_id is String) or (character_id as String).is_empty():
		return _result(OUTCOME_INVALID_SNAPSHOT, "character_id must be a non-empty string.")
	if state == null or not (state is GameStateScript):
		return _result(OUTCOME_INVALID_SNAPSHOT, "state must be a GameState aggregate.")
	var snapshot: Dictionary = state.to_snapshot()
	var stats_json: String = JSON.stringify(snapshot["stats"])
	var updated_at: int = Time.get_unix_time_from_system()
	var transaction_result: Dictionary = _store.transaction(func() -> bool:
		var upsert: Dictionary = _store.query_with_bindings(
			"""
			INSERT INTO character_stats (character_id, schema_version, tuning_version, stats_json, updated_at)
			VALUES (?, ?, ?, ?, ?)
			ON CONFLICT(character_id) DO UPDATE SET
				schema_version = excluded.schema_version,
				tuning_version = excluded.tuning_version,
				stats_json = excluded.stats_json,
				updated_at = excluded.updated_at;
			""",
			[character_id, int(snapshot["schema_version"]), String(tuning.tuning_version), stats_json, updated_at]
		)
		return upsert["outcome"] == SqliteStore.OUTCOME_OK
	)
	if transaction_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, "Character stat save failed: %s" % transaction_result["detail"])
	return _result(OUTCOME_OK, "Character stats for '%s' persisted." % character_id)


func load_stats(character_id: Variant, tuning: Object) -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open.", "state": null}
	if not (character_id is String) or (character_id as String).is_empty():
		return {"outcome": OUTCOME_NOT_FOUND, "detail": "character_id must be a non-empty string.", "state": null}
	var select_result: Dictionary = _store.query_with_bindings(
		"SELECT schema_version, tuning_version, stats_json FROM character_stats WHERE character_id = ?;",
		[character_id]
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return {"outcome": SqliteStore.OUTCOME_QUERY_FAILED, "detail": select_result["detail"], "state": null}
	if (select_result["rows"] as Array).is_empty():
		return {"outcome": OUTCOME_NOT_FOUND, "detail": "No stats exist for '%s'." % character_id, "state": null}
	var row: Dictionary = select_result["rows"][0]
	if int(row["schema_version"]) != GameStateScript.SCHEMA_VERSION:
		return _invalid("unsupported schema_version")
	if String(row["tuning_version"]) != String(tuning.tuning_version):
		return _invalid("unsupported tuning_version")
	var parsed: Variant = JSON.parse_string(String(row["stats_json"]))
	var validation: Dictionary = GameStateScript.from_snapshot(
		{"schema_version": int(row["schema_version"]), "stats": parsed}, tuning
	)
	if validation["outcome"] != GameStateScript.OUTCOME_OK:
		return _invalid(validation["detail"])
	return {"outcome": OUTCOME_OK, "detail": "", "state": validation["state"]}


func _invalid(detail: String) -> Dictionary:
	return {"outcome": OUTCOME_INVALID_SNAPSHOT, "detail": detail, "state": null}


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}