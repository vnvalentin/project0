extends GutTest

const ServerMainScript: Script = preload("res://server/server_main.gd")
const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")
const TelemetryIngestServiceScript: Script = preload("res://server/telemetry_ingest_service.gd")
const TelemetryRateLimiterScript: Script = preload("res://server/telemetry_rate_limiter.gd")
const ProvisionalSectorGeneratorScript: Script = preload("res://server/provisional_sector_generator.gd")
const CanonGenerationCoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
var _network_client: Node


func before_all() -> void:
	_network_client = get_tree().root.get_node_or_null("NetworkClient")
	if _network_client != null:
		_network_client.name = "FrontierTestNetworkClient"


func after_all() -> void:
	if _network_client != null:
		_network_client.name = "NetworkClient"


class FrontierServer extends "res://server/server_main.gd":
	var presentations: Array[Dictionary] = []
	var frontier_now: int = 0

	func _frontier_now_msec() -> int:
		return frontier_now

	func _send_sector_blueprint(peer_id: int, blueprint: Dictionary, ingress: Vector3, trace: Dictionary) -> void:
		presentations.append({"peer_id": peer_id, "blueprint": blueprint, "ingress": ingress, "trace": trace})


class FakeGenerator extends Node:
	var status: String = "unknown"
	var requests: Array[Dictionary] = []
	var result: Dictionary = {}

	func get_status(_sector_id: String) -> String:
		return status

	func get_provisional_result(_sector_id: String) -> Dictionary:
		return result

	func request_provisional_sector(sector_id: String, prompt: String, selected_profile: String, trace: Dictionary) -> String:
		requests.append({
			"sector_id": sector_id,
			"prompt": prompt,
			"selected_profile": selected_profile,
			"trace": trace.duplicate(true),
		})
		status = "pending"
		return "correlation-%d" % requests.size()


class FakeCanonRepository extends RefCounted:
	var blueprint: Dictionary = {}

	func get_canonical_sector(_sector_id: String) -> Dictionary:
		return {"outcome": "ok", "sector": {"blueprint": blueprint}}


class FakeTelemetrySink extends RefCounted:
	var envelopes: Array[Dictionary] = []
	var outcome: String = "ok"

	func emit(envelope: Dictionary) -> Dictionary:
		envelopes.append(envelope)
		return {"outcome": outcome}


class FakeMutationService extends RefCounted:
	func resolve_intent(_character_id: String, _intent: Dictionary) -> Dictionary:
		return {"status": "accepted", "reason": "ok", "applied_revision": 1}


class RecoverableCanonStore extends "res://server/sqlite_store.gd":
	var fail_writes: bool = true
	var write_attempts: int = 0

	func transaction(body: Callable) -> Dictionary:
		write_attempts += 1
		if fail_writes:
			return {"outcome": OUTCOME_TRANSACTION_FAILED, "detail": "Injected transient Canon write failure."}
		return super.transaction(body)


class CountingOllamaServer extends "res://scripts/fake_ollama_http_server.gd":
	var requests: int = 0

	func _process(delta: float) -> void:
		last_request_body = ""
		super._process(delta)
		if not last_request_body.is_empty():
			requests += 1


class FakeMutationRepository extends RefCounted:
	var outcome: String = "ok"
	var revision: int = 0
	var reads: int = 0

	func list_mutations(_sector_id: String) -> Dictionary:
		reads += 1
		return {"outcome": outcome, "mutations": [] if revision == 0 else [{"applied_revision": revision, "mutation_kind": "loot"}]}


func _frontier_server() -> FrontierServer:
	var server: FrontierServer = FrontierServer.new()
	var generator: FakeGenerator = FakeGenerator.new()
	server.root.add_child(generator)
	server._provisional_sector_generator = generator
	var repository: FakeCanonRepository = FakeCanonRepository.new()
	repository.blueprint = {"sector_id": "sector-0-0"}
	server._canon_repository = repository
	var detector: SectorBoundaryDetector = SectorBoundaryDetectorScript.new()
	detector.set_canon_lookup(func(sector_id: String) -> bool: return sector_id == "sector-0-0")
	detector.set_request_callback(Callable(server, "_request_sector_from_boundary"))
	detector.set_reload_callback(Callable(server, "_reload_sector_from_boundary"))
	server._sector_boundary_detector = detector
	_add_frontier_peer(server, 7)
	return server


func _add_frontier_peer(server: FrontierServer, peer_id: int) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(peer_id, Vector3(439.99, 1, 10))
	server._player_states[peer_id] = state
	server._configure_player_frontier(peer_id, state)
	state.position_updated.connect(server._on_player_state_position_updated)
	state.action_resolved.connect(server._on_player_state_action_resolved)
	state.combat_event_emitted.connect(server._on_player_state_combat_event_emitted)
	state.melee_swing_started.connect(server._on_player_state_melee_swing_started)
	state.character_bound.connect(server._on_player_state_character_bound)
	state.health_changed.connect(server._on_player_state_health_changed)
	state.character_snapshot_ready.connect(server._on_player_state_character_snapshot_ready)
	state.effective_mechanics_ready.connect(server._on_player_state_effective_mechanics_ready)
	state.player_defeated.connect(server._on_player_state_player_defeated)
	return state


