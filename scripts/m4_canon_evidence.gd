extends RefCounted
## #1377 experiment-only evidence at the approved raw Canon/SQL seams.
## The caller owns stores and must close every connection before digest().

const MUTATION_COLUMNS: String = "event_id, sector_id, target_guid, mutation_kind, payload_json, actor_player_id, server_tick, expected_revision, applied_revision, schema_version"
const SIDECARS: Array[String] = ["", "-wal", "-shm", "-journal"]


static func snapshot(store: SqliteStore) -> Dictionary:
	var databases: Dictionary = store.query("PRAGMA database_list;")
	var journal: Dictionary = store.query("PRAGMA journal_mode;")
	var blueprints: Dictionary = store.query("SELECT sector_id, blueprint_json, schema_version FROM canon_sectors ORDER BY sector_id;")
	var mutations: Dictionary = store.query("SELECT %s FROM canon_mutations ORDER BY sector_id, applied_revision;" % MUTATION_COLUMNS)
	for result: Dictionary in [databases, journal, blueprints, mutations]:
		if result.get("outcome") != "ok":
			return {"status": "NOT_OBSERVED", "reason": "query_failed"}
	var active_path: String = ""
	for database: Dictionary in databases["rows"]:
		if database["name"] == "main":
			active_path = str(database["file"])
	if active_path.is_empty() or journal["rows"].size() != 1:
		return {"status": "NOT_OBSERVED", "reason": "active_store_not_observed"}
	return {"status": "OBSERVED", "active_path": active_path,
		"journal_mode": journal["rows"][0]["journal_mode"],
		"blueprints": blueprints["rows"], "mutations": mutations["rows"]}


static func digest(active_path: String) -> Dictionary:
	var files: Dictionary = {}
	for suffix: String in SIDECARS:
		var path: String = active_path + suffix
		var exists: bool = FileAccess.file_exists(path)
		var sha256: String = FileAccess.get_sha256(path) if exists else ""
		files[suffix] = {"exists": exists, "sha256": sha256}
		if exists and sha256.length() != 64:
			return {"status": "NOT_OBSERVED", "reason": "digest_failed", "files": files}
	if not files[""]["exists"]:
		return {"status": "NOT_OBSERVED", "reason": "database_missing", "files": files}
	return {"status": "OBSERVED", "active_path": active_path, "files": files}


static func rejected_window(before: Dictionary, after: Dictionary, sql: Dictionary, before_digest: Dictionary, after_digest: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if before.get("status") != "OBSERVED" or after.get("status") != "OBSERVED":
		failures.append("raw_state_not_observed")
	elif before != after:
		failures.append("raw_state_changed")
	if before_digest.get("status") != "OBSERVED" or after_digest.get("status") != "OBSERVED":
		failures.append("digest_not_observed")
	elif before_digest != after_digest:
		failures.append("database_or_sidecar_changed")
	if sql.get("observation_status") != "OBSERVED":
		failures.append("sql_not_observed")
	else:
		for table: String in ["canon_sectors", "canon_mutations"]:
			var counts: Dictionary = sql.get("by_table", {}).get(table, {}).get("attempted", {})
			for operation: String in ["insert", "update", "replace", "delete"]:
				if not counts.has(operation):
					failures.append("missing_%s_%s" % [table, operation])
				elif counts[operation] != 0:
					failures.append("attempted_%s_%s" % [table, operation])
	return {"passed": failures.is_empty(), "failures": failures}


## Lossless report of the supported effective sector fields. The occupancy
## strings encode public is_blocked() results; they are not native saved masks.
static func reconstructed_state(raw: Dictionary) -> Array:
	var resolver: Script = load("res://shared/canon_sector_resolver.gd")
	var collision: Script = load("res://shared/sector_collision_map.gd")
	var geometry: Script = load("res://shared/sector_geometry_lookup.gd")
	var guid: Script = load("res://shared/canon_entity_guid.gd")
	var result: Array = []
	for row: Dictionary in raw["blueprints"]:
		var mutations: Array = []
		for committed: Dictionary in raw["mutations"]:
			if committed["sector_id"] == row["sector_id"]:
				var decoded: Dictionary = committed.duplicate(true)
				decoded["payload"] = JSON.parse_string(committed["payload_json"])
				mutations.append(decoded)
		var effective: Dictionary = resolver.resolve_effective_blueprint(JSON.parse_string(row["blueprint_json"]), mutations)
		var map: RefCounted = collision.new(effective)
		var bounds: Array = []
		var occupancy: Array = []
		for structure: Dictionary in effective.get("structures", []):
			var extent: Vector2i = geometry.structure_footprint(structure["kind"])
			var x: int = int(structure["x"])
			var z: int = int(structure["y"])
			var cells: Array[String] = []
			for dz: int in range(-extent.y, extent.y + 1):
				var bits: String = ""
				for dx: int in range(-extent.x, extent.x + 1):
					bits += "1" if map.is_blocked(Vector2i(x + dx, z + dz)) else "0"
				cells.append(bits)
			bounds.append({"anchor_id": structure["structure_id"], "x_min": x - extent.x - 0.5, "x_max": x + extent.x + 0.5,
				"z_min": z - extent.y - 0.5, "z_max": z + extent.y + 0.5})
			occupancy.append({"anchor_id": structure["structure_id"], "origin": [x - extent.x, z - extent.y], "rows_z_then_x": cells})
		var wall_cells: Array = []
		for tile: Dictionary in effective.get("tiles", []):
			if tile["kind"] == "wall":
				wall_cells.append({"cell": [tile["x"], tile["y"]], "blocked": map.is_blocked(Vector2i(int(tile["x"]), int(tile["y"])))})
		result.append({"sector_id": row["sector_id"], "effective_blueprint": effective, "entity_guids": guid.list_entities(effective),
			"static_collider_bounds": bounds, "occupancy_encoding": occupancy, "wall_cells": wall_cells, "blocked_count": map.blocked_count()})
	return result
