extends RefCounted
class_name JitPresentationAckTracker

const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const MAX_PENDING_PER_PEER: int = 16
const SERVER_AUTHORED_EVENTS: Array[String] = [
	"player_trigger_event",
	"llm_generation_latency",
	"schema_validation_result",
	"canon_db_commit",
	"canon_reentry",
]

var _pending_by_peer: Dictionary = {}


func issue(peer_id: int, commit_trace: Dictionary) -> Dictionary:
	if peer_id <= 0 or commit_trace.is_empty():
		return {}
	var trace: Dictionary = JitTraceContextScript.child(commit_trace, "client_presentation_ack")
	var pending: Dictionary = _pending_by_peer.get(peer_id, {})
	var sector_id: String = String(trace.get("sector_id", ""))
	if not pending.has(sector_id) and pending.size() >= MAX_PENDING_PER_PEER:
		pending.erase(pending.keys()[0])
	pending[sector_id] = trace.duplicate(true)
	_pending_by_peer[peer_id] = pending
	return trace


func match_pending(peer_id: int, raw_event: Dictionary) -> Dictionary:
	if String(raw_event.get("event_type", "")) != "client_presentation_ack":
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