func _destination_trace(server: FrontierServer) -> Dictionary:
	server._resolve_frontier_movement(7, Vector3(439.99, 1, 10), Vector3(440.1, 1, 10))
	server._jit_commit_trace_by_sector["sector-1-0"] = JitTraceContextScript.child(JitTraceContextScript.root(7, "sector-1-0"), "canon_db_commit")
	server._on_canonical_sector_ready("sector-1-0", {"sector_id": "sector-1-0"})
	return server.presentations.back()["trace"]


func _ack_event(trace: Dictionary) -> Dictionary:
	var payload: Dictionary = trace.duplicate(true)
	payload.erase("event_type")
	return {"event_type": "client_presentation_ack", "schema_version": 1, "payload": payload}


func test_live_frontier_prepares_once_holds_then_releases_without_telemetry() -> void:
	var server: FrontierServer = _frontier_server()
	var state: Node = server._player_states[7]
	server._reload_sector_from_boundary(7, "sector-0-0", state.position, JitTraceContextScript.root(7, "sector-0-0"))
	for presentation: Dictionary in server.presentations:
		server._on_client_telemetry_batch_received(7, [_ack_event(presentation["trace"])], 1)
	state.apply_input_intent(7, Vector2(1, 1), 10)
	for tick: int in range(20):
		state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 440.0, "live server wiring holds the unready destination")
	assert_gt(state.position.z, 10.5, "ready adjacent motion continues")
	assert_eq(server._provisional_sector_generator.requests.size(), 1, "held frames prepare destination exactly once")
	server._jit_commit_trace_by_sector["sector-1-0"] = JitTraceContextScript.child(JitTraceContextScript.root(7, "sector-1-0"), "canon_db_commit")
	server._on_canonical_sector_ready("sector-1-0", {"sector_id": "sector-1-0"})
	assert_eq(server.presentations.size(), 2, "source reentry and destination each have a presentation")
	if server.presentations.size() == 2:
		var destination: Dictionary = server.presentations.back()["trace"]
		assert_eq(destination.get("event_type"), "client_presentation_ack")
		server._on_client_telemetry_batch_received(7, [_ack_event(destination)], 2)
		state._physics_process(1.0 / 60.0)
		assert_gt(state.position.x, 440.0, "valid ACK releases the next movement without persistence")
		assert_eq(server.presentations.size(), 2, "committed crossing must not revoke its own ACK")
	server.free()


func test_current_town_ack_allows_origin_crossing_without_granting_neighbor_sector() -> void:
	var server: FrontierServer = _frontier_server()
	server._starting_town_hub_blueprint = {"sector_id": "starting_town_hub", "tiles": [
		{"x": -1, "y": 0, "kind": "floor"},
		{"x": 0, "y": 0, "kind": "floor"},
		{"x": 1, "y": 0, "kind": "floor"},
	]}
	var state: Node = server._player_states[7]
	state.position = Vector3(0.01, 1, 0)
	server._on_player_state_character_bound(7, "Tester", {})
	assert_eq(server.presentations.size(), 1, "world entry sends an explicit current-town presentation")
	if server.presentations.size() == 1:
		server._on_client_telemetry_batch_received(7, [_ack_event(server.presentations[0]["trace"])], 1)
	state.apply_input_intent(7, Vector2(-1, 0), 1)
	state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 0.0, "acknowledged town footprint crosses the grid origin normally")
	assert_eq(server._provisional_sector_generator.requests.size(), 0, "town footprint is not a new unexplored grid sector")
	var far_candidate: Vector3 = Vector3(-100, 1, 0)
	assert_ne(server._resolve_frontier_movement(7, state.position, far_candidate), far_candidate, "town ACK does not grant the whole neighboring 440-unit sector")
	server.free()


