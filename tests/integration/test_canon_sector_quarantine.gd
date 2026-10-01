extends GutTest
## Slice 1343: a damaged known Canon sector fails closed. It is quarantined, entry
## is denied with a reason, a high-severity diagnostic names it, and healthy
## sectors keep presenting, with no generation, repair or Canon write.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const CanonSectorIntegrityScript: Script = preload("res://server/canon_sector_integrity.gd")
const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")

const TARGET: String = "sector-1-0"
const HEALTHY: String = "sector-2-0"
const HUB: String = "starting_town_hub"
const TARGET_INGRESS: Vector3 = Vector3(440.1, 1, 10)
const HEALTHY_INGRESS: Vector3 = Vector3(880.1, 1, 10)

var _network_client: Node
var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null


class QuarantineServer extends "res://server/server_main.gd":
	var presentations: Array[Dictionary] = []
	var denials: Array[Dictionary] = []

	func _send_sector_blueprint(peer_id: int, blueprint: Dictionary, ingress: Vector3, trace: Dictionary) -> void:
		presentations.append({"peer_id": peer_id, "sector_id": String(blueprint.get("sector_id", "")), "trace": trace})

	func _send_sector_entry_denied(peer_id: int, denial: Dictionary) -> void:
		denials.append({"peer_id": peer_id, "denial": denial})


class FakeGenerator extends Node:
	var requests: Array[String] = []

	func get_status(_sector_id: String) -> String:
		return "unknown"

	func request_provisional_sector(sector_id: String, _prompt: String, _profile: String, _trace: Dictionary) -> String:
		requests.append(sector_id)
		return "correlation-%d" % requests.size()


class FakeTelemetrySink extends RefCounted:
	var envelopes: Array[Dictionary] = []

	func emit(envelope: Dictionary) -> Dictionary:
		envelopes.append(envelope)
		return {"outcome": "ok"}


