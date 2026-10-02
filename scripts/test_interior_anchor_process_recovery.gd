extends SceneTree
## #849 two native-process SQLite recovery smoke fixture; server-only.
## Coordinator owns isolated setup, phase ordering, evidence and final cleanup.
## No live generation, scene assembly, physical-event or plot-authority proof.

const StoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonScript: Script = preload("res://server/canon_repository.gd")
const MutationsScript: Script = preload("res://server/canon_mutation_repository.gd")
const AnchorScript: Script = preload("res://server/interior_anchor_repository.gd")
const GuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const SECTOR: String = "sector-0-0"
const ACTOR: String = "fixture-character-owner"
const DATABASES: Dictionary = {"valid": "anchor-recovery-valid.db", "damaged": "anchor-recovery-damaged.db"}

var _errors: Array[String] = []
var _scenarios: Dictionary = {}
var _phase: String = ""
var _state_path: String = ""
var _report_path: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(2)
		return
	_phase = args[0]
	_state_path = args[1]
	_report_path = args[2]
	if _phase not in ["prepare", "recover"] or not _state_path.begins_with("/tmp/project0-849-recovery-") or not _report_path.begins_with(ProjectSettings.globalize_path("res://build/validation/849-recovery/")):
		quit(2)
		return
	var isolated_xdg: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated_xdg.begins_with("/tmp/project0-849-recovery-") or not ProjectSettings.globalize_path("user://").begins_with(isolated_xdg + "/"):
		_check(false, "isolated_user_path")
		_finish()
		return
	var state: Dictionary = {}
	if _phase == "recover":
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(_state_path))
		if not (loaded is Dictionary) or not loaded.has_all(["prepare_pid", "valid", "damaged"]):
			_check(false, "complete_expected_state")
			_finish()
			return
		state = loaded
		_check(int(state.prepare_pid) != OS.get_process_id(), "distinct_native_process")
	for scenario: String in ["valid", "damaged"]:
		var database: String = DATABASES[scenario]
		var exists: bool = FileAccess.file_exists("user://" + database)
		if not _check(exists == (_phase == "recover"), scenario + ":clean_existing_target"):
			continue
		var store: SqliteStore = StoreScript.new()
		if not _check(store.open(database).outcome == "ok", scenario + ":open"):
			continue
		if _phase == "prepare":
			state[scenario] = _prepare(store, scenario)
		else:
			_recover(store, scenario, state[scenario])
		store.close()
	if _phase == "prepare" and _errors.is_empty():
		state.prepare_pid = OS.get_process_id()
		_check(_write_json(_state_path, state), "expected_state_written")
	_finish()


func _prepare(store: SqliteStore, scenario: String) -> Dictionary:
	var canon: CanonRepository = CanonScript.new(store)
	var mutations: CanonMutationRepository = MutationsScript.new(store, canon)
	var anchors: InteriorAnchorRepository = AnchorScript.new(store)
	if not _check(canon.ensure_schema().outcome == "ok" and mutations.ensure_schema().outcome == "ok" and anchors.ensure_schema().outcome == "ok", scenario + ":schema"):
		return {}
	if not _check(canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE)).outcome == "ok", scenario + ":canon"):
		return {}
	for index: int in range(2):
		var event: Dictionary = {
			"schema_version": 1, "event_id": "fixture-event-%d" % index,
			"sector_id": SECTOR, "target_guid": _target(), "mutation_kind": "loot",
			"payload": {"fixture": index}, "actor_player_id": ACTOR,
			"server_tick": 100 + index, "expected_revision": index,
		}
		if not _check(mutations.apply_mutation(event).outcome == "ok", scenario + ":mutation-%d" % index):
			return {}
	var registration: Dictionary = anchors.register_anchor(_descriptor())
	if not _check(registration.outcome == "ok", scenario + ":registration"):
		return {}
	var original: String = JSON.stringify(registration.anchor.to_dict())
	_check(registration.anchor.exterior_revision == 2, scenario + ":ordered_revision")
	if scenario == "damaged":
		_check(store.query_with_bindings("UPDATE canon_mutations SET schema_version = ? WHERE event_id = ?;", [99, "fixture-event-1"]).outcome == "ok", scenario + ":owned_damage")
	var snapshot: Dictionary = _snapshot(store, scenario)
	snapshot["normalized_anchor_json"] = original
	_scenarios[scenario] = _summary(snapshot)
	return snapshot