func test_invalid_ack_cannot_consume_pending_and_duplicate_keeps_valid_grant() -> void:
	var server: FrontierServer = _frontier_server()
	var trace: Dictionary = _destination_trace(server)
	var original: Dictionary = _ack_event(trace)
	var invalid_events: Array[Dictionary] = []
	for field: String in ["sector_id", "span_id", "trace_id", "spatial_guid", "parent_span_id", "status"]:
		var changed: Dictionary = original.duplicate(true)
		changed["payload"][field] = "wrong"
		invalid_events.append(changed)
	for schema: Variant in [2, "1", 1.0, null]:
		var changed: Dictionary = original.duplicate(true)
		changed["schema_version"] = schema
		invalid_events.append(changed)
	for duration: Variant in [-1.0, NAN, INF, "0"]:
		var changed: Dictionary = original.duplicate(true)
		changed["payload"]["duration_ms"] = duration
		invalid_events.append(changed)
	server._on_client_telemetry_batch_received(8, [original], 1)
	for event: Dictionary in invalid_events:
		server._on_client_telemetry_batch_received(7, [event], 1)
		assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
		assert_eq(server._jit_presentation_ack_tracker.match_pending(7, original), trace, "malformed ACK leaves the legitimate token pending")
	server._on_client_telemetry_batch_received(7, [original], 2)
	assert_true(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	server._on_client_telemetry_batch_received(7, [original], 3)
	assert_true(server._frontier_position_ready(7, Vector3(441, 1, 10)), "duplicate does not revoke a valid grant")
	assert_true(server._jit_presentation_ack_tracker.match_pending(7, original).is_empty(), "token consumed only once")
	server.free()


func test_two_waiters_receive_distinct_tokens_and_release_independently() -> void:
	var server: FrontierServer = _frontier_server()
	_add_frontier_peer(server, 8)
	for peer_id: int in [7, 8]:
		server._resolve_frontier_movement(peer_id, Vector3(439.99, 1, 10), Vector3(440.1, 1, 10))
	assert_eq(server._provisional_sector_generator.requests.size(), 1, "second waiter must not reinvoke generation")
	assert_eq(server._jit_peer_by_sector["sector-1-0"], 7, "generation owner is unchanged")
	server._jit_commit_trace_by_sector["sector-1-0"] = JitTraceContextScript.child(JitTraceContextScript.root(7, "sector-1-0"), "canon_db_commit")
	server._on_canonical_sector_ready("sector-1-0", {"sector_id": "sector-1-0"})
	assert_eq(server.presentations.size(), 2)
	var first: Dictionary = server.presentations[0]["trace"]
	var second: Dictionary = server.presentations[1]["trace"]
	assert_ne(first["span_id"], second["span_id"])
	server._on_client_telemetry_batch_received(8, [_ack_event(first)], 1)
	assert_false(server._frontier_position_ready(8, Vector3(441, 1, 10)))
	server._on_client_telemetry_batch_received(7, [_ack_event(first)], 1)
	assert_true(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	assert_false(server._frontier_position_ready(8, Vector3(441, 1, 10)))
	server._on_client_telemetry_batch_received(8, [_ack_event(second)], 2)
	assert_true(server._frontier_position_ready(8, Vector3(441, 1, 10)))
	server.free()


func test_failed_telemetry_sink_does_not_prevent_valid_release() -> void:
	var server: FrontierServer = _frontier_server()
	var trace: Dictionary = _destination_trace(server)
	var sink: FakeTelemetrySink = FakeTelemetrySink.new()
	sink.outcome = "write_failed"
	server._telemetry_ingest = TelemetryIngestServiceScript.new(sink, TelemetryRateLimiterScript.new())
	server._on_client_telemetry_batch_received(7, [_ack_event(trace)], 1)
	assert_eq(sink.envelopes.size(), 1, "the real ingest attempted persistence")
	assert_true(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	server.free()


func test_disconnect_and_reused_peer_id_do_not_inherit_pending_or_ready() -> void:
	var server: FrontierServer = _frontier_server()
	var old_trace: Dictionary = _destination_trace(server)
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 1)
	server._on_peer_disconnected(7)
	_add_frontier_peer(server, 7)
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 2)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	var fresh_trace: Dictionary = _destination_trace(server)
	assert_ne(fresh_trace["span_id"], old_trace["span_id"])
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 3)
	assert_eq(server._jit_presentation_ack_tracker.match_pending(7, _ack_event(fresh_trace)), fresh_trace)
	server._on_peer_disconnected(7)
	server._on_client_telemetry_batch_received(7, [_ack_event(fresh_trace)], 4)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	server.free()


func test_changed_journey_invalidates_previous_presentation() -> void:
	var server: FrontierServer = _frontier_server()
	var registry: Object = JourneyRegistryScript.new()
	server._journey_registry = registry
	var state: Node = server._player_states[7]
	state.character_id = "character-7"
	registry.enter("character-7", 7, 100)
	server._configure_player_frontier(7, state)
	var old_trace: Dictionary = _destination_trace(server)
	registry.mark_disconnected("character-7", 7, 101)
	registry.cleanup(1000)
	registry.enter("character-7", 7, 1001)
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 1)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)), "same character and peer cannot reuse an earlier journey token")
	server.free()


func test_authoritative_mutation_invalidates_pending_revision_before_ack() -> void:
	var server: FrontierServer = _frontier_server()
	var old_trace: Dictionary = _destination_trace(server)
	server._canon_mutation_service = FakeMutationService.new()
	server._on_canon_mutation_intent(7, {"sector_id": "sector-1-0"})
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 1)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)), "old presentation cannot authorize a changed Canon revision")
	server.free()


func test_changed_revision_reentry_rejects_old_token_and_accepts_new_child() -> void:
	var server: FrontierServer = _frontier_server()
	var mutations: FakeMutationRepository = FakeMutationRepository.new()
	server._canon_mutation_repository = mutations
	var old_trace: Dictionary = _destination_trace(server)
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 1)
	mutations.revision = 1
	server._canon_mutation_service = FakeMutationService.new()
	server._on_canon_mutation_intent(7, {"sector_id": "sector-1-0"})
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)), "mutation clears already granted readiness")
	server._canon_repository.blueprint = {"sector_id": "sector-1-0"}
	var reentry: Dictionary = JitTraceContextScript.child(old_trace, "canon_reentry")
	server._reload_sector_from_boundary(7, "sector-1-0", Vector3(440.1, 1, 10), reentry)
	var fresh: Dictionary = server.presentations.back()["trace"]
	assert_eq(fresh["event_type"], "client_presentation_ack")
	assert_eq(fresh["parent_span_id"], reentry["span_id"], "reentry has its own presentation child")
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 2)
	assert_eq(server._jit_presentation_ack_tracker.match_pending(7, _ack_event(fresh)), fresh)
	server._on_client_telemetry_batch_received(7, [_ack_event(fresh)], 3)
	assert_true(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	var reads_before_ticks: int = mutations.reads
	for tick: int in range(20):
		server._resolve_frontier_movement(7, Vector3(441, 1, 10), Vector3(441.1, 1, 10))
	assert_eq(mutations.reads, reads_before_ticks, "movement/ACK uses presentation cache, never per-frame revision reads")
	server.free()


func test_revision_read_failure_revokes_old_readiness_without_zero_revision_fallback() -> void:
	var server: FrontierServer = _frontier_server()
	var old_trace: Dictionary = _destination_trace(server)
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 1)
	var mutations: FakeMutationRepository = FakeMutationRepository.new()
	mutations.outcome = "query_failed"
	server._canon_mutation_repository = mutations
	server._canon_repository.blueprint = {"sector_id": "sector-1-0"}
	server._reload_sector_from_boundary(7, "sector-1-0", Vector3(440.1, 1, 10), JitTraceContextScript.root(7, "sector-1-0"))
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	assert_eq(server.presentations.size(), 1, "failed revision read sends no trusted presentation")
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 2)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	server.free()


