extends RefCounted
class_name CanonRepository
## Slice 045: server-only durable sector Canon repository. Provisional data is
## revalidated at this boundary and a sector_id can be canonicalized only once.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

const OUTCOME_OK: String = "ok"
const OUTCOME_IDEMPOTENT: String = "idempotent"
const OUTCOME_CONFLICT: String = "conflict"
const OUTCOME_INVALID_BLUEPRINT: String = "invalid_blueprint"
const OUTCOME_NOT_FOUND: String = "not_found"

var _store: SqliteStore = null


func _init(store: SqliteStore) -> void:
	_store = store


## Creates the immutable Canon table and its coordinate uniqueness constraint.
func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	var schema_result: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS canon_sectors (
			sector_id TEXT PRIMARY KEY,
			blueprint_json TEXT NOT NULL,
			schema_version INTEGER NOT NULL,
			created_at INTEGER NOT NULL
		);
	""")
	if schema_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, "Canon schema failed: %s" % schema_result["detail"])
	return _result(OUTCOME_OK, "Canon schema ready.")


## Validates and stores a blueprint as the first immutable Canon for its sector.
## An exact replay is idempotent; a different replay cannot replace history.
func canonicalize_blueprint(blueprint: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	var validation: Dictionary = SectorBlueprintSchemaScript.validate(blueprint)
	if validation["outcome"] != SectorBlueprintSchemaScript.OUTCOME_VALID:
		return {
			"outcome": OUTCOME_INVALID_BLUEPRINT,
			"detail": validation["detail"],
			"validation_outcome": validation["outcome"],
		}

	var validated: Dictionary = validation["blueprint"]
	var sector_id: String = validated["sector_id"]
	var blueprint_json: String = JSON.stringify(validated)
	var existing: Dictionary = _store.query_with_bindings(
		"SELECT sector_id, blueprint_json, schema_version, created_at FROM canon_sectors WHERE sector_id = ?;",
		[sector_id]
	)
	if existing["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, existing["detail"])
	if not (existing["rows"] as Array).is_empty():
		var row: Dictionary = existing["rows"][0]
		var stored_blueprint: Variant = JSON.parse_string(row["blueprint_json"])
		var stored: Dictionary = _record_from_row(row, stored_blueprint)
		if row["blueprint_json"] == blueprint_json:
			return {
				"outcome": OUTCOME_IDEMPOTENT,
				"detail": "Sector '%s' is already canonical." % sector_id,
				"sector": stored,
			}
		return {
			"outcome": OUTCOME_CONFLICT,
			"detail": "Sector '%s' already has immutable Canon." % sector_id,
			"sector": stored,
		}

	var created_at: int = Time.get_unix_time_from_system()
	var transaction_result: Dictionary = _store.transaction(func() -> bool:
		var insert: Dictionary = _store.query_with_bindings(
			"INSERT INTO canon_sectors (sector_id, blueprint_json, schema_version, created_at) VALUES (?, ?, ?, ?);",
			[sector_id, blueprint_json, int(validated["schema_version"]), created_at]
		)
		return insert["outcome"] == SqliteStore.OUTCOME_OK
	)
	if transaction_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, "Canonicalization failed: %s" % transaction_result["detail"])
	return {
		"outcome": OUTCOME_OK,
		"detail": "Sector '%s' became Canon." % sector_id,
		"sector": {
			"sector_id": sector_id,
			"blueprint": validated,
			"schema_version": int(validated["schema_version"]),
			"created_at": created_at,
		},
	}


## Loads one immutable Canon record after restart, or returns OUTCOME_NOT_FOUND.
func get_canonical_sector(sector_id: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (sector_id is String) or (sector_id as String).is_empty():
		return _result(OUTCOME_NOT_FOUND, "sector_id must be a non-empty string.")
	var select_result: Dictionary = _store.query_with_bindings(
		"SELECT sector_id, blueprint_json, schema_version, created_at FROM canon_sectors WHERE sector_id = ?;",
		[sector_id]
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, select_result["detail"])
	if (select_result["rows"] as Array).is_empty():
		return _result(OUTCOME_NOT_FOUND, "No Canon exists for '%s'." % sector_id)
	var row: Dictionary = select_result["rows"][0]
	return {"outcome": OUTCOME_OK, "detail": "", "sector": _record_from_row(row, JSON.parse_string(row["blueprint_json"]))}


## Slice 080: server-only migration read. Returns every Canon row verbatim
## (including created_at) so a one-time copy into a dedicated store preserves the
## immutable historical record. Ordered oldest-first. NEVER a client DTO.
func list_all_records() -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open.", "records": []}
	var select_result: Dictionary = _store.query(
		"SELECT sector_id, blueprint_json, schema_version, created_at FROM canon_sectors ORDER BY created_at ASC, sector_id ASC;"
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return {"outcome": SqliteStore.OUTCOME_QUERY_FAILED, "detail": select_result["detail"], "records": []}
	var records: Array = []
	for row: Dictionary in select_result["rows"]:
		records.append(_record_from_row(row, JSON.parse_string(row["blueprint_json"])))
	return {"outcome": OUTCOME_OK, "detail": "", "records": records}


## Slice 080: server-only migration write. Inserts a previously-canonical record
## into this store preserving its original created_at (unlike canonicalize_blueprint,
## which stamps the current time). Validates the blueprint; idempotent on an
## identical existing row; refuses to overwrite a differing one.
func restore_record(record: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (record is Dictionary):
		return _result(OUTCOME_INVALID_BLUEPRINT, "record must be a Dictionary.")
	var validation: Dictionary = SectorBlueprintSchemaScript.validate((record as Dictionary).get("blueprint"))
	if validation["outcome"] != SectorBlueprintSchemaScript.OUTCOME_VALID:
		return {
			"outcome": OUTCOME_INVALID_BLUEPRINT,
			"detail": validation["detail"],
			"validation_outcome": validation["outcome"],
		}
	var created_at_value: Variant = (record as Dictionary).get("created_at")
	if not (created_at_value is int) and not (created_at_value is float):
		return _result(OUTCOME_INVALID_BLUEPRINT, "created_at must be a number.")
	var created_at: int = int(created_at_value)
	var validated: Dictionary = validation["blueprint"]
	var sector_id: String = validated["sector_id"]
	var blueprint_json: String = JSON.stringify(validated)
	var existing: Dictionary = _store.query_with_bindings(
		"SELECT blueprint_json FROM canon_sectors WHERE sector_id = ?;",
		[sector_id]
	)
	if existing["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, existing["detail"])
	if not (existing["rows"] as Array).is_empty():
		if existing["rows"][0]["blueprint_json"] == blueprint_json:
			return _result(OUTCOME_IDEMPOTENT, "Sector '%s' is already restored." % sector_id)
		return _result(OUTCOME_CONFLICT, "Sector '%s' already has differing Canon." % sector_id)
	var transaction_result: Dictionary = _store.transaction(func() -> bool:
		var insert: Dictionary = _store.query_with_bindings(
			"INSERT INTO canon_sectors (sector_id, blueprint_json, schema_version, created_at) VALUES (?, ?, ?, ?);",
			[sector_id, blueprint_json, int(validated["schema_version"]), created_at]
		)
		return insert["outcome"] == SqliteStore.OUTCOME_OK
	)
	if transaction_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, "Restore failed: %s" % transaction_result["detail"])
	return {
		"outcome": OUTCOME_OK,
		"detail": "Sector '%s' restored." % sector_id,
		"sector": {
			"sector_id": sector_id,
			"blueprint": validated,
			"schema_version": int(validated["schema_version"]),
			"created_at": created_at,
		},
	}


func _record_from_row(row: Dictionary, blueprint: Variant) -> Dictionary:
	return {
		"sector_id": row["sector_id"],
		"blueprint": blueprint,
		"schema_version": int(row["schema_version"]),
		"created_at": int(row["created_at"]),
	}


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}