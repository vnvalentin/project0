extends RefCounted
class_name ServerTownNpcManager
## Slice 130 (Phase 14): the server-side runtime that staffs a town's fixed
## anchors with live town NPCs (ServerTownNpcState), using the SpawnAnchor
## contract for population dynamics. A RefCounted driven by server_main each tick,
## so its whole lifecycle is unit-testable without a SceneTree, like
## ServerMonsterManager. See issue #232 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## Population behaviour (map "What Good Looks Like" item 6): each anchor wants a
## role filled to a capacity. When an occupant is lost the anchor is NOT instantly
## refilled: replacement is DELAYED and shortened by PRESSURE (nearby players),
## and is either a SILENT PROMOTION of an ambient NPC into the role (no pop-in) or,
## when none is available, a NEWLY GENERATED, contextually-named identity — never
## resurrecting the same individual.

const ServerTownNpcStateScript: Script = preload("res://server/server_town_npc_state.gd")
const SpawnAnchorScript: Script = preload("res://shared/spawn_anchor.gd")
const ActivityRoutineScript: Script = preload("res://shared/activity_routine.gd")

## Radius (yards) around an anchor within which a player counts as demand
## (pressure) for that anchor.
const PRESSURE_RADIUS_YARDS: float = 20.0
const DEFAULT_REPLACEMENT_DELAY_TICKS: int = 300

signal npc_spawned(npc_id: String, anchor_id: String, source: String, server_tick: int)
signal npc_removed(npc_id: String, anchor_id: String, server_tick: int)

var _slots: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_identity: int = 0
## Ambient NPCs (display names) available for silent promotion into a role.
var _ambient_names: Array[String] = []


## `anchor_defs`: each a Dictionary with anchor_id, role, home_position (Vector3),
## desired_capacity, and optional replacement_delay_ticks, routine_steps,
## activity_locations. Anchors start staffed to capacity.
func _init(anchor_defs: Array, rng_seed: int = 0) -> void:
	_rng.seed = rng_seed
	for def: Dictionary in anchor_defs:
		var desired: int = int(def.get("desired_capacity", 1))
		var anchor_id: String = String(def.get("anchor_id", "anchor_%d" % _slots.size()))
		var role: String = String(def.get("role", "villager"))
		var delay: int = int(def.get("replacement_delay_ticks", DEFAULT_REPLACEMENT_DELAY_TICKS))
		var anchor: Object = SpawnAnchorScript.from_wire_dict({
			"schema_version": 1,
			"anchor_id": anchor_id,
			"role": role,
			"desired_capacity": desired,
			"current_occupancy": 0,
			"replacement_delay_ticks": delay,
		})["anchor"]
		var slot: Dictionary = {
			"anchor": anchor,
			"anchor_id": anchor_id,
			"role": role,
			"home": def.get("home_position", Vector3.ZERO),
			"steps": def.get("routine_steps", []),
			"locations": def.get("activity_locations", {}),
			"npcs": [],
		}
		for _i in desired:
			_spawn_into(slot, SpawnAnchorScript.SOURCE_GENERATE, 0, false)
		_slots.append(slot)


func anchor_count() -> int:
	return _slots.size()


func npc_count() -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		total += (slot["npcs"] as Array).size()
	return total


func npcs_at(index: int) -> Array:
	if index < 0 or index >= _slots.size():
		return []
	return _slots[index]["npcs"]


## Every live town NPC across all anchors, for the server runtime to replicate.
func all_npcs() -> Array:
	var all: Array = []
	for slot: Dictionary in _slots:
		all.append_array(slot["npcs"] as Array)
	return all


## The live NPC with this id, or null if none — for targeted replication.
func find_npc(npc_id: String) -> Object:
	for slot: Dictionary in _slots:
		for npc: Variant in (slot["npcs"] as Array):
			if (npc as Object).npc_id == npc_id:
				return npc
	return null



func anchor_deficit(index: int) -> int:
	if index < 0 or index >= _slots.size():
		return 0
	return (_slots[index]["anchor"] as Object).current_deficit()


## Register an ambient NPC (by display name) that may be silently promoted into a
## role when a replacement is due.
func add_ambient_candidate(display_name: String) -> void:
	_ambient_names.append(display_name)


## Simulate losing an occupant (it departed, was defeated, etc.): removes the NPC
## and vacates its anchor so a delayed replacement is scheduled.
func remove_npc(anchor_index: int, npc_id: String, server_tick: int) -> bool:
	if anchor_index < 0 or anchor_index >= _slots.size():
		return false
	var slot: Dictionary = _slots[anchor_index]
	var npcs: Array = slot["npcs"]
	for i in range(npcs.size()):
		if (npcs[i] as Object).npc_id == npc_id:
			npcs.remove_at(i)
			(slot["anchor"] as Object).vacate(1)
			npc_removed.emit(npc_id, slot["anchor_id"], server_tick)
			return true
	return false


## Advance the population one tick: accumulate each understaffed anchor's vacancy
## clock and, when a pressure-scaled replacement is due, staff it — promoting an
## ambient NPC when available, else generating a new identity.
func advance(observer_positions: Array, ticks: int, server_tick: int) -> void:
	for slot: Dictionary in _slots:
		var anchor: Object = slot["anchor"]
		anchor.advance(ticks)
		if not anchor.is_understaffed():
			continue
		var pressure: float = _pressure_for(slot, observer_positions)
		var plan: Dictionary = anchor.plan_replacement(pressure, not _ambient_names.is_empty())
		if plan["due"]:
			_spawn_into(slot, String(plan["source"]), server_tick, true)


func _pressure_for(slot: Dictionary, observer_positions: Array) -> float:
	var home: Vector3 = slot["home"]
	for observer: Variant in observer_positions:
		if (observer as Vector3).distance_to(home) <= PRESSURE_RADIUS_YARDS:
			return 1.0
	return 0.0


func _spawn_into(slot: Dictionary, source: String, server_tick: int, emit: bool) -> Object:
	var display_name: String
	var resolved_source: String = source
	if source == SpawnAnchorScript.SOURCE_PROMOTE and not _ambient_names.is_empty():
		display_name = _ambient_names.pop_front()
	else:
		resolved_source = SpawnAnchorScript.SOURCE_GENERATE
		display_name = _generate_identity(String(slot["role"]))
	var npc_id: String = "%s_%d" % [slot["anchor_id"], _next_identity]
	_next_identity += 1
	var routine: Object = ActivityRoutineScript.from_wire_dict({
		"schema_version": 1, "steps": slot["steps"], "fallback_mode": "patrol"
	})["routine"]
	var npc: Object = ServerTownNpcStateScript.new(
		npc_id, slot["home"], routine, slot["locations"], display_name
	)
	(slot["npcs"] as Array).append(npc)
	(slot["anchor"] as Object).fill()
	if emit:
		npc_spawned.emit(npc_id, slot["anchor_id"], resolved_source, server_tick)
	return npc


## Contextual identity generation: a fresh, role-flavoured display name.
func _generate_identity(role: String) -> String:
	return "%s-%04d" % [role, _rng.randi_range(1000, 9999)]