func test_oversized_ack_batch_is_bounded_without_consuming_legitimate_token() -> void:
	var server: FrontierServer = _frontier_server()
	var trace: Dictionary = _destination_trace(server)
	var oversized: Array = []
	oversized.resize(51)
	oversized.fill(_ack_event(trace))
	server._on_client_telemetry_batch_received(7, oversized, 1)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	assert_eq(server._jit_presentation_ack_tracker.match_pending(7, _ack_event(trace)), trace)
	server._on_client_telemetry_batch_received(7, [_ack_event(trace)], 2)
	assert_true(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	server.free()


func test_character_change_drops_inflight_waiter_and_previous_ready_grants() -> void:
	var server: FrontierServer = _frontier_server()
	var old_trace: Dictionary = _destination_trace(server)
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 1)
	server._resolve_frontier_movement(7, Vector3(879.99, 1, 10), Vector3(880.1, 1, 10))
	var state: Node = server._player_states[7]
	state.bind_character("new-character", "New", {})
	var before_ready: int = server.presentations.size()
	server._jit_commit_trace_by_sector["sector-2-0"] = JitTraceContextScript.root(7, "sector-2-0")
	server._on_canonical_sector_ready("sector-2-0", {"sector_id": "sector-2-0"})
	assert_eq(server.presentations.size(), before_ready, "old character waiter cannot receive a new grant")
	server._on_client_telemetry_batch_received(7, [_ack_event(old_trace)], 2)
	assert_false(server._frontier_position_ready(7, Vector3(441, 1, 10)))
	server.free()


func test_town_revision_refresh_prepares_hub_not_grid_neighbor() -> void:
	var server: FrontierServer = _frontier_server()
	var town: Dictionary = {"sector_id": "starting_town_hub", "tiles": [{"x": 0, "y": 0, "kind": "floor"}]}
	server._starting_town_hub_blueprint = town
	server._canon_repository.blueprint = town
	server._sector_boundary_detector.set_canon_lookup(func(sector_id: String) -> bool: return sector_id == "starting_town_hub")
	var state: Node = server._player_states[7]
	state.position = Vector3(0.01, 1, 0)
	server._on_player_state_character_bound(7, "Tester", {})
	server._on_client_telemetry_batch_received(7, [_ack_event(server.presentations.back()["trace"])], 1)
	server._canon_mutation_service = FakeMutationService.new()
	server._on_canon_mutation_intent(7, {"sector_id": "starting_town_hub"})
	state.apply_input_intent(7, Vector2(-1, 0), 1)
	for tick: int in range(10):
		state._physics_process(1.0 / 60.0)
	assert_eq(server.presentations.size(), 2, "one fresh hub presentation replaces the invalidated revision")
	assert_eq(server._provisional_sector_generator.requests.size(), 0, "refresh must not request the origin-adjacent grid sector")
	server.free()


func test_unavailable_revision_read_stays_held_without_per_frame_queries() -> void:
	var server: FrontierServer = _frontier_server()
	server._canon_repository.blueprint = {"sector_id": "sector-1-0"}
	server._sector_boundary_detector.set_canon_lookup(func(_sector_id: String) -> bool: return true)
	var mutations: FakeMutationRepository = FakeMutationRepository.new()
	mutations.outcome = "query_failed"
	server._canon_mutation_repository = mutations
	var state: Node = server._player_states[7]
	state.apply_input_intent(7, Vector2(1, 0), 1)
	for tick: int in range(10):
		state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 440.0)
	assert_eq(mutations.reads, 1, "failed preparation stays deduplicated instead of retrying a DB query every tick")
	assert_eq(server.presentations.size(), 0)
	server.free()


func test_lost_ack_retries_presentation_without_rotating_pending_token() -> void:
	var server: FrontierServer = _frontier_server()
	var trace: Dictionary = _destination_trace(server)
	server._canon_repository.blueprint = {"sector_id": "sector-1-0"}
	server._sector_boundary_detector.set_canon_lookup(func(_sector_id: String) -> bool: return true)
	var current: Vector3 = Vector3(439.99, 1, 10)
	var destination: Vector3 = Vector3(440.1, 1, 10)
	for tick: int in range(10):
		assert_ne(server._resolve_frontier_movement(7, current, destination), destination)
	assert_eq(server.presentations.size(), 1, "no per-tick resends")
	server.frontier_now = 1000
	assert_ne(server._resolve_frontier_movement(7, current, destination), destination)
	assert_eq(server.presentations.size(), 2, "lost unreliable ACK gets a bounded presentation retry")
	assert_eq(server.presentations.back()["trace"], trace, "slow or reordered ACK remains valid across retry")
	server._on_client_telemetry_batch_received(7, [_ack_event(trace)], 1)
	assert_eq(server._resolve_frontier_movement(7, current, destination), destination)
	assert_eq(server._provisional_sector_generator.requests.size(), 1, "presentation retry never retries LLM generation")
	server.free()


