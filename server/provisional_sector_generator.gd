extends Node
class_name ProvisionalSectorGenerator
## Server-side public seam for Slice 009: accepts a sector-generation request
## keyed by sector id, drives the Slice 008
## SectorBlueprintService, and exposes an in-memory provisional
## result/outcome. See docs/slices/009-provisional-sector-generation.md.
##
## Acceptance is synchronous: request_provisional_sector() records a
## "pending" entry and returns its correlation id without the caller
## awaiting generation. The actual SectorBlueprintService request runs in a
## deferred coroutine, so this node's own call stack never blocks on
## HTTPRequest/Ollama round-trip time, and the SceneTree/multiplayer loop
## (e.g. ServerPlayerState._physics_process) keeps ticking while a request is
## in flight — the same non-blocking property Slice 008 already proved for
## the underlying service.
##
## Explicit non-goals (see .scratch/game-vision/issues/16-provisional-sector-generation.md):
## no geometry generation, no SQLite, no Canon persistence, no sector-boundary
## detection, no quests, zero LLM retries,
## and no client-side Ollama calls. Results live only in _sector_state for
## this node's lifetime and are lost on process exit.
##
## Each request gets its own short-lived SectorBlueprintService instance
## (created and freed per request) rather than one shared instance, because
## SectorBlueprintService's single child HTTPRequest node can only run one
## request at a time; sharing one instance would make concurrent requests for
## different sector ids fail with "HTTPRequest is processing a request."

const SectorBlueprintServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const SectorArchetypeAdmissionScript: Script = preload("res://server/sector_archetype_admission.gd")

## In-memory request lifecycle. There is no "failed" status distinct from
## "ready": a bounded failure is itself a ready outcome (see
## SectorBlueprintService's REQUEST_OUTCOME_* / validation_outcome), so callers
## always resolve to either "unknown", "pending", or "ready".
const STATUS_UNKNOWN: String = "unknown"
const STATUS_PENDING: String = "pending"
const STATUS_READY: String = "ready"

signal provisional_sector_ready(sector_id: String, result: Dictionary)

## Passed through to the underlying SectorBlueprintService. Must be set
## before this node enters the tree (e.g. immediately after .new()), since
## SectorBlueprintService copies these into its own child LocalLLMClient
## during its _ready().
@export var ollama_host: String = "http://127.0.0.1:11434"
@export var model_name: String = "llama3:latest"
@export var request_timeout_sec: float = 60.0

## sector_id (String) -> Dictionary {"status": String, "correlation_id": String, "result": Variant}
## "correlation_id" is this seam's own id, handed back synchronously by
## request_provisional_sector() at acceptance time, and stays stable for the
## life of the entry. "result" is null while status == STATUS_PENDING, and
## the SectorBlueprintService result Dictionary once status == STATUS_READY
## (that Dictionary carries a separate, service-level "correlation_id" of its
## own, used only for provenance against SectorBlueprintService.get_provenance()).
## In-memory only for this node's lifetime; no persistence.
var _sector_state: Dictionary = {}
var clock_usec: Callable = Callable()


func _now_usec() -> int:
	return int(clock_usec.call()) if clock_usec.is_valid() else Time.get_ticks_usec()


