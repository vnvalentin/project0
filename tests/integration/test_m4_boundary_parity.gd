extends GutTest
## #1377. These are isolated Linux component proofs, not deployed-stack or
## three-case gameplay acceptance. Raw storage is an explicitly approved seam.

const Evidence: Script = preload("res://scripts/m4_canon_evidence.gd")
const Store: Script = preload("res://server/sqlite_store.gd")
const Canon: Script = preload("res://server/canon_repository.gd")
const Mutations: Script = preload("res://server/canon_mutation_repository.gd")
const Service: Script = preload("res://server/canon_mutation_service.gd")
const Intent: Script = preload("res://shared/canon_mutation_intent.gd")
const Guid: Script = preload("res://shared/canon_entity_guid.gd")
const Fixtures: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _stores: Array[SqliteStore] = []
var _paths: Array[String] = []
var _trace: Dictionary = {}
var _stamp: String = ""
var _old_canon: String = ""
var _had_canon: bool = false


func before_each() -> void:
	_stamp = "%d_%d" % [Time.get_ticks_usec(), randi()]
	_stores = []
	_paths = []
	_trace = {"issue": 1377, "evidence_scope": "isolated_linux_component", "engine": Engine.get_version_info()["string"],
		"source_revision": OS.get_environment("M4_SOURCE_REVISION"), "case_id": "", "passed": false,
		"source_sha256": {"helper": FileAccess.get_sha256("res://scripts/m4_canon_evidence.gd"), "test": FileAccess.get_sha256("res://tests/integration/test_m4_boundary_parity.gd")},
		"unsupported": ["repair_claim_permanent_flags", "persistent_in_flight_interaction_transfer", "native_persisted_occupancy_bitmask"]}
	_had_canon = OS.has_environment("PROJECT0_CANON_DB_PATH")
	_old_canon = OS.get_environment("PROJECT0_CANON_DB_PATH")


func after_each() -> void:
	for store: SqliteStore in _stores:
		if store.is_open():
			store.close()
	var cleanup: Array = []
	for path: String in _paths:
		for suffix: String in Evidence.SIDECARS:
			var owned: String = path + suffix
			if FileAccess.file_exists(owned):
				DirAccess.remove_absolute(owned)
			cleanup.append({"path": owned, "absent": not FileAccess.file_exists(owned)})
			assert_false(FileAccess.file_exists(owned), "owned fixture removed")
	if _had_canon:
		OS.set_environment("PROJECT0_CANON_DB_PATH", _old_canon)
	else:
		OS.unset_environment("PROJECT0_CANON_DB_PATH")
	_trace["cleanup"] = cleanup
	for result: Dictionary in cleanup:
		if not result["absent"]:
			_trace["passed"] = false
	var directory: String = "res://logs/experiments"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix: String = "parity" if _trace["passed"] else "FAIL_trace"
	var file: FileAccess = FileAccess.open("%s/exp_m4_2_%s_%s.json" % [directory, prefix, _stamp], FileAccess.WRITE)
	assert_not_null(file, "retain result after cleanup")
	if file != null:
		file.store_string(JSON.stringify(_trace, "\t"))
		file.close()


func _open_store(relative_path: String) -> SqliteStore:
	var path: String = ProjectSettings.globalize_path("user://" + relative_path)
	for suffix: String in Evidence.SIDECARS:
		if FileAccess.file_exists(path + suffix):
			return null # Never open or claim cleanup ownership of an existing path.
	_paths.append(path)
	var store: SqliteStore = Store.new()
	_stores.append(store)
	assert_eq(store.open(relative_path)["outcome"], "ok")
	return store