func test_evicted_readiness_can_reprepare_despite_different_ack_order() -> void:
	var server: FrontierServer = _frontier_server()
	server._sector_boundary_detector.set_canon_lookup(func(_sector_id: String) -> bool: return true)
	var first_traces: Array[Dictionary] = []
	for sector: int in range(1, 18):
		var destination: Vector3 = Vector3(440 * sector + 0.1, 1, 10)
		server._canon_repository.blueprint = {"sector_id": "sector-%d-0" % sector}
		server._resolve_frontier_movement(7, Vector3(439.99, 1, 10), destination)
		var trace: Dictionary = server.presentations.back()["trace"]
		if sector < 3:
			first_traces.append(trace)
			if sector == 2:
				server._on_client_telemetry_batch_received(7, [_ack_event(first_traces[1]), _ack_event(first_traces[0])], 1)
		else:
			server._on_client_telemetry_batch_received(7, [_ack_event(trace)], sector)
	var revisit: Vector3 = Vector3(880.1, 1, 10)
	assert_false(server._frontier_position_ready(7, revisit), "ACK-order eviction removed sector two")
	server._canon_repository.blueprint = {"sector_id": "sector-2-0"}
	server.frontier_now = 1000
	var before_retry: int = server.presentations.size()
	server._resolve_frontier_movement(7, Vector3(439.99, 1, 10), revisit)
	assert_eq(server.presentations.size(), before_retry + 1, "cached preparation cannot suppress readiness recovery")
	server._on_client_telemetry_batch_received(7, [_ack_event(server.presentations.back()["trace"])], 20)
	assert_true(server._frontier_position_ready(7, revisit))
	server.free()


func test_failed_revision_lookup_recovers_after_bounded_retry() -> void:
	var server: FrontierServer = _frontier_server()
	server._canon_repository.blueprint = {"sector_id": "sector-1-0"}
	server._sector_boundary_detector.set_canon_lookup(func(_sector_id: String) -> bool: return true)
	var mutations: FakeMutationRepository = FakeMutationRepository.new()
	mutations.outcome = "query_failed"
	server._canon_mutation_repository = mutations
	var current: Vector3 = Vector3(439.99, 1, 10)
	var destination: Vector3 = Vector3(440.1, 1, 10)
	server._resolve_frontier_movement(7, current, destination)
	mutations.outcome = "ok"
	server.frontier_now = 999
	assert_ne(server._resolve_frontier_movement(7, current, destination), destination)
	assert_eq(mutations.reads, 1, "failed read is not retried before the bound")
	server.frontier_now = 1000
	assert_ne(server._resolve_frontier_movement(7, current, destination), destination)
	assert_eq(mutations.reads, 2)
	if server.presentations.size() == 1:
		server._on_client_telemetry_batch_received(7, [_ack_event(server.presentations[0]["trace"])], 1)
	assert_eq(server._resolve_frontier_movement(7, current, destination), destination)
	server.free()


func test_initial_canon_write_failure_recovers_without_regeneration() -> void:
	var server: FrontierServer = _frontier_server()
	var state: Node = server._player_states[7]
	state.set_physics_process(false)
	var database: String = "test_frontier_write_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	var store: RecoverableCanonStore = RecoverableCanonStore.new()
	assert_eq(store.open(database)["outcome"], "ok")
	var repository: CanonRepository = CanonRepositoryScript.new(store)
	assert_eq(repository.ensure_schema()["outcome"], "ok")
	server._canon_repository = repository
	server._sector_boundary_detector.set_canon_lookup(func(sector_id: String) -> bool:
		return repository.get_canonical_sector(sector_id)["outcome"] == "ok"
	)
	var coordinator: CanonGenerationCoordinator = CanonGenerationCoordinatorScript.new()
	coordinator.set_canonicalize_callback(repository.canonicalize_blueprint)
	server._canon_generation_coordinator = coordinator
	var ollama: CountingOllamaServer = CountingOllamaServer.new()
	add_child_autofree(ollama)
	var port: int = ollama.start()
	assert_gt(port, 0)
	var blueprint: Dictionary = {
		"schema_version": 1, "sector_id": "sector-1-0", "origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}
	ollama.next_response_body = JSON.stringify({"response": JSON.stringify(blueprint)})
	server._provisional_sector_generator.free()
	var generator: ProvisionalSectorGenerator = ProvisionalSectorGeneratorScript.new()
	generator.ollama_host = "http://127.0.0.1:%d" % port
	generator.request_timeout_sec = 2.0
	add_child_autofree(generator)
	generator.provisional_sector_ready.connect(server._on_provisional_sector_ready)
	server._provisional_sector_generator = generator
	watch_signals(generator)
	state.apply_input_intent(7, Vector2(1, 0), 1)
	state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 440.0, "movement starts generation but holds before completion")
	assert_eq(generator.get_status("sector-1-0"), ProvisionalSectorGeneratorScript.STATUS_PENDING)
	var correlation: String = generator.get_correlation_id("sector-1-0")
	await generator.provisional_sector_ready
	await wait_process_frames(1)
	assert_eq(generator.get_status("sector-1-0"), ProvisionalSectorGeneratorScript.STATUS_READY)
	assert_eq(store.write_attempts, 1, "valid generation attempted the initial Canon write")
	assert_eq(repository.get_canonical_sector("sector-1-0")["outcome"], "not_found")
	assert_eq(server.presentations.size(), 0, "failed persistence cannot issue a presentation")
	var premature: Dictionary = JitTraceContextScript.child(generator.get_provisional_result("sector-1-0")["trace_context"], "client_presentation_ack")
	server._on_client_telemetry_batch_received(7, [_ack_event(premature)], 1)
	store.fail_writes = false
	server.frontier_now = 999
	for tick: int in range(10):
		state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 440.0, "premature ACK cannot release an uncommitted sector")
	assert_eq(store.write_attempts, 1, "no per-frame persistence or pre-cooldown retry")
	server.frontier_now = 1000
	state._physics_process(1.0 / 60.0)
	assert_eq(store.write_attempts, 2, "cooldown retries initial Canon persistence")
	assert_eq(repository.get_canonical_sector("sector-1-0")["outcome"], "ok", "recovered write commits Canon")
	assert_eq(server.presentations.size(), 1, "only committed Canon becomes a presentation")
	assert_lt(state.position.x, 440.0, "commit alone does not authorize movement")
	if server.presentations.size() == 1:
		var presentation: Dictionary = server.presentations[0]
		assert_eq(presentation["blueprint"], repository.get_canonical_sector("sector-1-0")["sector"]["blueprint"])
		server._on_client_telemetry_batch_received(8, [_ack_event(presentation["trace"])], 2)
		state._physics_process(1.0 / 60.0)
		assert_lt(state.position.x, 440.0, "wrong-peer ACK cannot release committed Canon")
		server._on_client_telemetry_batch_received(7, [_ack_event(presentation["trace"])], 3)
	state._physics_process(1.0 / 60.0)
	assert_gt(state.position.x, 440.0, "committed Canon and matching ACK release movement")
	assert_eq(store.write_attempts, 2, "successful retry does not write on subsequent movement")
	assert_eq(generator.get_correlation_id("sector-1-0"), correlation)
	assert_eq(ollama.requests, 1, "persistence recovery must never issue another LLM request")
	assert_signal_emit_count(generator, "provisional_sector_ready", 1, "one generation completion only")
	ollama.stop()
	store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var database_path: String = ProjectSettings.globalize_path("user://%s%s" % [database, suffix])
		if FileAccess.file_exists(database_path):
			DirAccess.remove_absolute(database_path)
	server.free()


