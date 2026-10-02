extends GutTest
## #1377. These are isolated Linux component proofs, not deployed-stack or
## networked/deployed gameplay acceptance. Raw storage is an explicitly approved seam.

const Evidence: Script = preload("res://scripts/m4_canon_evidence.gd")
const Store: Script = preload("res://server/sqlite_store.gd")
const Canon: Script = preload("res://server/canon_repository.gd")
const Mutations: Script = preload("res://server/canon_mutation_repository.gd")
const Service: Script = preload("res://server/canon_mutation_service.gd")
const Intent: Script = preload("res://shared/canon_mutation_intent.gd")
const Guid: Script = preload("res://shared/canon_entity_guid.gd")
const Boundary: Script = preload("res://server/sector_boundary_detector.gd")
const Player: Script = preload("res://server/server_player_state.gd")
const Combat: Script = preload("res://shared/combat_contracts.gd")
const Interaction: Script = preload("res://shared/environmental_interaction_contract.gd")
const Environmental: Script = preload("res://server/environmental_interaction_service.gd")
const Collision: Script = preload("res://shared/sector_collision_map.gd")
const Fixtures: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _stores: Array[SqliteStore] = []
var _paths: Array[String] = []
var _trace: Dictionary = {}
var _stamp: String = ""
var _old_canon: String = ""
var _had_canon: bool = false
var _failures_before: int = 0
var _network_client: Node = null


func before_each() -> void:
	_failures_before = get_fail_count()
	_network_client = get_tree().root.get_node_or_null("NetworkClient")
	if _network_client != null:
		_network_client.name = "M4ComponentNetworkClient"
	_stamp = "%d_%d" % [Time.get_ticks_usec(), randi()]
	_stores = []
	_paths = []
	_trace = {"issue": 1377, "evidence_scope": "isolated_linux_component", "engine": Engine.get_version_info()["string"],
		"source_revision": OS.get_environment("M4_SOURCE_REVISION"), "case_id": "", "passed": false,
		"source_sha256": {"helper": FileAccess.get_sha256("res://scripts/m4_canon_evidence.gd"), "test": FileAccess.get_sha256("res://tests/integration/test_m4_boundary_parity.gd")},
		"unsupported": ["repair_claim_permanent_flags", "persistent_in_flight_interaction_transfer", "native_persisted_occupancy_bitmask"]}
	_trace["store_observations"] = {}
	_trace["source_identity"] = Evidence.source_identity(_trace["source_revision"])
	assert_eq(_trace["source_identity"]["status"], "OBSERVED", "M4_SOURCE_REVISION must be the full lowercase commit SHA")
	_had_canon = OS.has_environment("PROJECT0_CANON_DB_PATH")
	_old_canon = OS.get_environment("PROJECT0_CANON_DB_PATH")


func after_each() -> void:
	if _network_client != null:
		_network_client.name = "NetworkClient"
		assert_eq(get_tree().root.get_node_or_null("NetworkClient"), _network_client, "autoload restored")
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
	_trace["passed"] = _trace["passed"] and get_fail_count() == _failures_before
	_trace["assertion_failures"] = get_fail_count() - _failures_before
	var directory: String = "res://logs/experiments"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix: String = "parity" if _trace["passed"] else "FAIL_trace"
	var file: FileAccess = FileAccess.open("%s/exp_m4_2_%s_%s.json" % [directory, prefix, _stamp], FileAccess.WRITE)
	assert_not_null(file, "retain result after cleanup")
	if file != null:
		var content: String = JSON.stringify(_trace, "\t")
		file.store_string(content)
		file.flush()
		assert_eq(file.get_error(), OK, "evidence persisted")
		var saved_path: String = file.get_path_absolute()
		file.close()
		assert_eq(FileAccess.get_file_as_string(saved_path), content, "complete evidence readback")
		var persisted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved_path))
		assert_eq(persisted["passed"], get_fail_count() == _failures_before, "persisted verdict matches actual test assertions")


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