## Public seam. Accepts a request to provisionally generate `sector_id` from
## `prompt`. Returns the assigned correlation id immediately; the caller does
## not need to await this function to receive acceptance. Re-requesting a
## sector id that is already pending or ready returns its existing state
## instead of starting a second concurrent request for the same sector id.
func request_provisional_sector(sector_id: String, prompt: String, selected_profile_or_trace: Variant = SectorArchetypeAdmissionScript.PROFILE_WILDERNESS, trace: Dictionary = {}) -> String:
	var selected_profile: String = SectorArchetypeAdmissionScript.PROFILE_WILDERNESS
	if selected_profile_or_trace is Dictionary:
		trace = selected_profile_or_trace
	else:
		selected_profile = String(selected_profile_or_trace)
	if not SectorArchetypeAdmissionScript._supported_profiles().has(selected_profile):
		return ""
	if _sector_state.has(sector_id):
		return _sector_state[sector_id]["correlation_id"]

	var correlation_id: String = "provisional-%s-%d" % [sector_id, Time.get_ticks_usec()]
	_sector_state[sector_id] = {
		"status": STATUS_PENDING,
		"correlation_id": correlation_id,
		"selected_profile": selected_profile,
		"result": null,
		"trace": trace.duplicate(true),
		"generation_started_usec": int(trace.get("generation_started_usec", _now_usec())),
	}

	_run_request.call_deferred(sector_id, prompt)
	return correlation_id


## Public seam: current lifecycle status for a sector id, or STATUS_UNKNOWN if
## no request has ever been made for it.
func get_status(sector_id: String) -> String:
	if not _sector_state.has(sector_id):
		return STATUS_UNKNOWN
	return _sector_state[sector_id]["status"]


## Public seam: this seam's own correlation id for a sector id (the same id
## returned by request_provisional_sector()), or an empty String if the
## sector id is unknown.
func get_correlation_id(sector_id: String) -> String:
	if not _sector_state.has(sector_id):
		return ""
	return _sector_state[sector_id]["correlation_id"]


## Public seam: the in-memory provisional result for a sector id, or an empty
## Dictionary if the sector id is unknown or still pending. Never blocks. The
## returned Dictionary is SectorBlueprintService's own result shape (see
## server/sector_blueprint_service.gd); use get_correlation_id() for this
## seam's own request-acceptance id rather than the nested
## result["correlation_id"], which is SectorBlueprintService's internal id.
func get_provisional_result(sector_id: String) -> Dictionary:
	if not _sector_state.has(sector_id):
		return {}
	if _sector_state[sector_id]["status"] != STATUS_READY:
		return {}
	return _sector_state[sector_id]["result"]


func _run_request(sector_id: String, prompt: String) -> void:
	var started_usec: int = _sector_state[sector_id]["generation_started_usec"]
	var blueprint_service: Node = SectorBlueprintServiceScript.new()
	blueprint_service.ollama_host = ollama_host
	blueprint_service.model_name = model_name
	blueprint_service.request_timeout_sec = request_timeout_sec
	blueprint_service.clock_usec = clock_usec
	add_child(blueprint_service)

	var result: Dictionary = await blueprint_service.request_sector_blueprint(prompt, sector_id, started_usec)
	var trace: Dictionary = _sector_state[sector_id].get("trace", {})
	if not trace.is_empty():
		var generation_span: Dictionary = JitTraceContextScript.child(trace, "llm_generation_latency")
		generation_span["duration_ms"] = result["timing"]["generation_duration_ms"]
		generation_span["status"] = "OK" if result.get("request_outcome", "") == "validated" else "ERROR"
		var validation_span: Dictionary = JitTraceContextScript.child(generation_span, "schema_validation_result")
		validation_span["duration_ms"] = result["timing"]["validation_duration_ms"]
		validation_span["status"] = "OK" if result.get("candidate_validation_outcome", result.get("validation_outcome", "")) == "valid" else "ERROR"
		result["trace_spans"] = [generation_span, validation_span]
		result["trace_context"] = validation_span

	blueprint_service.queue_free()

	# Preserve the correlation id handed back at acceptance time rather than
	# overwriting it with SectorBlueprintService's own internal id.
	var correlation_id: String = _sector_state[sector_id]["correlation_id"]
	result["selected_profile"] = _sector_state[sector_id]["selected_profile"]
	_sector_state[sector_id] = {
		"status": STATUS_READY,
		"correlation_id": correlation_id,
		"selected_profile": _sector_state[sector_id]["selected_profile"],
		"result": result,
		"trace": trace,
	}
	provisional_sector_ready.emit(sector_id, result)