func test_timeout_fallback_commits_canon_and_holds_until_matching_ack() -> void:
	var server: FrontierServer = _frontier_server()
	var state: Node = server._player_states[7]
	state.set_physics_process(false)
	var database: String = "test_fallback_canon_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	var store: RecoverableCanonStore = RecoverableCanonStore.new()
	store.fail_writes = false
	assert_eq(store.open(database)["outcome"], "ok")
	var repository: CanonRepository = CanonRepositoryScript.new(store)
	assert_eq(repository.ensure_schema()["outcome"], "ok")
	server._canon_repository = repository
	server._sector_boundary_detector.set_canon_lookup(func(sector_id: String) -> bool:
		return repository.get_canonical_sector(sector_id)["outcome"] == "ok"
	)
	var coordinator: CanonGenerationCoordinator = CanonGenerationCoordinatorScript.new()
	coordinator.set_canonicalize_callback(repository.canonicalize_blueprint)
	server._canon_generation_coordinator = coordinator
	var ollama: CountingOllamaServer = CountingOllamaServer.new()
	ollama.respond_at_all = false
	add_child_autofree(ollama)
	var port: int = ollama.start()
	assert_gt(port, 0)
	server._provisional_sector_generator.free()
	var generator: ProvisionalSectorGenerator = ProvisionalSectorGeneratorScript.new()
	generator.ollama_host = "http://127.0.0.1:%d" % port
	generator.request_timeout_sec = 0.1
	add_child_autofree(generator)
	generator.provisional_sector_ready.connect(server._on_provisional_sector_ready)
	server._provisional_sector_generator = generator
	watch_signals(generator)
	state.apply_input_intent(7, Vector2(1, 0), 1)
	state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 440.0)
	var correlation: String = generator.get_correlation_id("sector-1-0")
	await generator.provisional_sector_ready
	await wait_process_frames(1)
	var generated: Dictionary = generator.get_provisional_result("sector-1-0")
	assert_eq(generated.get("request_outcome"), "timeout", "model timeout must not become LLM success")
	assert_eq(generated.get("validation_outcome"), "", "model schema validation was never reached")
	assert_eq(generated.get("source"), "fallback")
	assert_true(generated.get("fallback_selected", false))
	assert_true(String(generated.get("detail", "")).contains("result=%d" % HTTPRequest.RESULT_TIMEOUT))
	assert_eq(generated.get("candidate_validation_outcome", ""), "valid", "fallback is validated separately")
	assert_eq(generated["trace_spans"][0]["status"], "ERROR")
	assert_eq(generated["trace_spans"][1]["status"], "OK", "schema span describes the deliverable candidate")
	assert_eq(store.write_attempts, 1, "independently valid fallback reaches real SQLite Canon")
	var stored: Dictionary = repository.get_canonical_sector("sector-1-0")
	assert_eq(stored["outcome"], "ok")
	assert_eq(server.presentations.size(), 1, "only stored Canon is dispatched")
	state._physics_process(1.0 / 60.0)
	assert_lt(state.position.x, 440.0, "committed fallback alone cannot release the frontier")
	if server.presentations.size() == 1 and stored["outcome"] == "ok":
		var presentation: Dictionary = server.presentations[0]
		assert_eq(JSON.stringify(presentation["blueprint"]), JSON.stringify(stored["sector"]["blueprint"]), "all serialized Canon fields match")
		assert_eq(presentation["blueprint"]["archetype"], "WILDERNESS")
		server._on_client_telemetry_batch_received(8, [_ack_event(presentation["trace"])], 1)
		state._physics_process(1.0 / 60.0)
		assert_lt(state.position.x, 440.0, "wrong-peer ACK cannot release fallback")
		server._on_client_telemetry_batch_received(7, [_ack_event(presentation["trace"])], 2)
		state._physics_process(1.0 / 60.0)
		assert_gt(state.position.x, 440.0, "correct ACK releases durable fallback")
		assert_eq(coordinator.accept_generation_result("sector-1-0", "WILDERNESS", generated)["outcome"], "idempotent")
		server._reload_sector_from_boundary(7, "sector-1-0", state.position, presentation["trace"])
		assert_eq(server.presentations.back()["blueprint"], stored["sector"]["blueprint"])
		assert_eq(server.presentations.back()["trace"]["spatial_guid"], presentation["trace"]["spatial_guid"])
		assert_eq(repository.get_canonical_sector("sector-1-0")["sector"], stored["sector"])
		var conflicting: Dictionary = generated.duplicate(true)
		conflicting["blueprint"]["tiles"][0]["kind"] = "wall"
		assert_eq(coordinator.accept_generation_result("sector-1-0", "WILDERNESS", conflicting)["outcome"], "conflict")
		assert_eq(repository.get_canonical_sector("sector-1-0")["sector"], stored["sector"], "fallback cannot replace immutable Canon")
	assert_eq(generator.get_correlation_id("sector-1-0"), correlation)
	assert_signal_emit_count(generator, "provisional_sector_ready", 1, "no regeneration on replay")
	assert_eq(ollama.requests, 1, "timeout delivery and replay never retry generation")
	ollama.stop()
	store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var database_path: String = ProjectSettings.globalize_path("user://%s%s" % [database, suffix])
		if FileAccess.file_exists(database_path):
			DirAccess.remove_absolute(database_path)
	server.free()


