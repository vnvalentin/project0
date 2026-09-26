extends RefCounted
class_name JitPresentationAckTracker

const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")
const MAX_PENDING_PER_PEER: int = 16
const SERVER_AUTHORED_EVENTS: Array[String] = [
	"player_trigger_event",
	"llm_generation_latency",
	"schema_validation_result",
	"canon_db_commit",
	"canon_reentry",
]

var _pending_by_peer: Dictionary = {}
var _binding_by_peer: Dictionary = {}
var _ready_by_peer: Dictionary = {}


func issue(peer_id: int, commit_trace: Dictionary, binding: Dictionary = {}) -> Dictionary:
	if peer_id <= 0 or commit_trace.is_empty():
		return {}
	var trace: Dictionary = JitTraceContextScript.child(commit_trace, "client_presentation_ack")
	var pending: Dictionary = _pending_by_peer.get(peer_id, {})
	var sector_id: String = String(trace.get("sector_id", ""))
	if not pending.has(sector_id) and pending.size() >= MAX_PENDING_PER_PEER:
		forget_presentation(peer_id, String(pending.keys()[0]))
	var bindings: Dictionary = _binding_by_peer.get(peer_id, {})
	bindings[sector_id] = binding.duplicate(true)
	_binding_by_peer[peer_id] = bindings
	var ready: Dictionary = _ready_by_peer.get(peer_id, {})
	ready.erase(sector_id)
	pending[sector_id] = trace.duplicate(true)
	_pending_by_peer[peer_id] = pending
	return trace


func match_pending(peer_id: int, raw_event: Dictionary) -> Dictionary:
	if not _valid_ack(raw_event):
		return {}
	var payload: Variant = raw_event.get("payload")
	if not (payload is Dictionary):
		return {}
	var sector_id: String = String((payload as Dictionary).get("sector_id", ""))
	var pending: Dictionary = _pending_by_peer.get(peer_id, {})
	var expected: Dictionary = pending.get(sector_id, {})
	if expected.is_empty() or not _matches(expected, payload as Dictionary):
		return {}
	return expected.duplicate(true)


func is_ready(peer_id: int, sector_id: String, binding: Dictionary) -> bool:
	var ready: Dictionary = _ready_by_peer.get(peer_id, {})
	return not binding.is_empty() and ready.get(sector_id, {}) == binding


func has_presentation(peer_id: int, sector_id: String, binding: Dictionary) -> bool:
	var pending: Dictionary = _pending_by_peer.get(peer_id, {})
	var bindings: Dictionary = _binding_by_peer.get(peer_id, {})
	return is_ready(peer_id, sector_id, binding) or (pending.has(sector_id) and not binding.is_empty() and bindings.get(sector_id, {}) == binding)


func pending_trace(peer_id: int, sector_id: String, binding: Dictionary) -> Dictionary:
	var bindings: Dictionary = _binding_by_peer.get(peer_id, {})
	if binding.is_empty() or bindings.get(sector_id, {}) != binding:
		return {}
	var pending: Dictionary = _pending_by_peer.get(peer_id, {})
	return pending.get(sector_id, {}).duplicate(true)


func confirm_ready(peer_id: int, event: Dictionary, binding: Dictionary) -> Dictionary:
	var trace: Dictionary = match_pending(peer_id, event)
	var sector_id: String = String(trace.get("sector_id", ""))
	var bindings: Dictionary = _binding_by_peer.get(peer_id, {})
	if binding.is_empty() or bindings.get(sector_id, {}) != binding:
		return {}
	var confirmed: Dictionary = confirm_persisted(peer_id, trace)
	if confirmed.is_empty():
		return {}
	bindings.erase(sector_id)
	var ready: Dictionary = _ready_by_peer.get(peer_id, {})
	if not ready.has(sector_id) and ready.size() >= MAX_PENDING_PER_PEER:
		ready.erase(ready.keys()[0])
	ready[sector_id] = binding.duplicate(true)
	_ready_by_peer[peer_id] = ready
	return confirmed


func forget_presentation(peer_id: int, sector_id: String) -> void:
	for collection: Dictionary in [_pending_by_peer, _binding_by_peer, _ready_by_peer]:
		var sectors: Dictionary = collection.get(peer_id, {})
		sectors.erase(sector_id)


func confirm_persisted(peer_id: int, trace: Dictionary) -> Dictionary:
	var sector_id: String = String(trace.get("sector_id", ""))
	var pending: Dictionary = _pending_by_peer.get(peer_id, {})
	var expected: Dictionary = pending.get(sector_id, {})
	if expected.is_empty() or expected != trace:
		return {}
	pending.erase(sector_id)
	if pending.is_empty():
		_pending_by_peer.erase(peer_id)
	else:
		_pending_by_peer[peer_id] = pending
	return expected.duplicate(true)


func verified_events(peer_id: int, events: Array) -> Array[Dictionary]:
	var verified: Array[Dictionary] = []
	for raw_event: Variant in events:
		if not (raw_event is Dictionary):
			continue
		var event: Dictionary = raw_event as Dictionary
		var event_type: String = String(event.get("event_type", ""))
		if event_type in SERVER_AUTHORED_EVENTS:
			continue
		if event_type != "client_presentation_ack":
			verified.append(event)
			continue
		var expected: Dictionary = match_pending(peer_id, event)
		if not expected.is_empty():
			verified.append(_raw_event(expected))
	return verified


func confirm_accepted(peer_id: int, accepted_events: Array[Dictionary]) -> Array[Dictionary]:
	var confirmed: Array[Dictionary] = []
	for event: Dictionary in accepted_events:
		var matched: Dictionary = match_pending(peer_id, event)
		var trace: Dictionary = confirm_persisted(peer_id, matched)
		if not trace.is_empty():
			confirmed.append(trace)
	return confirmed


func forget_peer(peer_id: int) -> void:
	_pending_by_peer.erase(peer_id)
	_binding_by_peer.erase(peer_id)
	_ready_by_peer.erase(peer_id)


func _valid_ack(event: Dictionary) -> bool:
	if event.get("event_type") != "client_presentation_ack" or not (event.get("schema_version") is int) or event.get("schema_version") != 1:
		return false
	if not (event.get("payload") is Dictionary):
		return false
	var payload: Dictionary = event["payload"]
	if payload.size() != 8:
		return false
	for field: String in ["trace_id", "span_id", "parent_span_id", "sector_id", "spatial_guid", "status"]:
		if not (payload.get(field) is String) or String(payload[field]).is_empty():
			return false
	if not (payload.get("timestamp_ms") is int) or int(payload["timestamp_ms"]) < 0:
		return false
	var duration: Variant = payload.get("duration_ms")
	if not (duration is float or duration is int) or not is_finite(float(duration)) or float(duration) < 0.0:
		return false
	return TelemetryEventScript.validate(TelemetryEventScript.build("client_presentation_ack", 1, 0, 0, 0, payload))["outcome"] == TelemetryEventScript.OUTCOME_ACCEPTED


func _matches(expected: Dictionary, payload: Dictionary) -> bool:
	for field: String in ["trace_id", "span_id", "parent_span_id", "sector_id", "spatial_guid", "timestamp_ms", "status"]:
		if payload.get(field) != expected.get(field):
			return false
	return true


func _raw_event(trace: Dictionary) -> Dictionary:
	var payload: Dictionary = trace.duplicate(true)
	payload.erase("event_type")
	return {
		"event_type": "client_presentation_ack",
		"schema_version": 1,
		"payload": payload,
	}