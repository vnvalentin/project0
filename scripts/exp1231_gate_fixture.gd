extends "res://server/server_main.gd"
## Experiment #1231 server fixture: one gate-unlock validation case per process.
## Setup places bound players and dynamic occluders at declared server-owned
## positions; validation, LOS, reach and commit stay in the real service.

const Exp1231Guid: Script = preload("res://shared/canon_entity_guid.gd")
const Exp1231Resolver: Script = preload("res://shared/canon_sector_resolver.gd")
const EXP1231_HUB: String = "starting_town_hub"
const EXP1231_GATE_ID: String = "gate_01"
const EXP1231_GATE_POINT: Vector3 = Vector3(0.0, 0.0, -5.0)
const EXP1231_OCCLUDER_DEFAULT: Vector3 = Vector3(6.0, 1.0, 0.0)
const EXP1231_OBSTACLE: Dictionary = {"structure_id": "exp1231_well", "kind": "well", "x": 0, "y": -4, "facing_degrees": 0.0}
## Actor positions are declared per case; the gate point is the gate anchor at ground level.
const EXP1231_ACTOR: Dictionary = {
	"valid_in_range": Vector3(0.0, 1.0, -3.4),
	"exactly_two_yards": Vector3(0.0, 1.0, -3.0),
	"over_range": Vector3(0.0, 1.0, -2.5),
	"static_obstacle": Vector3(0.0, 1.0, -3.4),
	"dynamic_occluders": Vector3(0.0, 1.0, -3.4),
	"target_gate_side_hit": Vector3(-1.5, 1.0, -5.0),
	"malformed_intent": Vector3(0.0, 1.0, -3.4),
	"wrong_owner": Vector3(0.0, 1.0, -3.4),
	"unbound_actor": Vector3(0.0, 1.0, -3.4),
	"nonexistent_target": Vector3(0.0, 1.0, -3.4),
	"not_lockable_target": Vector3(0.0, 1.0, -3.4),
}
const EXP1231_OCCLUDER_PLAYER: Vector3 = Vector3(0.0, 1.0, -4.3)
const EXP1231_OCCLUDER_NPC: Vector3 = Vector3(0.0, 1.0, -3.8)
const EXP1231_OCCLUDER_MONSTER: Vector3 = Vector3(0.0, 1.0, -4.6)

var _exp_case: String = OS.get_environment("EXP1231_CASE")
var _exp_observation: Dictionary = {"case": OS.get_environment("EXP1231_CASE"), "bound": {}, "resolutions": [], "boot": {}}
var _exp_receive_seq: int = 0


func _starting_town_hub_source() -> Dictionary:
	var blueprint: Dictionary = super()
	if _exp_case == "static_obstacle":
		(blueprint["structures"] as Array).append(EXP1231_OBSTACLE.duplicate(true))
	return blueprint


func _on_player_state_character_bound(peer_id: int, display_name: String, cosmetic: Dictionary) -> void:
	super(peer_id, display_name, cosmetic)
	var state: Node = _player_states.get(peer_id)
	if state == null:
		return
	var character_id: String = String(state.character_id)
	var role: String = ""
	if character_id == OS.get_environment("EXP1231_ACTOR_CID"):
		role = "actor"
		state.position = EXP1231_ACTOR.get(_exp_case, EXP1231_ACTOR["valid_in_range"])
	elif character_id == OS.get_environment("EXP1231_OCCLUDER_CID"):
		role = "occluder"
		state.position = EXP1231_OCCLUDER_PLAYER if _exp_case == "dynamic_occluders" else EXP1231_OCCLUDER_DEFAULT
	else:
		return
	_exp_observation["bound"][role] = {
		"peer_id": peer_id,
		"character_id": character_id,
		"journey_id": _frontier_journey_id(peer_id, character_id),
		"position": _exp_vec(state.position),
	}
	_exp_write()


