extends GutTest
## Slice #1043: production-path correlation from authoritative boundary
## observation through generation, Canon, client presentation, and re-entry.

const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const ProvisionalSectorGeneratorScript: Script = preload("res://server/provisional_sector_generator.gd")
const CanonGenerationCoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")
const SectorArchetypeAdmissionScript: Script = preload("res://server/sector_archetype_admission.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const TelemetrySinkScript: Script = preload("res://server/telemetry_sink.gd")
const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")
const TelemetryRateLimiterScript: Script = preload("res://server/telemetry_rate_limiter.gd")
const TelemetryIngestServiceScript: Script = preload("res://server/telemetry_ingest_service.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const JitPresentationAckTrackerScript: Script = preload("res://server/jit_presentation_ack_tracker.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")

const PEER_ID: int = 1043
const TARGET_POSITION: Vector3 = Vector3(17.0, 0.0, 32.0)
const TRANSIT_POSITION: Vector3 = Vector3(457.0, 0.0, 32.0)
const EXPECTED_EVENTS: Array[String] = [
	"player_trigger_event",
	"llm_generation_latency",
	"schema_validation_result",
	"canon_db_commit",
	"client_presentation_ack",
	"canon_reentry",
]

var _relative_path: String = ""
var _store: SqliteStore = null
var _original_scene: Node = null
var _gameplay_root: Node3D = null


func before_each() -> void:
	_relative_path = "test_jit_production_trace_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_original_scene = get_tree().current_scene
	_gameplay_root = null
	var target_sector: String = SectorBoundaryDetectorScript.sector_id_for_position(TARGET_POSITION)
	var network_client: Node = get_tree().root.get_node("NetworkClient")
	network_client._completed_geometry_sectors.erase(target_sector)
	network_client._telemetry_queue.take_batch(Time.get_ticks_msec())


func after_each() -> void:
	var target_sector: String = SectorBoundaryDetectorScript.sector_id_for_position(TARGET_POSITION)
	var network_client: Node = get_tree().root.get_node("NetworkClient")
	network_client._completed_geometry_sectors.erase(target_sector)
	network_client._telemetry_queue.take_batch(Time.get_ticks_msec())
	get_tree().current_scene = _original_scene
	if _gameplay_root != null:
		_gameplay_root.queue_free()
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_live_trace_reaches_presentation_and_continues_on_canon_reentry() -> void:
	var target_sector: String = SectorBoundaryDetectorScript.sector_id_for_position(TARGET_POSITION)
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	assert_gt(port, 0, "the fake Ollama endpoint listens")
	add_child_autofree(fake_server)
	fake_server.next_response_body = JSON.stringify({"response": JSON.stringify(_blueprint(target_sector))})

	var repository: CanonRepository = CanonRepositoryScript.new(_store)
	assert_eq(repository.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sink: TelemetrySink = TelemetrySinkScript.new(_store)
	assert_eq(sink.ensure_schema()["outcome"], TelemetrySinkScript.OUTCOME_OK)
	var ingest: TelemetryIngestService = TelemetryIngestServiceScript.new(
		sink,
		TelemetryRateLimiterScript.new(),
	)

	var generator: ProvisionalSectorGenerator = ProvisionalSectorGeneratorScript.new()
	generator.ollama_host = "http://127.0.0.1:%d" % port
	generator.request_timeout_sec = 2.0
	add_child_autofree(generator)
	var detector: SectorBoundaryDetector = SectorBoundaryDetectorScript.new()
	detector.set_canon_lookup(Callable(repository, "get_canonical_sector"))
	var target_generation_calls: Array[int] = [0]
	detector.set_request_callback(func(_peer_id: int, sector_id: String, _position: Vector3, trace: Dictionary) -> void:
		if sector_id == target_sector:
			target_generation_calls[0] += 1
			generator.request_provisional_sector(
				sector_id,
				"generate %s" % sector_id,
				SectorArchetypeAdmissionScript.PROFILE_POI_ANCHOR,
				trace
			)
	)

	var trigger: Dictionary = detector.observe_position(PEER_ID, TARGET_POSITION)
	assert_true(trigger["requested"], "crossing an unexplored boundary starts generation")
	_emit_server_trace(sink, trigger["trace"])
	var emitted: Array = await generator.provisional_sector_ready
	var generation_result: Dictionary = emitted[1]
	for span: Dictionary in generation_result["trace_spans"]:
		_emit_server_trace(sink, span)

	var coordinator: CanonGenerationCoordinator = CanonGenerationCoordinatorScript.new()
	coordinator.set_canonicalize_callback(Callable(repository, "canonicalize_blueprint"))
	var commit_trace: Dictionary = JitTraceContextScript.child(
		generation_result["trace_context"],
		"canon_db_commit",
	)
	var finalization: Dictionary = coordinator.accept_generation_result(
		target_sector,
		generation_result["selected_profile"],
		generation_result
	)
	commit_trace["status"] = "OK" if finalization["outcome"] == CanonGenerationCoordinatorScript.OUTCOME_CANONICALIZED else "ERROR"
	_emit_server_trace(sink, commit_trace)
	assert_eq(finalization["outcome"], CanonGenerationCoordinatorScript.OUTCOME_CANONICALIZED)
	var committed_record: Dictionary = repository.get_canonical_sector(target_sector)["sector"]
	assert_eq(committed_record["blueprint"]["archetype"], SectorArchetypeAdmissionScript.PROFILE_POI_ANCHOR)
	var mutations: CanonMutationRepository = CanonMutationRepositoryScript.new(_store, repository)
	assert_eq(mutations.ensure_schema()["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var committed_revision: int = mutations.get_sector_revision(target_sector)["revision"]

	var network_client: Node = get_tree().root.get_node("NetworkClient")
	var ack_tracker: Object = JitPresentationAckTrackerScript.new()
	network_client._telemetry_queue.take_batch(Time.get_ticks_msec())
	_gameplay_root = Node3D.new()
	get_tree().root.add_child(_gameplay_root)
	get_tree().current_scene = _gameplay_root
	var presentation_trace: Dictionary = ack_tracker.issue(PEER_ID, commit_trace)
	network_client.receive_sector_blueprint(finalization["blueprint"], TARGET_POSITION, presentation_trace)
	await network_client.geometry_assembly_completed
	var presentation_batch: Array[Dictionary] = network_client._telemetry_queue.take_batch(Time.get_ticks_msec())
	assert_eq(presentation_batch.size(), 1, "successful render queues one presentation acknowledgement")
	var verified_presentation: Array[Dictionary] = ack_tracker.verified_events(PEER_ID, presentation_batch)
	var accepted: Array[Dictionary] = ingest.ingest_batch(
		PEER_ID,
		verified_presentation,
		"character-1043",
		int(Time.get_unix_time_from_system()),
		1043,
	)
	assert_eq(accepted.size(), 1, "the persisted client acknowledgement is accepted")
	var accepted_presentation: Dictionary = ack_tracker.confirm_accepted(PEER_ID, accepted)[0]
	assert_eq(accepted_presentation, presentation_trace, "only the accepted acknowledgement becomes causal context")
	detector.remember_canon_trace(target_sector, accepted_presentation)

	var rows_before_reentry: int = _canon_row_count()
	var reentry_trace: Array[Dictionary] = []
	detector.set_reload_callback(func(_peer_id: int, sector_id: String, position: Vector3, trace: Dictionary) -> void:
		if sector_id != target_sector:
			return
		reentry_trace.append(trace)
		_emit_server_trace(sink, trace)
		var canon: Dictionary = repository.get_canonical_sector(sector_id)
		network_client.receive_sector_blueprint(canon["sector"]["blueprint"], position, trace)
	)
	detector.observe_position(PEER_ID, TRANSIT_POSITION)
	var reentry: Dictionary = detector.observe_position(PEER_ID, TARGET_POSITION)
	assert_true(reentry["reloaded"], "returning resolves the existing Canon sector")
	await wait_physics_frames(2)
	var reentry_batch: Array[Dictionary] = network_client._telemetry_queue.take_batch(Time.get_ticks_msec())
	assert_eq(reentry_batch.size(), 1, "successful replay queues one re-entry event")
	assert_true(
		ack_tracker.verified_events(PEER_ID, reentry_batch).is_empty(),
		"client-authored re-entry is rejected because the server already emitted it",
	)

	var telemetry_rows: Dictionary = _store.query(
		"SELECT event_type, payload FROM events ORDER BY id ASC;"
	)
	var spans: Array[Dictionary] = []
	for row: Dictionary in telemetry_rows["rows"]:
		var payload: Dictionary = JSON.parse_string(row["payload"])
		payload["event_type"] = row["event_type"]
		spans.append(payload)

	assert_eq(_event_types(spans), EXPECTED_EVENTS, "production telemetry preserves exact causal order")
	assert_true(_one_trace(spans), "all six spans share one trace id")
	assert_true(_one_spatial_guid(spans), "all six spans carry one non-empty sector spatial GUID")
	assert_true(_valid_links(spans), "each span links to its immediate causal parent")
	assert_eq(reentry_trace.size(), 1, "Canon re-entry emits one linked trace")
	assert_eq(target_generation_calls[0], 1, "the target sector is generated exactly once")
	assert_eq(_canon_row_count(), rows_before_reentry, "re-entry writes no Canon rows")
	assert_eq(repository.get_canonical_sector(target_sector)["sector"], committed_record, "re-entry preserves Canon identity")
	assert_eq(mutations.get_sector_revision(target_sector)["revision"], committed_revision, "re-entry preserves Canon revision")
	assert_eq(
		JSON.stringify(repository.get_canonical_sector(target_sector)["sector"]["blueprint"]).sha1_text(),
		JSON.stringify(finalization["blueprint"]).sha1_text(),
		"re-entry presents the exact committed Canon blueprint",
	)


func test_unavailable_telemetry_does_not_block_canon_presentation_or_reentry() -> void:
	var outage_position: Vector3 = TARGET_POSITION
	var target_sector: String = SectorBoundaryDetectorScript.sector_id_for_position(outage_position)
	var repository: CanonRepository = CanonRepositoryScript.new(_store)
	assert_eq(repository.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var canonicalized: Dictionary = repository.canonicalize_blueprint(_blueprint(target_sector))
	assert_eq(canonicalized["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var committed_record: Dictionary = repository.get_canonical_sector(target_sector)["sector"]
	var rows_before_reentry: int = _canon_row_count()

	var unavailable_ingest: TelemetryIngestService = TelemetryIngestServiceScript.new(
		null,
		TelemetryRateLimiterScript.new(),
	)
	var outage_tracker: JitPresentationAckTracker = JitPresentationAckTrackerScript.new()
	var outage_root: Dictionary = JitTraceContextScript.root(PEER_ID, target_sector)
	var outage_commit: Dictionary = JitTraceContextScript.child(outage_root, "canon_db_commit")
	var outage_presentation: Dictionary = outage_tracker.issue(PEER_ID, outage_commit)
	var detector: SectorBoundaryDetector = SectorBoundaryDetectorScript.new()
	detector.remember_canon_trace(target_sector, outage_presentation)
	assert_true(unavailable_ingest.ingest_batch(PEER_ID, [{
		"event_type": "client_presentation_ack",
		"schema_version": 1,
		"payload": {},
	}], "character-1043", int(Time.get_unix_time_from_system()), 1043).is_empty())

	var network_client: Node = get_tree().root.get_node("NetworkClient")
	network_client._telemetry_queue.take_batch(Time.get_ticks_msec())
	_gameplay_root = Node3D.new()
	get_tree().root.add_child(_gameplay_root)
	get_tree().current_scene = _gameplay_root
	network_client.receive_sector_blueprint(canonicalized["sector"]["blueprint"], outage_position, {})
	await network_client.geometry_assembly_completed

	detector.set_canon_lookup(Callable(repository, "get_canonical_sector"))
	var reloads: Array[Dictionary] = []
	detector.set_reload_callback(func(_peer_id: int, sector_id: String, position: Vector3, trace: Dictionary) -> void:
		var canon: Dictionary = repository.get_canonical_sector(sector_id)
		reloads.append(canon["sector"])
		network_client.receive_sector_blueprint(canon["sector"]["blueprint"], position, trace)
	)
	var reentry: Dictionary = detector.observe_position(PEER_ID, outage_position)
	assert_true(reentry["reloaded"], "Canon reload proceeds while telemetry is unavailable")
	assert_eq(reentry["trace"]["trace_id"], outage_root["trace_id"], "telemetry outage preserves the original trace")
	assert_eq(reentry["trace"]["parent_span_id"], outage_presentation["span_id"], "re-entry links to server-issued presentation context")
	await wait_physics_frames(2)
	assert_eq(reloads, [committed_record], "the same Canon identity is presented")
	assert_eq(_canon_row_count(), rows_before_reentry, "telemetry failure causes no Canon rewrite")


func _emit_server_trace(sink: TelemetrySink, trace: Dictionary) -> void:
	var payload: Dictionary = trace.duplicate(true)
	var event_type: String = payload["event_type"]
	payload.erase("event_type")
	var envelope: Dictionary = TelemetryEventScript.build(
		event_type,
		1,
		int(Time.get_unix_time_from_system()),
		1043,
		PEER_ID,
		payload,
	)
	assert_eq(sink.emit(envelope)["outcome"], TelemetrySinkScript.OUTCOME_OK)


func _canon_row_count() -> int:
	var result: Dictionary = _store.query("SELECT COUNT(*) AS count FROM canon_sectors;")
	return int(result["rows"][0]["count"])


func _event_types(spans: Array[Dictionary]) -> Array[String]:
	var event_types: Array[String] = []
	for span: Dictionary in spans:
		event_types.append(String(span["event_type"]))
	return event_types


func _one_trace(spans: Array[Dictionary]) -> bool:
	if spans.is_empty():
		return false
	var trace_id: String = spans[0]["trace_id"]
	for span: Dictionary in spans:
		if span["trace_id"] != trace_id:
			return false
	return true


func _one_spatial_guid(spans: Array[Dictionary]) -> bool:
	if spans.is_empty():
		return false
	var spatial_guid: String = String(spans[0].get("spatial_guid", ""))
	if spatial_guid.is_empty():
		return false
	for span: Dictionary in spans:
		if String(span.get("spatial_guid", "")) != spatial_guid:
			return false
	return true


func _valid_links(spans: Array[Dictionary]) -> bool:
	if spans.is_empty() or spans[0]["parent_span_id"] != null:
		return false
	for index: int in range(1, spans.size()):
		if spans[index]["parent_span_id"] != spans[index - 1]["span_id"]:
			return false
	return true


func _blueprint(sector_id: String) -> Dictionary:
	return {
		"schema_version": 3,
		"sector_id": sector_id,
		"origin": {"x": 16, "y": 32},
		"tiles": [
			{"x": 16, "y": 32, "kind": "floor"},
			{"x": 17, "y": 32, "kind": "floor"},
		],
		"structures": [{
			"structure_id": "str_trace_1043",
			"kind": "well",
			"x": 16,
			"y": 32,
			"facing_degrees": 0,
		}],
	}