func _recover(store: SqliteStore, scenario: String, expected: Dictionary) -> void:
	var started: Dictionary = store.start_dml_observation()
	_check(started.observation_status == "OBSERVED", scenario + ":observation_started")
	var before: Dictionary = _snapshot(store, scenario)
	for field: String in ["canon_bytes", "canon_row_json", "mutation_rows_json", "anchor_rows_json", "cell_rows_json"]:
		_check(before.get(field) == expected.get(field), scenario + ":" + field + "_unchanged")
	var anchors: InteriorAnchorRepository = AnchorScript.new(store)
	var archived: Dictionary = anchors.get_anchor(_interior_id(expected))
	_check(archived.outcome == "ok", scenario + ":archival_anchor")
	if archived.outcome == "ok":
		_check(JSON.stringify(archived.anchor.to_dict()) == expected.normalized_anchor_json, scenario + ":normalized_anchor_unchanged")
	var resolved: Dictionary = anchors.resolve_entry(_intent())
	var replay: Dictionary = anchors.register_anchor(_descriptor())
	if scenario == "valid":
		_check(resolved.outcome == "ok" and resolved.has("anchor"), "valid:live_resolution")
		_check(replay.outcome == "idempotent" and replay.has("anchor"), "valid:exact_replay")
		if resolved.has("anchor"):
			_check(JSON.stringify(resolved.anchor.to_dict()) == expected.normalized_anchor_json, "valid:resolved_anchor_unchanged")
		if replay.has("anchor"):
			_check(JSON.stringify(replay.anchor.to_dict()) == expected.normalized_anchor_json, "valid:replayed_anchor_unchanged")
	else:
		_check(resolved.outcome == "invalid_record" and not resolved.has("anchor"), "damaged:resolve_rejected")
		_check(replay.outcome == "invalid_record" and not replay.has("anchor"), "damaged:replay_rejected")
	var after: Dictionary = _snapshot(store, scenario)
	_check(before == after, scenario + ":no_storage_change")
	var observation: Dictionary = store.dml_statement_counters()
	_check(observation.observation_status == "OBSERVED" and observation.native_row_effects == "NOT_OBSERVED", scenario + ":scoped_observation")
	for window: String in ["attempted", "committed", "rolled_back", "failed"]:
		for operation: String in ["insert", "replace", "update", "delete"]:
			_check(observation.totals[window][operation] == 0, scenario + ":zero_" + window + "_" + operation)
		for table: String in observation.by_table:
			for operation: String in ["insert", "replace", "update", "delete"]:
				_check(observation.by_table[table][window][operation] == 0, scenario + ":zero_table_" + window)
	_scenarios[scenario] = _summary(after)
	_scenarios[scenario]["observation"] = observation
	_scenarios[scenario]["resolution_outcome"] = resolved.outcome
	_scenarios[scenario]["replay_outcome"] = replay.outcome


func _snapshot(store: SqliteStore, scenario: String) -> Dictionary:
	var snapshot: Dictionary = {}
	var selections: Dictionary = {
		"canon_row_json": "SELECT sector_id, blueprint_json, schema_version, created_at FROM canon_sectors ORDER BY sector_id;",
		"mutation_rows_json": "SELECT event_id, sector_id, target_guid, mutation_kind, payload_json, actor_player_id, server_tick, expected_revision, applied_revision, schema_version, created_at FROM canon_mutations ORDER BY sector_id, applied_revision, event_id;",
		"anchor_rows_json": "SELECT * FROM interior_anchors ORDER BY interior_id;",
		"cell_rows_json": "SELECT * FROM interior_cells ORDER BY interior_id, cell_x, cell_y, cell_z;",
	}
	for field: String in selections:
		var selected: Dictionary = store.query(selections[field])
		if not _check(selected.outcome == "ok", scenario + ":read_" + field):
			return {}
		snapshot[field] = JSON.stringify(selected.rows)
	var canon_rows: Array = JSON.parse_string(snapshot.canon_row_json)
	if _check(canon_rows.size() == 1, scenario + ":single_canon"):
		snapshot["canon_bytes"] = canon_rows[0].blueprint_json
	return snapshot


static func _summary(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has_all(["canon_bytes", "mutation_rows_json", "anchor_rows_json", "cell_rows_json"]):
		return {}
	var events: Array = JSON.parse_string(snapshot.mutation_rows_json)
	var identities: Array = []
	for event: Dictionary in events:
		identities.append({"event_id": event.event_id, "actor_player_id": event.actor_player_id, "target_guid": event.target_guid, "expected_revision": event.expected_revision, "applied_revision": event.applied_revision, "schema_version": event.schema_version})
	return {
		"canon_utf8_bytes": String(snapshot.canon_bytes).to_utf8_buffer().size(),
		"canon_sha1": String(snapshot.canon_bytes).sha1_text(),
		"ordered_mutation_sha1": String(snapshot.mutation_rows_json).sha1_text(),
		"ordered_mutation_identities": identities,
		"anchor_sha1": String(snapshot.anchor_rows_json).sha1_text(),
		"cell_sha1": String(snapshot.cell_rows_json).sha1_text(),
	}


static func _interior_id(expected: Dictionary) -> String:
	var record: Dictionary = JSON.parse_string(expected.normalized_anchor_json)
	return record.interior_id


static func _target() -> String:
	return GuidScript.derive(SECTOR, "structure", "village_hall")


static func _intent() -> Dictionary:
	return {"schema_version": 1, "exterior_sector_id": SECTOR, "exterior_entity_guid": _target()}


static func _descriptor() -> Dictionary:
	return {
		"schema_version": 1, "exterior_sector_id": SECTOR, "exterior_entity_guid": _target(),
		"plot_id": "fixture-plot-village-hall", "entry_position": [0.0, 0.0, 0.0],
		"cell_coordinate": [0, 0, 0], "bounds_min": [-2.0, -1.0, -2.0], "bounds_max": [2.0, 3.0, 2.0],
		"streaming_reference": "fixture/interior/village-hall/0-0-0",
	}


func _check(condition: bool, label: String) -> bool:
	if not condition:
		_errors.append(label)
	return condition


static func _write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.close()
	return true


func _finish() -> void:
	var report: Dictionary = {
		"schema_version": 1, "issue": 849, "phase": _phase, "native_pid": OS.get_process_id(),
		"status": "passed" if _errors.is_empty() else "failed", "errors": _errors, "scenarios": _scenarios,
		"generation": "NOT_OBSERVED", "scene_assembly": "NOT_OBSERVED", "physical_actor_authorization": "NOT_OBSERVED",
	}
	if not _write_json(_report_path, report):
		quit(2)
		return
	print(JSON.stringify({"phase": _phase, "status": report.status, "errors": _errors}))
	quit(0 if _errors.is_empty() else 1)
