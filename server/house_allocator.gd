extends RefCounted
class_name HouseAllocator
## Slice 019: server-authoritative allocation of the starting town's fixed
## house pool. Each connecting peer is assigned one unique house Structure from
## the hub fixture (Starting Town ticket 05); the slot frees immediately on
## disconnect with no reconnect reservation (there is no identity/save system
## yet to recognize a returning player, so reserving would only leak slots as
## players churn). Independent of the SceneTree so it is fully unit-testable.
## See docs/slices/019-player-house-allocation.md.

var _pool: Array[String] = []
## peer_id (int) -> house structure_id (String).
var _assigned: Dictionary = {}


func _init(house_ids: Array[String]) -> void:
	for house_id: String in house_ids:
		_pool.append(house_id)


## Extracts the ordered house structure ids from a validated sector blueprint
## (structures whose kind == "house"). Static so the server can build the pool
## straight from the hub fixture Dictionary without instantiating first.
static func house_ids_from_blueprint(blueprint: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for structure: Dictionary in blueprint.get("structures", []):
		if String(structure.get("kind", "")) == "house":
			ids.append(String(structure.get("structure_id", "")))
	return ids


## Assigns a unique house to peer_id and returns its id. Idempotent: a peer
## that already holds a house gets the same one back rather than a second slot.
## Returns "" when the pool is exhausted — a fail-closed signal the caller
## logs; unreachable in steady state since the pool size matches the server's
## max concurrent peers.
func assign(peer_id: int) -> String:
	if _assigned.has(peer_id):
		return _assigned[peer_id]
	for house_id: String in _pool:
		if not _is_taken(house_id):
			_assigned[peer_id] = house_id
			return house_id
	return ""


## Frees peer_id's house back to the pool immediately (no reservation window).
## A no-op if the peer holds none.
func release(peer_id: int) -> void:
	_assigned.erase(peer_id)


func assigned_house(peer_id: int) -> String:
	return _assigned.get(peer_id, "")


func available_count() -> int:
	return _pool.size() - _assigned.size()


func pool_size() -> int:
	return _pool.size()


func _is_taken(house_id: String) -> bool:
	for taken: String in _assigned.values():
		if taken == house_id:
			return true
	return false
