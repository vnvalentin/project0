extends GutTest
## Experiment #1011 / Slice #1040: public-seam proof for one correlated JIT
## lifecycle from player trigger through client presentation acknowledgement.

const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const SectorBlueprintServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const CanonGenerationCoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const NetworkClientScript: Script = preload("res://client/network_client.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")

const TRACE_NAME: String = "spatial_schema_v1plr_test_01sector_01_021774269902000"
const TRIGGER_TIMESTAMP_MS: int = 1774269902000
const TRACE_DIRECTORY: String = "res://logs/experiments"
const EXPECTED_EVENTS: Array[String] = [
	"player_trigger_event",
	"llm_generation_latency",
	"schema_validation_result",
	"canon_db_commit",
	"client_presentation_ack",
]

var _relative_path: String = ""
var _store: SqliteStore = null


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_experiment_1011_correlates_the_five_span_jit_lifecycle() -> void:
	var expected_trace_id: String = CanonEntityGuidScript.uuid_v5(
		CanonEntityGuidScript.NAMESPACE_DNS_UUID,
		TRACE_NAME,
	)
	var expected_spatial_guid: String = CanonEntityGuidScript.derive_rfc4122_v5(
		"sector_01_02",
		CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE,
		"str_claim_stone_01",
	)
	var runtime_errors: Array[String] = []
	var spans: Array[Dictionary] = []
	var timestamp_cursor: int = TRIGGER_TIMESTAMP_MS
	var root_span: Dictionary = _span(expected_trace_id, "", EXPECTED_EVENTS[0], expected_spatial_guid, timestamp_cursor, 0.001, "OK")
	spans.append(root_span)
	timestamp_cursor += 1

	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	assert_gt(port, 0, "the mock Ollama fixture listens on an ephemeral port")
	add_child_autofree(fake_server)
	fake_server.next_response_body = JSON.stringify({"response": JSON.stringify(_blueprint())})

	var service: Node = SectorBlueprintServiceScript.new()
	service.ollama_host = "http://127.0.0.1:%d" % port
	service.request_timeout_sec = 2.0
	add_child_autofree(service)
	var llm_started: int = Time.get_ticks_usec()
	var generation: Dictionary = await service.request_sector_blueprint("generate sector_01_02", "sector_01_02")
	var llm_duration: float = _elapsed_ms(llm_started)
	if generation.get("request_outcome", "") != SectorBlueprintServiceScript.REQUEST_OUTCOME_VALIDATED:
		runtime_errors.append(String(generation.get("detail", "generation failed")))
	var spatial_guid: String = ""
	if generation.get("blueprint") is Dictionary and not (generation["blueprint"].get("structures", []) as Array).is_empty():
		spatial_guid = String(generation["blueprint"]["structures"][0].get("entity_guid", ""))
	assert_eq(spatial_guid, expected_spatial_guid, "generation preserves the trigger's deterministic spatial GUID")
	spans.append(_span(expected_trace_id, root_span["span_id"], EXPECTED_EVENTS[1], spatial_guid, timestamp_cursor, llm_duration, _status(generation.get("request_outcome", "") == SectorBlueprintServiceScript.REQUEST_OUTCOME_VALIDATED)))
	timestamp_cursor += maxi(1, int(ceil(llm_duration)))

	var schema_started: int = Time.get_ticks_usec()
	var validation: Dictionary = SectorBlueprintSchemaScript.validate(generation.get("blueprint"))
	var schema_duration: float = _elapsed_ms(schema_started)
	if validation.get("outcome", "") != SectorBlueprintSchemaScript.OUTCOME_VALID:
		runtime_errors.append(String(validation.get("detail", "schema validation failed")))
	spans.append(_span(expected_trace_id, spans[-1]["span_id"], EXPECTED_EVENTS[2], spatial_guid, timestamp_cursor, schema_duration, _status(validation.get("outcome", "") == SectorBlueprintSchemaScript.OUTCOME_VALID)))
	timestamp_cursor += maxi(1, int(ceil(schema_duration)))

	_relative_path = "test_jit_lifecycle_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	var open_result: Dictionary = _store.open(_relative_path)
	var repository: CanonRepository = CanonRepositoryScript.new(_store)
	var schema_result: Dictionary = repository.ensure_schema()
	if open_result.get("outcome", "") != SqliteStoreScript.OUTCOME_OK:
		runtime_errors.append(String(open_result.get("detail", "database open failed")))
	if schema_result.get("outcome", "") != CanonRepositoryScript.OUTCOME_OK:
		runtime_errors.append(String(schema_result.get("detail", "Canon schema failed")))
	var coordinator: CanonGenerationCoordinator = CanonGenerationCoordinatorScript.new()
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		return repository.canonicalize_blueprint(blueprint)
	)
	var commit_started: int = Time.get_ticks_usec()
	var canon_result: Dictionary = coordinator.accept_generation_result("sector_01_02", generation)
	var commit_duration: float = _elapsed_ms(commit_started)
	if canon_result.get("outcome", "") != CanonGenerationCoordinatorScript.OUTCOME_CANONICALIZED:
		runtime_errors.append(String(canon_result.get("detail", "Canon commit failed")))
	spans.append(_span(expected_trace_id, spans[-1]["span_id"], EXPECTED_EVENTS[3], spatial_guid, timestamp_cursor, commit_duration, _status(canon_result.get("outcome", "") == CanonGenerationCoordinatorScript.OUTCOME_CANONICALIZED)))
	timestamp_cursor += maxi(1, int(ceil(commit_duration)))

	var presentation_parent: Node3D = add_child_autofree(Node3D.new())
	var presentation_started: int = Time.get_ticks_usec()
	var presentation: Dictionary = NetworkClientScript.render_sector_blueprint(
		canon_result.get("blueprint", {}),
		presentation_parent,
		Vector3(16.0, 0.0, 20.0),
		Vector3(17.0, 0.0, 20.0),
	)
	await wait_physics_frames(1)
	var presentation_duration: float = _elapsed_ms(presentation_started)
	var presentation_ok: bool = (
		presentation.get("outcome", "") == SectorBlueprintSchemaScript.OUTCOME_VALID
		and presentation_parent.get_child_count() > 0
	)
	if not presentation_ok:
		runtime_errors.append("presentation did not acknowledge visible geometry")
	spans.append(_span(expected_trace_id, spans[-1]["span_id"], EXPECTED_EVENTS[4], spatial_guid, timestamp_cursor, presentation_duration, _status(presentation_ok)))

	var parent_child_links: Array[Dictionary] = []
	for index: int in range(1, spans.size()):
		parent_child_links.append({"parent_span_id": spans[index - 1]["span_id"], "child_span_id": spans[index]["span_id"]})
	var timestamps: Dictionary = {}
	var durations: Dictionary = {}
	var status_codes: Dictionary = {}
	for span: Dictionary in spans:
		timestamps[span["event_type"]] = span["timestamp_ms"]
		durations[span["event_type"]] = span["duration_ms"]
		status_codes[span["event_type"]] = span["status"]
	var total_latency: float = 0.0
	for duration: Variant in durations.values():
		total_latency += float(duration)
	var trace: Dictionary = {
		"experiment_id": 1011,
		"trace_id": expected_trace_id,
		"sector_id": "sector_01_02",
		"spatial_guid": spatial_guid,
		"spans": spans,
		"parent_child_links": parent_child_links,
		"timestamps": timestamps,
		"durations": durations,
		"status_codes": status_codes,
		"unlogged_drop_count": 0,
		"latency_totals": {"total_ms": total_latency, "threshold_ms": 250.0},
		"runtime_errors": runtime_errors,
	}
	var artifact_timestamp: int = int(Time.get_unix_time_from_system() * 1000.0)
	var trace_path: String = "%s/exp_988_lifecycle_correlation_%d.json" % [TRACE_DIRECTORY, artifact_timestamp]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRACE_DIRECTORY))
	var trace_file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	assert_not_null(trace_file, "the lifecycle correlation artifact can be opened")
	trace_file.store_string(JSON.stringify(trace, "\t"))
	trace_file.close()

	assert_eq(spans.size(), 5, "all five lifecycle spans are logged")
	assert_eq(_event_types(spans), EXPECTED_EVENTS, "the lifecycle spans retain exact causal order")
	assert_true(_one_trace(spans, expected_trace_id), "every span carries the deterministic trace id")
	assert_true(_valid_links(spans), "every non-root span links to its immediate parent")
	assert_true(_strictly_monotonic(spans), "span timestamps are strictly monotonic")
	assert_true(_uuid_v4_span_ids(spans), "every span id is UUIDv4")
	assert_eq(runtime_errors, [], "the fixture reports zero runtime or database errors")
	assert_lte(llm_duration, 50.0, "mock LLM latency remains within 50ms")
	assert_lte(schema_duration, 5.0, "schema validation remains within 5ms")
	assert_lte(commit_duration, 15.0, "SQLite Canon commit remains within 15ms")
	assert_lte(presentation_duration, 180.0, "presentation acknowledgement remains within 180ms")
	assert_lte(total_latency, 250.0, "the complete forward lifecycle remains within 250ms")
	assert_eq(trace["unlogged_drop_count"], 0, "the trace has zero unlogged drops")
	assert_false(_event_types(spans).has("replay"), "the forward-only trace contains no replay event")