func _fixture(dedicated: bool) -> Dictionary:
	var account_path: String = "m4_accounts_%s.db" % _stamp
	var configured: String = "m4_canon_%s.db" % _stamp if dedicated else ""
	if dedicated:
		OS.set_environment("PROJECT0_CANON_DB_PATH", configured)
	else:
		OS.unset_environment("PROJECT0_CANON_DB_PATH")
	var accounts: SqliteStore = _open_store(account_path)
	assert_not_null(accounts, "fresh accounts target required")
	if accounts == null:
		return {}
	var selected: String = OS.get_environment("PROJECT0_CANON_DB_PATH").strip_edges()
	# This is the documented server_main selection rule, exercised in both modes.
	var store: SqliteStore = accounts if selected.is_empty() else _open_store(selected)
	assert_not_null(store, "fresh Canon target required")
	if store == null:
		return {}
	var canon: CanonRepository = Canon.new(store)
	assert_eq(canon.ensure_schema()["outcome"], "ok")
	var mutations: CanonMutationRepository = Mutations.new(store, canon)
	assert_eq(mutations.ensure_schema()["outcome"], "ok")
	for sector: String in ["sector-0-0", "sector-1-0"]:
		var blueprint: Dictionary = JSON.parse_string(Fixtures.VALID_WITH_LOCKED_GATE)
		blueprint["sector_id"] = sector
		assert_eq(canon.canonicalize_blueprint(blueprint)["outcome"], "ok")
	var service: CanonMutationService = Service.new(mutations, func() -> int: return 73)
	assert_eq(service.resolve_intent("m4-player", _intent())["status"], "accepted", "known committed revision precedes rejection window")
	_trace["store_selection"] = {"configured_canon_path": selected, "handle": "dedicated" if dedicated else "accounts_shared", "accounts_path": account_path}
	return {"store": store, "canon": canon, "mutations": mutations, "service": service, "relative_path": selected if dedicated else account_path}


func _intent(overrides: Dictionary = {}) -> Dictionary:
	var value: Dictionary = Intent.build("sector-0-0", Guid.derive("sector-0-0", Guid.ENTITY_CLASS_STRUCTURE, "gate-1"), "loot", 0, 1, {"item": "fixture"})
	value.merge(overrides, true)
	return value


func _before_window(fixture: Dictionary) -> Dictionary:
	var store: SqliteStore = fixture["store"]
	var raw: Dictionary = Evidence.snapshot(store)
	assert_eq(raw["status"], "OBSERVED")
	assert_eq(store.close()["outcome"], "ok")
	var digest: Dictionary = Evidence.digest(raw["active_path"])
	assert_eq(digest["status"], "OBSERVED")
	assert_eq(store.open(fixture["relative_path"])["outcome"], "ok")
	assert_eq(store.start_dml_observation()["observation_status"], "OBSERVED")
	return {"raw": raw, "digest": digest}


func _finish_window(fixture: Dictionary, before: Dictionary) -> Dictionary:
	var store: SqliteStore = fixture["store"]
	var sql: Dictionary = store.dml_statement_counters()
	# End the request window before diagnostic PRAGMA database_list.
	var raw: Dictionary = Evidence.snapshot(store)
	assert_eq(store.close()["outcome"], "ok")
	var digest: Dictionary = Evidence.digest(before["raw"]["active_path"])
	var verdict: Dictionary = Evidence.rejected_window(before["raw"], raw, sql, before["digest"], digest)
	_trace.merge({"raw_before": before["raw"], "raw_after": raw, "sql": sql,
		"quiescence": "all_connections_to_active_store_closed_at_each_digest", "digest_before": before["digest"], "digest_after": digest, "verdict": verdict})
	return verdict