class CountingService extends RefCounted:
	var calls: int = 0

	func resolve_intent(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> Dictionary:
		calls += 1
		return {"status": "accepted", "reason": "ok"}


func before_all() -> void:
	_network_client = get_tree().root.get_node_or_null("NetworkClient")
	if _network_client != null:
		_network_client.name = "QuarantineTestNetworkClient"


func after_all() -> void:
	if _network_client != null:
		_network_client.name = "NetworkClient"


func before_each() -> void:
	_relative_path = "test_canon_sector_quarantine_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()
	for sector_id: String in [TARGET, HEALTHY]:
		assert_eq(_canon.canonicalize_blueprint(_blueprint(sector_id))["outcome"], CanonRepositoryScript.OUTCOME_OK)
		assert_eq(_mutations.apply_mutation(_loot_event(sector_id))["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _blueprint(sector_id: String) -> Dictionary:
	var tiles: Array[Dictionary] = []
	for horizontal: int in range(5):
		for vertical: int in range(-1, 5):
			tiles.append({"x": horizontal, "y": vertical, "kind": "floor"})
	return {
		"schema_version": 5, "sector_id": sector_id, "detail_origin": {"x": 0, "y": 10},
		"origin": {"x": 0, "y": 0}, "tiles": tiles,
		"structures": [{"structure_id": "well-1", "kind": "well", "x": 2, "y": 2, "facing_degrees": 0}],
	}


func _well_guid(sector_id: String) -> String:
	return CanonEntityGuidScript.derive(sector_id, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "well-1")


func _loot_event(sector_id: String) -> Dictionary:
	return {
		"schema_version": 1, "event_id": "evt-%s" % sector_id, "sector_id": sector_id,
		"target_guid": _well_guid(sector_id), "mutation_kind": "loot", "actor_player_id": "character-1",
		"server_tick": 3, "expected_revision": 0, "payload": {"looted": true},
	}


func _server() -> QuarantineServer:
	var server: QuarantineServer = QuarantineServer.new()
	server._starting_town_hub_blueprint = {
		"schema_version": 1, "sector_id": HUB, "origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}
	var generator: FakeGenerator = FakeGenerator.new()
	server.root.add_child(generator)
	server._provisional_sector_generator = generator
	server._canon_repository = _canon
	server._canon_mutation_repository = _mutations
	server._telemetry_sink = FakeTelemetrySink.new()
	var detector: SectorBoundaryDetector = SectorBoundaryDetectorScript.new()
	detector.set_canon_lookup(Callable(server, "_boundary_has_canon"))
	detector.set_request_callback(Callable(server, "_request_sector_from_boundary"))
	detector.set_reload_callback(Callable(server, "_reload_sector_from_boundary"))
	server._sector_boundary_detector = detector
	_add_peer(server, 7, Vector3(439.99, 1, 10))
	return server


func _add_peer(server: QuarantineServer, peer_id: int, position: Vector3) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(peer_id, position)
	server._player_states[peer_id] = state
	server._configure_player_frontier(peer_id, state)
	return state


func _raw_canon() -> Dictionary:
	return {
		"sectors": _store.query("SELECT * FROM canon_sectors ORDER BY sector_id;")["rows"],
		"mutations": _store.query("SELECT * FROM canon_mutations ORDER BY sector_id, applied_revision;")["rows"],
	}


func _enter_target(server: QuarantineServer) -> void:
	server._resolve_frontier_movement(7, Vector3(439.99, 1, 10), TARGET_INGRESS)


func _assert_quarantined(server: QuarantineServer, failure_class: String) -> void:
	var evidence: Dictionary = server.sector_quarantine_evidence()
	assert_true(evidence["quarantined"].has(TARGET), "damaged sector is quarantined")
	assert_eq(evidence["quarantined"].get(TARGET, {}).get("failure_class"), failure_class)
	assert_eq(evidence["quarantined"].get(TARGET, {}).get("severity"), "high")
	assert_eq(server.denials.size(), 1, "one explicit denial for the entering peer")
	if server.denials.size() == 1:
		assert_eq(server.denials[0]["peer_id"], 7)
		assert_eq(server.denials[0]["denial"], {"sector_id": TARGET, "reason_code": "sector_quarantined", "failure_class": failure_class})
	assert_eq(server.presentations.filter(func(entry: Dictionary) -> bool: return entry["sector_id"] == TARGET).size(), 0, "damaged sector is never presented")
	assert_eq(server._provisional_sector_generator.requests.size(), 0, "damaged known sector never requests generation")
	assert_eq(server.canon_reload_events().size(), 0, "a failed entry fabricates no reload event")
	assert_false(server._frontier_position_ready(7, TARGET_INGRESS), "movement into the quarantined sector stays blocked")
	var types: Array = server._telemetry_sink.envelopes.map(func(envelope: Dictionary) -> String: return envelope["event_type"])
	assert_eq(types.count("canon.sector_quarantined"), 1, "one high-severity quarantine diagnostic")
	assert_eq(types.count("canon.sector_entry_denied"), 1, "one high-severity denial diagnostic")
	for envelope: Dictionary in server._telemetry_sink.envelopes:
		if String(envelope["event_type"]).begins_with("canon.sector_"):
			assert_eq(envelope["payload"].get("sector_id"), TARGET)
			assert_eq(envelope["payload"].get("failure_class"), failure_class)
			assert_eq(envelope["payload"].get("severity"), "high")


func _run_fault_case(fault_sql: String, failure_class: String) -> void:
	assert_eq(_store.query(fault_sql)["outcome"], SqliteStore.OUTCOME_OK, "fault seeded on owned test data")
	var faulted: Dictionary = _raw_canon()
	var counters: Dictionary = _store.canon_write_counters()
	var server: QuarantineServer = _server()
	_enter_target(server)
	for retry: int in range(5):
		_enter_target(server)
	_assert_quarantined(server, failure_class)
	assert_eq(_raw_canon(), faulted, "faulted Canon rows are preserved byte-for-byte (no repair or deletion)")
	assert_eq(_store.canon_write_counters(), counters, "no Canon INSERT/UPDATE during handling")
	server.free()


func test_missing_base_record_of_known_sector_is_quarantined_not_regenerated() -> void:
	_run_fault_case("DELETE FROM canon_sectors WHERE sector_id = '%s';" % TARGET, CanonSectorIntegrityScript.FAILURE_BASE_MISSING)


func test_corrupt_blueprint_payload_is_quarantined() -> void:
	_run_fault_case("UPDATE canon_sectors SET blueprint_json = '{\"schema_version\": 5, \"sector_id\"' WHERE sector_id = '%s';" % TARGET, CanonSectorIntegrityScript.FAILURE_BLUEPRINT_CORRUPT)


func test_schema_invalid_blueprint_is_quarantined() -> void:
	_run_fault_case("UPDATE canon_sectors SET blueprint_json = '{\"schema_version\": 99, \"sector_id\": \"%s\"}' WHERE sector_id = '%s';" % [TARGET, TARGET], CanonSectorIntegrityScript.FAILURE_BLUEPRINT_CORRUPT)


func test_corrupt_mutation_payload_is_quarantined() -> void:
	_run_fault_case("UPDATE canon_mutations SET payload_json = '[1,' WHERE sector_id = '%s';" % TARGET, CanonSectorIntegrityScript.FAILURE_MUTATION_CORRUPT)


func test_revision_gap_is_a_replay_inconsistency() -> void:
	_run_fault_case("UPDATE canon_mutations SET applied_revision = 2 WHERE sector_id = '%s';" % TARGET, CanonSectorIntegrityScript.FAILURE_REPLAY_INCONSISTENT)


func test_unaddressable_mutation_target_is_a_replay_inconsistency() -> void:
	_run_fault_case("UPDATE canon_mutations SET target_guid = 'ghost-entity' WHERE sector_id = '%s';" % TARGET, CanonSectorIntegrityScript.FAILURE_REPLAY_INCONSISTENT)


func test_unreadable_store_is_distinguished_and_denied_without_quarantine() -> void:
	var server: QuarantineServer = _server()
	_store.close()
	_enter_target(server)
	var evidence: Dictionary = server.sector_quarantine_evidence()
	assert_false(evidence["quarantined"].has(TARGET), "inability to observe is not recorded as observed damage")
	assert_eq(evidence["events"].map(func(event: Dictionary) -> String: return event["event_type"]), ["CANON_SECTOR_UNOBSERVABLE"])
	assert_eq(server.denials.size(), 1)
	if server.denials.size() == 1:
		assert_eq(server.denials[0]["denial"], {"sector_id": TARGET, "reason_code": "sector_unavailable", "failure_class": "base_unreadable"})
	var types: Array = server._telemetry_sink.envelopes.map(func(envelope: Dictionary) -> String: return envelope["event_type"])
	assert_eq(types.count("canon.sector_unobservable"), 1, "one high-severity unobservable diagnostic")
	assert_eq(server.presentations.size(), 0)
	assert_eq(server._provisional_sector_generator.requests.size(), 0, "an unreadable known sector never requests generation")
	assert_eq(server.canon_reload_events().size(), 0)
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStore.OUTCOME_OK)
	server._reload_sector_from_boundary(7, TARGET, TARGET_INGRESS, JitTraceContextScript.root(7, TARGET))
	assert_eq(server.presentations.size(), 1, "the sector presents once the store is readable again")
	assert_eq(server.canon_reload_events().size(), 1)
	server.free()


func test_healthy_sector_and_never_generated_sector_continue_beside_quarantine() -> void:
	_store.query("DELETE FROM canon_sectors WHERE sector_id = '%s';" % TARGET)
	var server: QuarantineServer = _server()
	_add_peer(server, 8, Vector3(879.99, 1, 10))
	_enter_target(server)
	_assert_quarantined(server, CanonSectorIntegrityScript.FAILURE_BASE_MISSING)
	server._reload_sector_from_boundary(8, HEALTHY, HEALTHY_INGRESS, JitTraceContextScript.root(8, HEALTHY))
	assert_eq(server.presentations.filter(func(entry: Dictionary) -> bool: return entry["sector_id"] == HEALTHY).size(), 1, "healthy sector still presents")
	assert_eq(server.canon_reload_events().size(), 1, "healthy re-entry records its one reload event")
	assert_false(server.sector_quarantine_evidence()["quarantined"].has(HEALTHY))
	server._resolve_frontier_movement(8, Vector3(1319.99, 1, 10), Vector3(1320.1, 1, 10))
	var requests: Array[String] = server._provisional_sector_generator.requests
	assert_eq(requests.size(), 1, "a never-generated sector still requests generation")
	if requests.size() == 1:
		assert_eq(requests[0], "sector-3-0")
	server.free()


func test_quarantined_sector_rejects_mutation_and_interaction_intents_without_writes() -> void:
	_store.query("UPDATE canon_mutations SET payload_json = 'null' WHERE sector_id = '%s';" % TARGET)
	var server: QuarantineServer = _server()
	_enter_target(server)
	var faulted: Dictionary = _raw_canon()
	var mutation_service: CountingService = CountingService.new()
	var interaction_service: CountingService = CountingService.new()
	server._canon_mutation_service = mutation_service
	server._environmental_interaction_service = interaction_service
	server._on_canon_mutation_intent(7, {"sector_id": TARGET, "client_seq": 3})
	var resolution: Dictionary = server._resolve_environmental_interaction(7, {"sector_id": TARGET, "client_seq": 4})
	assert_eq(mutation_service.calls, 0, "mutation intent is refused before the service")
	assert_eq(interaction_service.calls, 0, "interaction intent is refused before the service")
	assert_eq(resolution, {"status": "rejected", "reason": "sector_quarantined", "client_seq": 4})
	assert_eq(_raw_canon(), faulted, "no Canon write")
	server.free()


func test_damaged_hub_history_denies_reclaimed_entry_without_reload_event() -> void:
	_store.query("INSERT INTO canon_mutations VALUES ('evt-bad-hub', '%s', 'ghost', 'unlock_gate', '{}', 'character-1', 1, 0, 1, 1, 0);" % HUB)
	var server: QuarantineServer = _server()
	var state: Node = _add_peer(server, 9, Vector3(0, 1, 0))
	server._reclaimed_journey_peers[9] = true
	server._reload_reclaimed_hub_entry(9, state.position)
	assert_eq(server.canon_reload_events().size(), 0, "no CANON_SECTOR_RELOADED for a failed hub entry")
	assert_eq(server.sector_quarantine_evidence()["quarantined"].get(HUB, {}).get("failure_class"), CanonSectorIntegrityScript.FAILURE_REPLAY_INCONSISTENT)
	assert_eq(server.denials.map(func(entry: Dictionary) -> int: return entry["peer_id"]), [9])
	assert_eq(server.presentations.size(), 0)
	server.free()