func _fixture(dedicated: bool, label: String = "") -> Dictionary:
	if _trace["source_identity"]["status"] != "OBSERVED":
		return {}
	var account_path: String = "m4_accounts_%s%s.db" % [_stamp, label]
	var configured: String = "m4_canon_%s%s.db" % [_stamp, label] if dedicated else ""
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
	for sector: String in ["sector-0-0", "sector--1-0"]:
		var blueprint: Dictionary = JSON.parse_string(Fixtures.VALID_WITH_LOCKED_GATE)
		blueprint["sector_id"] = sector
		blueprint["structures"][0]["x"] = -2 if sector == "sector--1-0" else 1
		blueprint["structures"].append({"structure_id": "debris", "kind": "well", "x": 5, "y": 5, "facing_degrees": 90})
		var seeded: Dictionary = canon.canonicalize_blueprint(blueprint)
		assert_eq(seeded["outcome"], "ok", seeded.get("detail", ""))
		if seeded["outcome"] != "ok":
			return {}
	var service: CanonMutationService = Service.new(mutations, func() -> int: return 73)
	assert_eq(service.resolve_intent("m4-player", _intent())["status"], "accepted", "known committed revision precedes rejection window")
	var fixture: Dictionary = {"store": store, "canon": canon, "mutations": mutations, "service": service,
		"relative_path": selected if dedicated else account_path, "observation_id": label if not label.is_empty() else "fixture",
		"configured_canon_path": selected, "handle": "dedicated" if dedicated else "accounts_shared", "accounts_path": account_path}
	_retain_store_observation(fixture, Evidence.snapshot(store))
	return fixture


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
		{"id": "cross_sector_guid", "actor": "m4-player", "intent": _intent({"sector_id": "sector--1-0", "client_seq": 2}), "reason": "target_not_found"},
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
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		fail_test("sentinel control requires a fresh owned target")
		return
	var created: Dictionary = Evidence.create_sentinel(path, "owned sentinel, not a SQLite store", _paths)
	assert_eq(created["status"], "OBSERVED", "created sentinel owned for cleanup")
	if created["status"] != "OBSERVED":
		return
	var expected: String = FileAccess.get_sha256(path)
	var refused_ownership: Array[String] = []
	var refused: Dictionary = Evidence.create_sentinel(path, "must not replace existing bytes", refused_ownership)
	assert_eq(refused["status"], "NOT_OBSERVED", "existing sentinel refuses overwrite")
	assert_true(refused_ownership.is_empty(), "refused creation claims no ownership")
	assert_eq(FileAccess.get_sha256(path), expected, "existing sentinel bytes untouched")
	var result: SqliteStore = _open_store(relative)
	assert_null(result, "existing path refuses store open")
	assert_eq(_paths.count(path), 1, "only successful sentinel creation owns teardown")
	assert_eq(FileAccess.get_sha256(path), expected, "existing bytes untouched by store admission")
	_trace["passed"] = refused["status"] == "NOT_OBSERVED" and refused_ownership.is_empty() and result == null and _paths.count(path) == 1 and FileAccess.get_sha256(path) == expected


func _seed_permanent_changes(fixture: Dictionary) -> void:
	var mutations: CanonMutationRepository = fixture["mutations"]
	for event: Dictionary in [
		{"event_id": "m4-unlock", "target_guid": Guid.derive("sector-0-0", Guid.ENTITY_CLASS_STRUCTURE, "gate-1"), "mutation_kind": "unlock_gate", "expected_revision": 1, "payload": {"unlocked": true}},
		{"event_id": "m4-destroy", "target_guid": Guid.derive("sector-0-0", Guid.ENTITY_CLASS_STRUCTURE, "debris"), "mutation_kind": "destroy_structure", "expected_revision": 2, "payload": {}},
	]:
		event.merge({"schema_version": 1, "sector_id": "sector-0-0", "actor_player_id": "m4-player", "server_tick": 100})
		assert_eq(mutations.apply_mutation(event)["outcome"], "ok")


