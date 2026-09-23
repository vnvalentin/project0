extends Node
class_name SectorBlueprintService
## Server-side async request seam for Slice 008: sends a sector-generation
## prompt to the local Ollama instance via the existing, unchanged
## LocalLLMClient, then validates the result against SectorBlueprintSchema.
## Server-only, per shared/local_llm_client.gd and AGENTS.md; the client never
## calls Ollama.
##
## Every request is assigned a correlation id and provenance (requested_at
## ticks, model, host) recorded in memory for the lifetime of this node, so a
## caller (or telemetry) can trace which request produced which outcome. This
## node adds no persistence, no retry policy beyond LocalLLMClient's own
## single bounded HTTPRequest timeout, no SQLite, and no world/geometry
## mutation — see docs/slices/008-sector-blueprint-contract.md for full scope
## and non-goals.
##
## Non-blocking by construction: request_sector_blueprint() is an async
## (coroutine) function that awaits LocalLLMClient's own await on
## HTTPRequest.request_completed. Godot's await suspends only the calling
## coroutine, not the SceneTree/multiplayer physics loop, so other nodes
## (including ServerPlayerState's per-peer _physics_process) keep ticking
## while a request is in flight.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const LocalLLMClientScript: Script = preload("res://shared/local_llm_client.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")

## Outcome codes for the request seam itself, distinct from
## SectorBlueprintSchema's validation outcome codes. A request can fail before
## validation ever runs (transport failure or timeout).
const REQUEST_OUTCOME_VALIDATED: String = "validated"
const REQUEST_OUTCOME_TRANSPORT_ERROR: String = "transport_error"
const REQUEST_OUTCOME_TIMEOUT: String = "timeout"
const SOURCE_LLM: String = "llm"
const SOURCE_FALLBACK: String = "fallback"

signal blueprint_request_completed(correlation_id: String, result: Dictionary)

@export var ollama_host: String = "http://127.0.0.1:11434"
@export var model_name: String = "llama3:latest"
@export var request_timeout_sec: float = 60.0

var _llm_client: Node
## Correlation id (String) -> provenance Dictionary. Kept only in memory for
## this node's lifetime; not persisted (no SQLite/Canon in this slice).
var _request_provenance: Dictionary = {}
var _next_sequence: int = 0


func _ready() -> void:
	_llm_client = LocalLLMClientScript.new()
	_llm_client.ollama_host = ollama_host
	_llm_client.model_name = model_name
	_llm_client.request_timeout_sec = request_timeout_sec
	# An unchanged export means "no explicit choice", so defer to the process
	# environment. Without this the containerized server points at its own
	# loopback and every sector request fails before validation.
	_llm_client.configure_from_env()
	add_child(_llm_client)


## Public seam. Sends `prompt` to the local Ollama instance and validates the
## parsed response as a sector blueprint. Returns (and emits via
## blueprint_request_completed) a Dictionary:
## {
##   "correlation_id": String,
##   "request_outcome": String,   # REQUEST_OUTCOME_*
##   "validation_outcome": String,# SectorBlueprintSchema.OUTCOME_* or "" if not reached
##   "detail": String,
##   "blueprint": Variant,        # validated Dictionary, or null
##   "provenance": Dictionary,
## }
## Never raises; every failure path is a structured, bounded result. This
## function is a coroutine (uses await) so callers must await it, but nothing
## it does blocks the SceneTree's own frame/physics processing while it is
## suspended.
func request_sector_blueprint(prompt: String, sector_id: String = "generic-sector") -> Dictionary:
	var correlation_id: String = _generate_correlation_id()
	var provenance: Dictionary = {
		"correlation_id": correlation_id,
		"requested_at_ticks_msec": Time.get_ticks_msec(),
		"model": model_name,
		"host": ollama_host,
	}
	_request_provenance[correlation_id] = provenance

	var llm_result: Dictionary = await _llm_client.generate_json(prompt)

	var result: Dictionary
	if not llm_result["success"]:
		var request_outcome: String = REQUEST_OUTCOME_TIMEOUT if _is_timeout(llm_result["error"]) else REQUEST_OUTCOME_TRANSPORT_ERROR
		result = _fallback_result(correlation_id, request_outcome, "", llm_result["error"], sector_id, provenance)
	else:
		var validation: Dictionary = SectorBlueprintSchemaScript.validate_generated(llm_result["data"])
		if validation["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID:
			var blueprint: Dictionary = _stamp_entity_guids(validation["blueprint"])
			result = {
				"correlation_id": correlation_id,
				"request_outcome": REQUEST_OUTCOME_VALIDATED,
				"validation_outcome": validation["outcome"],
				"detail": validation["detail"],
				"source": SOURCE_LLM,
				"fallback_selected": false,
				"blueprint": blueprint,
				"provenance": provenance,
			}
		else:
			result = _fallback_result(correlation_id, REQUEST_OUTCOME_VALIDATED, validation["outcome"], "Generated blueprint rejected by schema gate.", sector_id, provenance)

	blueprint_request_completed.emit(correlation_id, result)
	return result


## Public seam for telemetry/tests: returns the provenance recorded for a
## given correlation id, or an empty Dictionary if unknown.
func get_provenance(correlation_id: String) -> Dictionary:
	return _request_provenance.get(correlation_id, {})


func _is_timeout(error_text: String) -> bool:
	# LocalLLMClient reports Godot's own HTTPRequest timeout as a non-OK
	# result code inside its "HTTP request failed (result=...)" message
	# (RESULT_TIMEOUT); no separate timeout signal exists on HTTPRequest, so
	# this string check is the only seam available without modifying the
	# preserved, unchanged LocalLLMClient. See shared/local_llm_client.gd.
	return error_text.findn("result=%d" % HTTPRequest.RESULT_TIMEOUT) != -1


func _generate_correlation_id() -> String:
	_next_sequence += 1
	return "sector-blueprint-%d-%d-%d" % [Time.get_ticks_usec(), OS.get_process_id(), _next_sequence]


func _fallback_result(correlation_id: String, request_outcome: String, validation_outcome: String, detail: String, sector_id: String, provenance: Dictionary) -> Dictionary:
	return {
		"correlation_id": correlation_id,
		"request_outcome": request_outcome,
		"validation_outcome": validation_outcome,
		"detail": detail,
		"source": SOURCE_FALLBACK,
		"fallback_selected": true,
		"blueprint": _generic_fallback(sector_id),
		"provenance": provenance,
	}


func _generic_fallback(sector_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"sector_id": sector_id if not sector_id.is_empty() else "generic-sector",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}


func _stamp_entity_guids(blueprint: Dictionary) -> Dictionary:
	var stamped: Dictionary = blueprint.duplicate(true)
	var sector_id: String = stamped["sector_id"]
	_stamp_entries(stamped, "structures", "structure_id", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, sector_id)
	_stamp_entries(stamped, "spawn_points", "spawn_id", CanonEntityGuidScript.ENTITY_CLASS_SPAWN_POINT, sector_id)
	return stamped


func _stamp_entries(blueprint: Dictionary, array_field: String, id_field: String, entity_class: String, sector_id: String) -> void:
	if not (blueprint.get(array_field) is Array):
		return
	for entry: Dictionary in blueprint[array_field]:
		entry["entity_guid"] = CanonEntityGuidScript.derive_rfc4122_v5(sector_id, entity_class, entry[id_field])
