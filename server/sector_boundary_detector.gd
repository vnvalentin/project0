extends RefCounted
class_name SectorBoundaryDetector
## Slice 046: maps authoritative world positions to sectors and requests unseen
## sectors. This seam owns no database handle and performs no async work.

const WorldScaleScript: Script = preload("res://shared/world_scale.gd")

signal sector_generation_requested(peer_id: int, sector_id: String, position: Vector3)

var _last_sector_by_peer: Dictionary = {}
var _canon_lookup: Callable = Callable()
var _request_callback: Callable = Callable()
var _reload_callback: Callable = Callable()


## Injects a server-owned lookup. It must accept sector_id and return either a
## Dictionary with outcome == CanonRepository.OUTCOME_OK or a boolean.
func set_canon_lookup(lookup: Callable) -> void:
	_canon_lookup = lookup


## Injects the asynchronous generation acceptance callback. It receives
## (peer_id, sector_id, position); the callback must return immediately.
func set_request_callback(callback: Callable) -> void:
	_request_callback = callback


## Injects the synchronous Canon re-entry callback. It receives
## (peer_id, sector_id, position) only when the sector already exists.
func set_reload_callback(callback: Callable) -> void:
	_reload_callback = callback


## Observes one authoritative position. Reports whether generation was
## requested or existing Canon was reloaded for the entering peer.
func observe_position(peer_id: int, position: Vector3) -> Dictionary:
	var sector_id: String = sector_id_for_position(position)
	if _last_sector_by_peer.get(peer_id, "") == sector_id:
		return {"sector_id": sector_id, "requested": false, "reloaded": false}
	_last_sector_by_peer[peer_id] = sector_id

	if _has_canon(sector_id):
		if _reload_callback.is_valid():
			_reload_callback.call(peer_id, sector_id, position)
		return {"sector_id": sector_id, "requested": false, "reloaded": true}

	sector_generation_requested.emit(peer_id, sector_id, position)
	if _request_callback.is_valid():
		_request_callback.call(peer_id, sector_id, position)
	return {"sector_id": sector_id, "requested": true, "reloaded": false}


## Clears a disconnected peer's transition state so a future connection with
## the same peer id is evaluated from its new authoritative position.
func forget_peer(peer_id: int) -> void:
	_last_sector_by_peer.erase(peer_id)


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