func _retain_store_observation(fixture: Dictionary, raw: Dictionary) -> void:
	assert_eq(raw["status"], "OBSERVED", "actual store path and journal observed")
	var metadata: Dictionary = {"status": raw["status"], "active_path": raw.get("active_path", ""), "journal_mode": raw.get("journal_mode", ""),
		"configured_canon_path": fixture["configured_canon_path"], "handle": fixture["handle"], "accounts_path": fixture["accounts_path"]}
	_trace["store_observations"][fixture["observation_id"]] = metadata


func _canonical_state(fixture: Dictionary) -> Dictionary:
	var raw: Dictionary = Evidence.snapshot(fixture["store"])
	_retain_store_observation(fixture, raw)
	if raw["status"] != "OBSERVED":
		return {}
	# Store identity is retained separately: it must differ between the two fixtures.
	return {"blueprints": raw["blueprints"], "mutations": raw["mutations"], "reconstructed": Evidence.reconstructed_state(raw)}


func _moving_players(fixture: Dictionary, count: int, observe_boundaries: bool) -> Dictionary:
	var canon: CanonRepository = fixture["canon"]
	var detector: RefCounted = Boundary.new()
	var reloads: Array = []
	var requests: Array = []
	detector.set_canon_lookup(canon.get_canonical_sector)
	detector.set_request_callback(func(_peer: int, sector: String, _position: Vector3) -> void: requests.append(sector))
	detector.set_reload_callback(func(peer: int, sector: String, position: Vector3) -> void:
		var loaded: Dictionary = canon.get_canonical_sector(sector)
		assert_eq(loaded["outcome"], "ok")
		reloads.append({"peer": peer, "sector_id": sector, "position": [position.x, position.y, position.z], "canonical": _canonical_state(fixture)})
	)
	var players: Array[Node] = []
	var targets: Array[Node3D] = []
	var hits: Array = []
	for index: int in count:
		var peer: int = 10 + index
		var direction: float = 1.0 if index % 2 == 0 else -1.0
		var start: Vector3 = Vector3(-0.2 if direction > 0 else 0.2, 0, 10 + index * 3)
		var target: Node3D = Node3D.new()
		target.position = Vector3(1.4 if direction > 0 else -1.4, 0, start.z)
		add_child_autofree(target)
		targets.append(target)
		var player: Node = Player.new()
		add_child_autofree(player)
		player.start_for_peer(peer, start)
		player.bind_character("m4-character-%d" % index, "M4 fixture", {})
		player.set_physics_process(false)
		player.set_target_dummies({"m4-spatial-%d" % index: target})
		player.combat_event_emitted.connect(func(_peer: int, event: Object) -> void:
			hits.append({"actor": event.attacker_peer_id, "target_id": event.target_id, "kind": event.kind,
				"impact": [event.impact_position.x, event.impact_position.y, event.impact_position.z]})
		)
		if observe_boundaries:
			detector.commit_position(peer, start)
			player.position_updated.connect(func(id: int, position: Vector3) -> void: detector.observe_position(id, position))
		player.apply_input_intent(peer, Vector2(direction, 0), 1)
		players.append(player)
	# Same-tick concurrency: every admitted character advances within each tick,
	# in deterministic server order. This is not parallel or multi-writer authority.
	for _tick: int in 4:
		for player: Node in players:
			player._physics_process(1.0 / 30.0)
	for player: Node in players:
		player.apply_input_intent(player.owning_peer_id, Vector2.ZERO, 2)
		var resolution: Object = player.apply_action_intent(player.owning_peer_id,
			Combat.ActionIntent.new(player.owning_peer_id, 1, 0, Combat.ACTION_KIND_MELEE_STRIKE, player.facing))
		assert_eq(resolution.result, Combat.RESULT_ACCEPTED)
	for _tick: int in 40:
		for player: Node in players:
			player._physics_process(1.0 / 30.0)
	var state: Array = []
	for index: int in players.size():
		var player: Node = players[index]
		var target: Node3D = targets[index]
		state.append({"peer": player.owning_peer_id, "character_id": player.character_id,
			"position": [player.position.x, player.position.y, player.position.z],
			"facing": [player.facing.x, player.facing.y, player.facing.z],
			"spatial_target": {"target_id": "m4-spatial-%d" % index, "position": [target.position.x, target.position.y, target.position.z]}})
	assert_eq(hits.size(), count, "registered spatial references still resolve after crossing")
	if observe_boundaries:
		assert_eq(reloads.size(), count, "one real adjacent-sector reload per character")
	assert_true(requests.is_empty(), "Canon crossings need no generation")
	return {"players": state, "hits": hits, "reloads": reloads, "generation_requests": requests}