func test_cached_invalid_and_fallback_candidates_cannot_release_frontier() -> void:
	var valid: Dictionary = {
		"request_outcome": "validated", "validation_outcome": "valid", "selected_profile": "WILDERNESS",
		"blueprint": {"schema_version": 1, "sector_id": "sector-1-0", "origin": {"x": 0, "y": 0},
			"tiles": [{"x": 0, "y": 0, "kind": "floor"}]},
	}
	var fallback: Dictionary = valid.duplicate(true)
	fallback["request_outcome"] = "transport_error"
	fallback["fallback_selected"] = true
	var invalid_schema: Dictionary = valid.duplicate(true)
	invalid_schema["blueprint"]["tiles"][0]["kind"] = "unsupported"
	var invalid_profile: Dictionary = valid.duplicate(true)
	invalid_profile["blueprint"]["archetype"] = "SETTLEMENT"
	var wrong_sector: Dictionary = valid.duplicate(true)
	wrong_sector["blueprint"]["sector_id"] = "sector-2-0"
	for candidate: Dictionary in [fallback, invalid_schema, invalid_profile, wrong_sector]:
		var server: FrontierServer = _frontier_server()
		var generator: FakeGenerator = server._provisional_sector_generator
		generator.status = "ready"
		generator.result = candidate
		var writes: Array[Dictionary] = []
		var coordinator: CanonGenerationCoordinator = CanonGenerationCoordinatorScript.new()
		coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
			writes.append(blueprint)
			return {"outcome": "ok", "sector": {"blueprint": blueprint}}
		)
		server._canon_generation_coordinator = coordinator
		var state: Node = server._player_states[7]
		state.apply_input_intent(7, Vector2(1, 0), 1)
		for retry_time: int in [0, 999, 1000, 1999, 2000]:
			server.frontier_now = retry_time
			state._physics_process(1.0 / 60.0)
			assert_lt(state.position.x, 440.0, "cached rejection cannot grant movement")
		assert_eq(writes.size(), 0, "unchanged admission gates reject before Canon")
		assert_eq(server.presentations.size(), 0)
		assert_eq(generator.requests.size(), 0, "rejected cached results cannot restart generation")
		server.free()


func test_persistent_canon_write_failure_retries_only_at_preparation_bound() -> void:
	var server: FrontierServer = _frontier_server()
	var generator: FakeGenerator = server._provisional_sector_generator
	generator.status = "ready"
	generator.result = {
		"request_outcome": "validated", "validation_outcome": "valid", "selected_profile": "WILDERNESS",
		"blueprint": {"schema_version": 1, "sector_id": "sector-1-0", "origin": {"x": 0, "y": 0},
			"tiles": [{"x": 0, "y": 0, "kind": "floor"}]},
	}
	var writes: Array[Dictionary] = []
	var coordinator: CanonGenerationCoordinator = CanonGenerationCoordinatorScript.new()
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		writes.append(blueprint)
		return {"outcome": "transaction_failed", "detail": "Persistence remains unavailable."}
	)
	server._canon_generation_coordinator = coordinator
	var state: Node = server._player_states[7]
	state.apply_input_intent(7, Vector2(1, 0), 1)
	for retry_time: int in [0, 999, 1000, 1999, 2000]:
		server.frontier_now = retry_time
		for tick: int in range(10):
			state._physics_process(1.0 / 60.0)
		assert_eq(writes.size(), 1 + retry_time / 1000, "at most one persistence attempt per cooldown")
		assert_lt(state.position.x, 440.0, "failed persistence remains fail-closed")
	assert_eq(server.presentations.size(), 0)
	assert_eq(generator.requests.size(), 0, "persistence retries cannot restart generation")
	server.free()


