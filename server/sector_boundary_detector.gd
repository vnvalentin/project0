extends RefCounted
class_name SectorBoundaryDetector
## Slice 046: maps authoritative world positions to sectors and requests unseen
## sectors. This seam owns no database handle and performs no async work.

const WorldScaleScript: Script = preload("res://shared/world_scale.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const MAX_RETAINED_CANON_TRACES: int = 256

signal sector_generation_requested(peer_id: int, sector_id: String, position: Vector3)

var _last_sector_by_peer: Dictionary = {}
var _prepared_by_peer: Dictionary = {}
var _trace_by_sector: Dictionary = {}
var _canon_lookup: Callable = Callable()
var _request_callback: Callable = Callable()
var _reload_callback: Callable = Callable()


## Injects a server-owned lookup. It must accept sector_id and return either a
## Dictionary with outcome == CanonRepository.OUTCOME_OK or a boolean.
func set_canon_lookup(lookup: Callable) -> void:
	_canon_lookup = lookup


## Injects the asynchronous generation acceptance callback. Trace-aware
## callbacks receive (peer_id, sector_id, position, trace); legacy callbacks
## may retain the original three arguments. The callback must return immediately.
func set_request_callback(callback: Callable) -> void:
	_request_callback = callback


## Injects the synchronous Canon re-entry callback, with the same optional
## fourth trace argument as the generation callback.
func set_reload_callback(callback: Callable) -> void:
	_reload_callback = callback


## Observes one authoritative position. Reports whether generation was
## requested or existing Canon was reloaded for the entering peer.
func observe_position(peer_id: int, position: Vector3) -> Dictionary:
	var sector_id: String = sector_id_for_position(position)
	if _last_sector_by_peer.get(peer_id, "") == sector_id:
		return {"sector_id": sector_id, "requested": false, "reloaded": false}
	_last_sector_by_peer[peer_id] = sector_id
	return _prepare_sector(peer_id, sector_id, position)


func commit_position(peer_id: int, position: Vector3) -> void:
	_last_sector_by_peer[peer_id] = sector_id_for_position(position)


func prepare_position(peer_id: int, position: Vector3) -> Dictionary:
	var sector_id: String = sector_id_for_position(position)
	var prepared: Dictionary = _prepared_by_peer.get(peer_id, {})
	if prepared.has(sector_id):
		return {"sector_id": sector_id, "requested": false, "reloaded": false}
	if prepared.size() >= 16:
		prepared.erase(prepared.keys()[0])
	prepared[sector_id] = true
	_prepared_by_peer[peer_id] = prepared
	return _prepare_sector(peer_id, sector_id, position)


func forget_preparation(peer_id: int, sector_id: String) -> void:
	var prepared: Dictionary = _prepared_by_peer.get(peer_id, {})
	prepared.erase(sector_id)


func _prepare_sector(peer_id: int, sector_id: String, position: Vector3) -> Dictionary:

	if _has_canon(sector_id):
		var retained_trace: Dictionary = _trace_by_sector.get(sector_id, {})
		var reload_trace: Dictionary = (
			JitTraceContextScript.child(retained_trace, "canon_reentry")
			if not retained_trace.is_empty()
			else JitTraceContextScript.root(peer_id, sector_id)
		)
		reload_trace["event_type"] = "canon_reentry"
		if _reload_callback.is_valid():
			_call_transition_callback(_reload_callback, peer_id, sector_id, position, reload_trace)
		return {"sector_id": sector_id, "requested": false, "reloaded": true, "trace": reload_trace}

	var root_trace: Dictionary = JitTraceContextScript.root(peer_id, sector_id)
	sector_generation_requested.emit(peer_id, sector_id, position)
	if _request_callback.is_valid():
		_call_transition_callback(_request_callback, peer_id, sector_id, position, root_trace)
	return {"sector_id": sector_id, "requested": true, "reloaded": false, "trace": root_trace}


## Retains only the terminal bounded context needed to link a later Canon
## re-entry. Canon data and trace metadata remain separate.
func remember_canon_trace(sector_id: String, trace: Dictionary) -> void:
	if sector_id.is_empty() or String(trace.get("trace_id", "")).is_empty():
		return
	if not _trace_by_sector.has(sector_id) and _trace_by_sector.size() >= MAX_RETAINED_CANON_TRACES:
		_trace_by_sector.erase(_trace_by_sector.keys()[0])
	_trace_by_sector[sector_id] = trace.duplicate(true)


## Clears a disconnected peer's transition state so a future connection with
## the same peer id is evaluated from its new authoritative position.
func forget_peer(peer_id: int) -> void:
	_last_sector_by_peer.erase(peer_id)
	_prepared_by_peer.erase(peer_id)


## Public pure mapping seam. X is the world east/west axis and Z is the
## north/south axis; Y does not affect sector membership.
static func sector_id_for_position(position: Vector3) -> String:
	var edge: float = WorldScaleScript.SECTOR_EDGE_UNITS
	var sector_x: int = floori(position.x / edge)
	var sector_z: int = floori(position.z / edge)
	return "sector-%d-%d" % [sector_x, sector_z]


func _has_canon(sector_id: String) -> bool:
	if not _canon_lookup.is_valid():
		return false
	var result: Variant = _canon_lookup.call(sector_id)
	if result is bool:
		return result
	if result is Dictionary:
		return result.get("outcome", "") == "ok"
	return false


func _call_transition_callback(
	callback: Callable,
	peer_id: int,
	sector_id: String,
	position: Vector3,
	trace: Dictionary,
) -> void:
	if callback.get_argument_count() >= 4:
		callback.call(peer_id, sector_id, position, trace)
	else:
		callback.call(peer_id, sector_id, position)