func _boundary_case(count: int) -> void:
	_trace["case_id"] = "unilateral" if count == 1 else "concurrent_same_tick"
	var reference: Dictionary = _fixture(false, "_reference")
	var crossed: Dictionary = _fixture(true, "_crossed")
	if reference.is_empty() or crossed.is_empty():
		return
	_seed_permanent_changes(reference)
	_seed_permanent_changes(crossed)
	var original: Dictionary = _canonical_state(reference)
	assert_eq(original["mutations"].size(), 3, "three literal committed events")
	assert_eq(original["reconstructed"][1]["effective_blueprint"]["structures"].size(), 1, "destroyed debris absent")
	assert_true(original["reconstructed"][1]["effective_blueprint"]["structures"][0]["unlocked"], "committed gate unlock reconstructed")
	assert_eq(original["reconstructed"][1]["occupancy_encoding"][0]["rows_z_then_x"], ["111"], "unlocked gate remains physically closed until opened")
	var baseline: Dictionary = _moving_players(reference, count, false)
	var crossing: Dictionary = _moving_players(crossed, count, true)
	var restored: Dictionary = _canonical_state(crossed)
	assert_eq(restored, original, "exact raw Canon, ordered mutation rows and reconstructed geometry match reference")
	assert_eq(crossing["players"], baseline["players"], "authoritative transforms and entity references match")
	assert_eq(crossing["hits"], baseline["hits"], "spatial references remain usable")
	for reload: Dictionary in crossing["reloads"]:
		assert_eq(reload["canonical"], original, "each boundary callback reload matches independent reference")
	_trace.merge({"reference": original, "crossed": restored, "reference_runtime": baseline, "crossed_runtime": crossing,
		"concurrency_model": "one_authoritative_thread_same_tick_batch", "passed": restored == original and crossing["players"] == baseline["players"] and crossing["hits"] == baseline["hits"]}, true)


func test_unilateral_crossing_keeps_active_spatial_reference_and_exact_canon() -> void:
	_boundary_case(1)


func test_concurrent_crossings_keep_each_character_and_exact_canon() -> void:
	_boundary_case(4)


func _synchronous_interaction(fixture: Dictionary, observe_boundary: bool) -> Dictionary:
	var canon: CanonRepository = fixture["canon"]
	var blueprint: Dictionary = canon.get_canonical_sector("sector-0-0")["sector"]["blueprint"]
	var collision: RefCounted = Collision.new(blueprint)
	var service: RefCounted = Environmental.new(canon, fixture["mutations"], func() -> int: return 120, collision.has_line_of_sight)
	var actor: Vector3 = Vector3(0.5, 0, 1)
	var intent: Dictionary = Interaction.build_intent("sector-0-0", Guid.derive("sector-0-0", Guid.ENTITY_CLASS_STRUCTURE, "gate-1"), "lock_pick", 1, Vector3.RIGHT, 12)
	var detector: RefCounted = Boundary.new()
	detector.set_canon_lookup(canon.get_canonical_sector)
	var transition: Dictionary = {}
	if observe_boundary:
		detector.commit_position(20, Vector3(-0.5, 0, 1))
		transition = detector.observe_position(20, actor)
		assert_true(transition["reloaded"], "interaction actor entered the adjacent canonical sector")
	var result: Dictionary = service.resolve_intent("m4-interaction-actor", actor, {}, intent)
	assert_eq(result["status"], "accepted")
	assert_eq(result["applied_revision"], 2)
	return {"result": result, "actor_position": [actor.x, actor.y, actor.z], "target_guid": intent["target_guid"], "sector_id": "sector-0-0",
		"line_of_sight": collision.has_line_of_sight(actor, Vector3(1, 0, 0)), "transition_reloaded": transition.get("reloaded", false)}