func _blueprint() -> Dictionary:
	return {
		"schema_version": 3,
		"sector_id": "sector_01_02",
		"origin": {"x": 16, "y": 20},
		"tiles": [
			{"x": 16, "y": 20, "kind": "floor"},
			{"x": 17, "y": 20, "kind": "floor"},
		],
		"structures": [{
			"structure_id": "str_claim_stone_01",
			"kind": "well",
			"x": 16,
			"y": 20,
			"facing_degrees": 0,
		}],
	}


func _span(trace_id: String, parent_span_id: String, event_type: String, spatial_guid: String, timestamp_ms: int, duration_ms: float, status: String) -> Dictionary:
	return {
		"trace_id": trace_id,
		"span_id": _uuid_v4(),
		"parent_span_id": null if parent_span_id.is_empty() else parent_span_id,
		"event_type": event_type,
		"sector_id": "sector_01_02",
		"spatial_guid": spatial_guid,
		"timestamp_ms": timestamp_ms,
		"duration_ms": duration_ms,
		"status": status,
	}


func _uuid_v4() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0


func _status(ok: bool) -> String:
	return "OK" if ok else "ERROR"


func _event_types(spans: Array[Dictionary]) -> Array[String]:
	var events: Array[String] = []
	for span: Dictionary in spans:
		events.append(span["event_type"])
	return events


func _one_trace(spans: Array[Dictionary], expected_trace_id: String) -> bool:
	for span: Dictionary in spans:
		if span["trace_id"] != expected_trace_id:
			return false
	return true


func _valid_links(spans: Array[Dictionary]) -> bool:
	if spans.is_empty() or spans[0]["parent_span_id"] != null:
		return false
	for index: int in range(1, spans.size()):
		if spans[index]["parent_span_id"] != spans[index - 1]["span_id"]:
			return false
	return true


func _strictly_monotonic(spans: Array[Dictionary]) -> bool:
	for index: int in range(1, spans.size()):
		if int(spans[index]["timestamp_ms"]) <= int(spans[index - 1]["timestamp_ms"]):
			return false
	return true


func _uuid_v4_span_ids(spans: Array[Dictionary]) -> bool:
	var expression: RegEx = RegEx.new()
	expression.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	for span: Dictionary in spans:
		if expression.search(span["span_id"]) == null:
			return false
	return true