func _rejections(dedicated: bool) -> void:
	_trace["case_id"] = "rejected_dedicated" if dedicated else "rejected_shared"
	var fixture: Dictionary = _fixture(dedicated)
	if fixture.is_empty():
		return
	var before: Dictionary = _before_window(fixture)
	var service: CanonMutationService = fixture["service"]
	var cases: Array[Dictionary] = [
		{"id": "malformed", "actor": "m4-player", "intent": null, "reason": "invalid_intent"},
		{"id": "invalid_actor", "actor": "", "intent": _intent(), "reason": "invalid_actor"},
		{"id": "cross_sector_guid", "actor": "m4-player", "intent": _intent({"sector_id": "sector-1-0", "client_seq": 2}), "reason": "target_not_found"},
		{"id": "missing_sector", "actor": "m4-player", "intent": _intent({"sector_id": "sector-9-9", "client_seq": 3}), "reason": "sector_not_canon"},
		{"id": "stale_revision", "actor": "m4-player", "intent": _intent({"client_seq": 4}), "reason": "revision_mismatch"},
		{"id": "forged_tick", "actor": "m4-player", "intent": _intent({"server_tick": 999}), "reason": "invalid_intent"},
		{"id": "conflicting_replay", "actor": "m4-player", "intent": _intent({"payload": {"item": "changed"}}), "reason": "conflict"},
	]
	var responses: Array = []
	var rejected: bool = true
	for case: Dictionary in cases:
		var result: Dictionary = service.resolve_intent(case["actor"], case["intent"])
		assert_eq(result["status"], "rejected", case["id"])
		assert_eq(result["reason"], case["reason"], case["id"])
		rejected = rejected and result["status"] == "rejected" and result["reason"] == case["reason"]
		responses.append({"case_id": case["id"], "result": result})
	_trace["rejections"] = responses
	var verdict: Dictionary = _finish_window(fixture, before)
	assert_true(verdict["passed"], "rejections preserve raw state/digests and attempt no writes")
	_trace["passed"] = rejected and verdict["passed"]


func test_rejected_cross_sector_requests_preserve_shared_accounts_store() -> void:
	_rejections(false)


func test_rejected_cross_sector_requests_preserve_configured_dedicated_store() -> void:
	_rejections(true)


func test_negative_control_detects_an_actual_committed_write() -> void:
	_trace["case_id"] = "control_committed_write"
	var fixture: Dictionary = _fixture(true)
	if fixture.is_empty():
		return
	var before: Dictionary = _before_window(fixture)
	var result: Dictionary = fixture["service"].resolve_intent("m4-player", _intent({"expected_revision": 1, "client_seq": 2}))
	assert_eq(result["status"], "accepted")
	var verdict: Dictionary = _finish_window(fixture, before)
	assert_false(verdict["passed"])
	assert_has(verdict["failures"], "attempted_canon_mutations_insert")
	assert_has(verdict["failures"], "database_or_sidecar_changed")
	assert_has(verdict["failures"], "raw_state_changed")
	_trace["expected_control_failure"] = true
	_trace["passed"] = not verdict["passed"] and verdict["failures"].has("attempted_canon_mutations_insert") and verdict["failures"].has("database_or_sidecar_changed") and verdict["failures"].has("raw_state_changed")


func test_negative_control_never_treats_unobserved_sql_as_zero() -> void:
	_trace["case_id"] = "control_unobserved_sql"
	var fixture: Dictionary = _fixture(false)
	if fixture.is_empty():
		return
	var before: Dictionary = _before_window(fixture)
	assert_eq(fixture["store"].query("WITH probe AS (SELECT 1 AS n) SELECT n FROM probe;")["outcome"], "ok")
	var verdict: Dictionary = _finish_window(fixture, before)
	assert_false(verdict["passed"])
	assert_has(verdict["failures"], "sql_not_observed")
	_trace["expected_control_failure"] = true
	_trace["passed"] = not verdict["passed"] and verdict["failures"].has("sql_not_observed")


func test_existing_target_is_neither_opened_nor_claimed_for_cleanup() -> void:
	_trace["case_id"] = "control_existing_target"
	var relative: String = "m4_sentinel_%s.db" % _stamp
	var path: String = ProjectSettings.globalize_path("user://" + relative)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("owned sentinel, not a SQLite store")
	file.close()
	var expected: String = FileAccess.get_sha256(path)
	var result: SqliteStore = _open_store(relative)
	assert_null(result, "existing path refuses open")
	assert_false(_paths.has(path), "failed claim cannot delete existing target")
	assert_eq(FileAccess.get_sha256(path), expected, "existing bytes untouched")
	_trace["passed"] = result == null and not _paths.has(path) and FileAccess.get_sha256(path) == expected
	_paths.append(path) # This test created the sentinel and owns its teardown.