func test_supported_synchronous_boundary_interaction_matches_reference() -> void:
	_trace["case_id"] = "synchronous_boundary_interaction"
	var reference: Dictionary = _fixture(false, "_reference")
	var crossed: Dictionary = _fixture(true, "_crossed")
	if reference.is_empty() or crossed.is_empty():
		return
	var baseline: Dictionary = _synchronous_interaction(reference, false)
	var crossing: Dictionary = _synchronous_interaction(crossed, true)
	var expected: Dictionary = _canonical_state(reference)
	var actual: Dictionary = _canonical_state(crossed)
	assert_eq(crossing["result"], baseline["result"], "same server-stamped interaction outcome")
	assert_true(crossing["line_of_sight"], "real collision-map line of sight")
	assert_eq(actual, expected, "exact raw rows and supported reconstructed state")
	assert_eq(actual["mutations"][1]["server_tick"], 120, "authoritative tick retained in parity")
	assert_true(actual["reconstructed"][1]["effective_blueprint"]["structures"][0]["unlocked"])
	_trace.merge({"reference": expected, "crossed": actual, "reference_interaction": baseline, "crossed_interaction": crossing,
		"interaction_model": "synchronous_validation_and_commit_no_persistent_in_flight_state", "passed": actual == expected and crossing["result"] == baseline["result"]}, true)


func test_source_identity_rejects_missing_or_invalid_revision() -> void:
	_trace["case_id"] = "control_source_identity"
	for revision: String in ["", "main", "41078c6", "g".repeat(40), " ".repeat(40)]:
		var rejected: Dictionary = Evidence.source_identity(revision)
		assert_eq(rejected["status"], "NOT_OBSERVED", "unqualified source cannot identify passing evidence")
	var accepted: Dictionary = Evidence.source_identity("41078c67a42553ca55b3e1e958f170421cfa4912")
	assert_eq(accepted["status"], "OBSERVED")
	assert_eq(accepted["revision"], "41078c67a42553ca55b3e1e958f170421cfa4912")
	_trace["passed"] = true


func test_both_fixture_sources_retain_actual_path_handle_and_journal() -> void:
	_trace["case_id"] = "control_fixture_observations"
	var reference: Dictionary = _fixture(false, "_reference")
	var crossed: Dictionary = _fixture(true, "_crossed")
	if reference.is_empty() or crossed.is_empty():
		return
	_canonical_state(reference)
	_canonical_state(crossed)
	var observed: Dictionary = _trace.get("store_observations", {})
	assert_eq(observed.size(), 2, "both fixture observations retained")
	for entry: Dictionary in [
		{"id": "_reference", "fixture": reference, "handle": "accounts_shared", "configured": ""},
		{"id": "_crossed", "fixture": crossed, "handle": "dedicated", "configured": "m4_canon_%s_crossed.db" % _stamp},
	]:
		var metadata: Dictionary = observed.get(entry["id"], {})
		assert_eq(metadata.get("status"), "OBSERVED")
		assert_eq(metadata.get("handle"), entry["handle"])
		assert_eq(metadata.get("configured_canon_path"), entry["configured"])
		assert_eq(metadata.get("active_path"), ProjectSettings.globalize_path("user://" + entry["fixture"]["relative_path"]))
		assert_eq(metadata.get("journal_mode"), "wal")
	_trace["passed"] = observed.size() == 2