func test_first_peer_remains_generation_owner_for_duplicate_sector_request() -> void:
	var server: SceneTree = ServerMainScript.new()
	var generator: FakeGenerator = FakeGenerator.new()
	server._provisional_sector_generator = generator
	var first_trace: Dictionary = JitTraceContextScript.root(7, "sector-1-0")
	var second_trace: Dictionary = JitTraceContextScript.root(8, "sector-1-0")

	server._request_sector_from_boundary(7, "sector-1-0", Vector3(440.0, 0.0, 0.0), first_trace)
	server._request_sector_from_boundary(8, "sector-1-0", Vector3(441.0, 0.0, 0.0), second_trace)

	assert_eq(server._jit_peer_by_sector["sector-1-0"], 7)
	assert_eq(generator.requests.size(), 1)
	assert_eq(generator.requests[0]["trace"]["trace_id"], first_trace["trace_id"], "the generator retains its first trace")
	generator.free()
	server.free()


func test_presentation_context_is_retained_before_telemetry_persistence() -> void:
	var server: FrontierServer = _frontier_server()
	var detector: Object = server._sector_boundary_detector
	server._request_sector_from_boundary(7, "sector-1-0", Vector3(440, 1, 10), JitTraceContextScript.root(7, "sector-1-0"))
	server._jit_commit_trace_by_sector["sector-1-0"] = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-1-0"),
		"canon_db_commit",
	)

	server._on_canonical_sector_ready("sector-1-0", {"sector_id": "sector-1-0"})

	assert_true(detector._trace_by_sector.has("sector-1-0"), "send-time server context survives telemetry outage")
	assert_eq(
		detector._trace_by_sector["sector-1-0"]["event_type"],
		"client_presentation_ack",
		"the retained parent is the server-issued presentation span",
	)
	server.free()


func test_canon_reentry_is_emitted_by_server_before_client_presentation() -> void:
	var server: SceneTree = ServerMainScript.new()
	var repository: FakeCanonRepository = FakeCanonRepository.new()
	repository.blueprint = {"sector_id": "sector-1-0"}
	var sink: FakeTelemetrySink = FakeTelemetrySink.new()
	server._canon_repository = repository
	server._telemetry_sink = sink
	var reentry_trace: Dictionary = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-1-0"),
		"canon_reentry",
	)

	server._reload_sector_from_boundary(7, "sector-1-0", Vector3.ZERO, reentry_trace)

	assert_eq(sink.envelopes.size(), 1)
	assert_eq(sink.envelopes[0]["event_type"], "canon_reentry")
	assert_eq(sink.envelopes[0]["payload"]["span_id"], reentry_trace["span_id"])
	server.free()


func test_boundary_prompt_carries_schema_contract_for_the_requested_sector() -> void:
	var server: SceneTree = ServerMainScript.new()
	var generator: FakeGenerator = FakeGenerator.new()
	server._provisional_sector_generator = generator

	server._request_sector_from_boundary(7, "sector-3-2", Vector3(1320.0, 0.0, 880.0), JitTraceContextScript.root(7, "sector-3-2"))

	assert_eq(generator.requests.size(), 1)
	var prompt: String = generator.requests[0]["prompt"]
	assert_true(prompt.contains("\"sector_id\": \"sector-3-2\""), "prompt states the authoritative, request-specific sector_id")
	assert_true(prompt.contains("\"schema_version\": 3"), "prompt states the supported schema version")
	assert_true(prompt.contains("\"origin\": {\"x\": 0, \"y\": 0}"), "prompt states the fixed sector-local origin so a candidate cannot claim a mismatched origin")
	assert_true(prompt.contains("\"tiles\": 1..%d" % SectorBlueprintSchemaScript.MAX_TILE_COUNT), "prompt states the non-empty bounded tiles field")
	assert_true(prompt.contains("{\"x\": int, \"y\": int, \"kind\": string}"), "prompt states each tile's required fields")
	for kind: String in SectorBlueprintSchemaScript.SUPPORTED_TILE_KINDS:
		assert_true(prompt.contains(kind), "prompt allows tile kind '%s'" % kind)
	var bound: String = str(SectorBlueprintSchemaScript.MAX_COORDINATE_ABS)
	assert_true(prompt.contains("-%s..%s" % [bound, bound]), "prompt states the coordinate bound of %s" % bound)
	assert_true(prompt.contains("Return ONLY one JSON object"), "prompt excludes prose and thinking from the response")
	assert_true(prompt.contains("Output valid JSON only."), "prompt constrains the model to valid JSON-only output")

	server._request_sector_from_boundary(9, "sector-5-1", Vector3(2200.0, 0.0, 440.0), JitTraceContextScript.root(9, "sector-5-1"))
	assert_true(generator.requests[1]["prompt"].contains("\"sector_id\": \"sector-5-1\""), "a different boundary crossing embeds its own authoritative sector_id, not the earlier request's")
	assert_false(generator.requests[1]["prompt"].contains("sector-3-2"), "a different boundary crossing does not leak the earlier request's sector_id")

	generator.free()
	server.free()