func _resolve_environmental_interaction(sender_peer_id: int, intent: Dictionary) -> Dictionary:
	_exp_receive_seq += 1
	var occluders: Dictionary = _exp_place_occluders()
	var state: Node = _player_states.get(sender_peer_id)
	var actor_position: Variant = state.position if state != null else null
	var target_position: Variant = _exp_target_position(String(intent.get("target_guid", "")))
	var before: Dictionary = _exp_canon_state()
	var resolution: Dictionary = super(sender_peer_id, intent)
	var after: Dictionary = _exp_canon_state()
	var record: Dictionary = {
		"receive_seq": _exp_receive_seq,
		"server_tick": _current_server_tick(),
		"sender_peer_id": sender_peer_id,
		"has_player_state": state != null,
		"character_id": String(state.character_id) if state != null else "",
		"actor_position": _exp_vec(actor_position) if actor_position is Vector3 else null,
		"target_guid": String(intent.get("target_guid", "")),
		"target_position": _exp_vec(target_position) if target_position is Vector3 else null,
		"intent": var_to_str(intent),
		"occluders": occluders,
		"before": before,
		"after": after,
		"resolution": resolution if not resolution.is_empty() else null,
	}
	if actor_position is Vector3 and target_position is Vector3:
		var delta: Vector3 = (target_position as Vector3) - (actor_position as Vector3)
		record["distance_3d"] = delta.length()
		record["distance_horizontal"] = Vector2(delta.x, delta.z).length()
		record["server_line_of_sight"] = _has_environmental_line_of_sight(actor_position, target_position)
	_exp_observation["resolutions"].append(record)
	_exp_write()
	return resolution


func _exp_place_occluders() -> Dictionary:
	if _exp_case != "dynamic_occluders":
		return {}
	var placed: Dictionary = {}
	for state: Node in _player_states.values():
		if String(state.character_id) == OS.get_environment("EXP1231_OCCLUDER_CID"):
			placed["player"] = _exp_vec(state.position)
	if _monster_manager != null and _monster_manager.monster_count() > 0:
		var monster: Object = _monster_manager.monster_at(0)
		monster.position = EXP1231_OCCLUDER_MONSTER
		placed["monster"] = _exp_vec(monster.position)
	if _town_npc_manager != null and not _town_npc_manager.all_npcs().is_empty():
		var npc: Object = _town_npc_manager.all_npcs()[0]
		npc.interrupt("exp1231_hold", 0)
		npc._interrupt_position = EXP1231_OCCLUDER_NPC
		placed["npc"] = _exp_vec(npc.position_at(0))
	return placed


func _exp_target_position(target_guid: String) -> Variant:
	var sector: Dictionary = _canon_repository.get_canonical_sector(EXP1231_HUB)
	if sector.get("outcome") != "ok":
		return null
	for structure: Dictionary in sector["sector"]["blueprint"].get("structures", []):
		if Exp1231Guid.derive(EXP1231_HUB, Exp1231Guid.ENTITY_CLASS_STRUCTURE, String(structure["structure_id"])) == target_guid:
			return Vector3(float(structure["x"]), 0.0, float(structure["y"]))
	return null


func _exp_canon_state() -> Dictionary:
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	var sector: Dictionary = _canon_repository.get_canonical_sector(EXP1231_HUB)
	var mutations: Array = _canon_mutation_repository.list_mutations(EXP1231_HUB).get("mutations", [])
	var gate: Variant = null
	var obstacle_present: bool = false
	if sector.get("outcome") == "ok":
		var effective: Dictionary = Exp1231Resolver.resolve_effective_blueprint(sector["sector"]["blueprint"], mutations)
		for structure: Dictionary in effective.get("structures", []):
			if structure["structure_id"] == EXP1231_GATE_ID:
				gate = structure.duplicate(true)
			obstacle_present = obstacle_present or structure["structure_id"] == EXP1231_OBSTACLE["structure_id"]
	var journal: Dictionary = store.query("PRAGMA journal_mode;")
	return {
		"revision": _canon_mutation_repository.get_sector_revision(EXP1231_HUB).get("revision"),
		"mutations": mutations,
		"canon_writes": store.canon_write_counters(),
		"effective_gate": gate,
		"obstacle_present": obstacle_present,
		"journal_mode": String(journal["rows"][0]["journal_mode"]) if journal.get("outcome") == "ok" else null,
		"gate_guid": Exp1231Guid.derive(EXP1231_HUB, Exp1231Guid.ENTITY_CLASS_STRUCTURE, EXP1231_GATE_ID),
	}


func _exp_write() -> void:
	var path: String = OS.get_environment("EXP1231_OBSERVATION")
	if path.is_empty():
		return
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("EXP1231 observation write failed: %s" % path)
		return
	file.store_string(JSON.stringify(_exp_observation, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


static func _exp_vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
