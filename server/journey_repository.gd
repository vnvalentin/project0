extends RefCounted
class_name JourneyRepository

const OUTCOME_OK: String = "ok"

var _store: SqliteStore = null


func _init(store: SqliteStore) -> void:
	_store = store


func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open."}
	var result: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS journeys (
			journey_id TEXT PRIMARY KEY,
			character_id TEXT UNIQUE NOT NULL,
			lifecycle_status TEXT NOT NULL,
			peer_id INTEGER NOT NULL DEFAULT 0,
			position_x REAL NOT NULL,
			position_y REAL NOT NULL,
			position_z REAL NOT NULL,
			sector_id TEXT NOT NULL,
			sector_revision INTEGER NOT NULL DEFAULT 0,
			sector_geometry_hash TEXT NOT NULL DEFAULT '',
			last_checkpoint_at INTEGER NOT NULL,
			last_disconnected_at INTEGER NOT NULL DEFAULT 0
		);
	""")
	if result["outcome"] != SqliteStore.OUTCOME_OK:
		return {"outcome": result["outcome"], "detail": result["detail"]}
	return {"outcome": OUTCOME_OK, "detail": "Schema ready."}


func load_all() -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open.", "records": []}
	var result: Dictionary = _store.query_with_bindings(
		"SELECT journey_id, character_id, lifecycle_status, peer_id, position_x, position_y, position_z, sector_id, sector_revision, sector_geometry_hash, last_checkpoint_at, last_disconnected_at FROM journeys;"
	)
	if result["outcome"] != SqliteStore.OUTCOME_OK:
		return {"outcome": result["outcome"], "detail": result["detail"], "records": []}
	return {"outcome": OUTCOME_OK, "detail": "", "records": result["rows"]}


func save(record: Dictionary) -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open."}
	var result: Dictionary = _store.query_with_bindings(
		"INSERT INTO journeys (journey_id, character_id, lifecycle_status, peer_id, position_x, position_y, position_z, sector_id, sector_revision, sector_geometry_hash, last_checkpoint_at, last_disconnected_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(journey_id) DO UPDATE SET character_id = excluded.character_id, lifecycle_status = excluded.lifecycle_status, peer_id = excluded.peer_id, position_x = excluded.position_x, position_y = excluded.position_y, position_z = excluded.position_z, sector_id = excluded.sector_id, sector_revision = excluded.sector_revision, sector_geometry_hash = excluded.sector_geometry_hash, last_checkpoint_at = excluded.last_checkpoint_at, last_disconnected_at = excluded.last_disconnected_at;",
		[
			String(record.get("journey_id", "")), String(record.get("character_id", "")),
			String(record.get("lifecycle_status", "disconnected")), int(record.get("peer_id", 0)),
			float(record.get("position_x", 0.0)), float(record.get("position_y", 0.0)), float(record.get("position_z", 0.0)),
			String(record.get("sector_id", "")), int(record.get("sector_revision", 0)),
			String(record.get("sector_geometry_hash", "")), int(record.get("last_checkpoint_at", 0)),
			int(record.get("last_disconnected_at", 0)),
		]
	)
	return {"outcome": result["outcome"], "detail": result["detail"]}


func delete_journey(journey_id: String) -> Dictionary:
	if _store == null or not _store.is_open():
		return {"outcome": SqliteStore.OUTCOME_NOT_OPEN, "detail": "Store is not open."}
	var result: Dictionary = _store.query_with_bindings("DELETE FROM journeys WHERE journey_id = ?;", [journey_id])
	return {"outcome": result["outcome"], "detail": result["detail"]}