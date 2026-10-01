extends "res://server/server_main.gd"
## Experiment #1236 server fixture. Setup, outside the measured window,
## canonicalizes a target frontier sector and gives it and the hub a valid
## mutation history through the real repositories, then seeds the declared
## fault with raw SQL on the owned database. Integrity, quarantine, denial and
## presentation stay in the real server; this only records what it does.

const Exp1236Guid: Script = preload("res://shared/canon_entity_guid.gd")
const Exp1236Placement: Script = preload("res://shared/sector_detail_placement.gd")
const EXP1236_TARGET: String = "sector-0-0"
const EXP1236_HUB: String = "starting_town_hub"
const EXP1236_TARGET_POSITION: Vector3 = Vector3(200.0, 1.0, 200.0)
const EXP1236_OBSERVER_POSITION: Vector3 = Vector3(10.0, 1.0, 2.0)
const EXP1236_FAULTS: Dictionary = {
	"intact_control": "",
	"base_unavailable": "DELETE FROM canon_sectors WHERE sector_id = 'sector-0-0';",
	"blueprint_corrupt": "UPDATE canon_sectors SET blueprint_json = substr(blueprint_json, 1, 40) WHERE sector_id = 'sector-0-0';",
	"mutation_corrupt": "UPDATE canon_mutations SET payload_json = '{\"looted\": tru' WHERE sector_id = 'sector-0-0';",
	"replay_inconsistent": "UPDATE canon_mutations SET applied_revision = 2 WHERE sector_id = 'sector-0-0';",
}
const EXP1236_SAMPLE_FRAMES: int = 15
const EXP1236_MAX_SAMPLES: int = 4000

var _exp_case: String = OS.get_environment("EXP1236_CASE")
var _exp_observation: Dictionary = {"case": OS.get_environment("EXP1236_CASE"), "bound": [], "samples": [],
	"presentations": [], "reload_events": [], "telemetry": []}
var _exp_frame: int = 0
var _exp_finalized: bool = false


func _initialize() -> void:
	super()
	_exp_observation["boot"] = {"pid": OS.get_process_id()}
	physics_frame.connect(_exp1236_on_physics_frame)
	process_frame.connect(_exp1236_poll_finalize)


func _start_server() -> void:
	await super()
	_exp_observation["setup"] = _exp1236_setup()
	_exp_observation["window_start"] = _exp1236_counters()
	_exp_write()


func _exp1236_setup() -> Dictionary:
	var store: SqliteStore = _exp1236_store()
	if store == null or _canon_repository == null or _canon_mutation_repository == null:
		return {"error": "canon_unavailable"}
	var setup: Dictionary = {"target": EXP1236_TARGET, "fault_case": _exp_case, "target_position": _exp_vec(EXP1236_TARGET_POSITION)}
	var blueprint: Dictionary = _exp1236_target_blueprint()
	setup["target_blueprint"] = blueprint
	setup["target_canonicalize"] = String(_canon_repository.canonicalize_blueprint(blueprint).get("outcome", ""))
	var target_guid: String = Exp1236Guid.derive(EXP1236_TARGET, Exp1236Guid.ENTITY_CLASS_STRUCTURE, "exp1236_well")
	setup["target_mutation"] = String(_canon_mutation_repository.apply_mutation(_exp1236_loot(EXP1236_TARGET, target_guid)).get("outcome", ""))
	var control_guid: String = ""
	for structure: Dictionary in _starting_town_hub_blueprint.get("structures", []):
		if String(structure.get("kind", "")) == "well":
			control_guid = Exp1236Guid.derive(EXP1236_HUB, Exp1236Guid.ENTITY_CLASS_STRUCTURE, String(structure["structure_id"]))
			break
	setup["control_mutation"] = String(_canon_mutation_repository.apply_mutation(_exp1236_loot(EXP1236_HUB, control_guid)).get("outcome", ""))
	var journal: Dictionary = store.query("PRAGMA journal_mode;")
	setup["journal_mode"] = String(journal["rows"][0]["journal_mode"]) if journal.get("outcome") == "ok" else null
	setup["original_rows"] = _exp1236_rows()
	if not EXP1236_FAULTS.has(_exp_case):
		setup["error"] = "unknown_case"
		return setup
	var sql: String = EXP1236_FAULTS[_exp_case]
	setup["fault_sql"] = sql
	setup["fault_applied"] = true if sql.is_empty() else store.query(sql).get("outcome") == "ok"
	setup["faulted_rows"] = _exp1236_rows()
	return setup


## Placement follows the real JIT rule so the declared ingress is inside the detail.
func _exp1236_target_blueprint() -> Dictionary:
	var placement: Dictionary = Exp1236Placement.select(EXP1236_TARGET, EXP1236_TARGET_POSITION)
	var origin: Dictionary = placement.get("origin", {"x": 0, "y": 0})
	var tiles: Array[Dictionary] = []
	for dx: int in range(-5, 6):
		for dy: int in range(-5, 6):
			tiles.append({"x": int(origin["x"]) + dx, "y": int(origin["y"]) + dy, "kind": "floor"})
	return {
		"schema_version": 5, "sector_id": EXP1236_TARGET, "detail_origin": placement.get("detail_origin", {}),
		"origin": origin, "tiles": tiles,
		"structures": [{"structure_id": "exp1236_well", "kind": "well", "x": int(origin["x"]) + 4, "y": int(origin["y"]) + 4, "facing_degrees": 0}],
	}


func _exp1236_loot(sector_id: String, target_guid: String) -> Dictionary:
	return {
		"schema_version": 1, "event_id": "exp1236-setup-%s" % sector_id, "sector_id": sector_id,
		"target_guid": target_guid, "mutation_kind": "loot", "actor_player_id": "exp1236-setup",
		"server_tick": _current_server_tick(), "expected_revision": 0, "payload": {"looted": true},
	}


func _on_player_state_character_bound(peer_id: int, display_name: String, cosmetic: Dictionary) -> void:
	var state: Node = _player_states.get(peer_id)
	var role: String = _exp1236_role(state)
	if not role.is_empty():
		state.restore_authoritative_position(EXP1236_TARGET_POSITION if role == "actor" else EXP1236_OBSERVER_POSITION)
	super(peer_id, display_name, cosmetic)
	if role.is_empty():
		return
	var character_id: String = String(state.character_id)
	_exp_observation["bound"].append({"role": role, "peer_id": peer_id, "character_id": character_id,
		"journey_id": _frontier_journey_id(peer_id, character_id), "tick": _current_server_tick(), "frame": _exp_frame,
		"position": _exp_vec(state.position)})
	_exp_write()


func _send_sector_blueprint(peer_id: int, blueprint: Dictionary, ingress: Vector3, trace: Dictionary) -> void:
	_exp_observation["presentations"].append({"peer_id": peer_id, "sector_id": String(blueprint.get("sector_id", "")),
		"tick": _current_server_tick(), "frame": _exp_frame})
	super(peer_id, blueprint, ingress, trace)


func _record_canon_reload(peer_id: int, sector_id: String, presented: Dictionary) -> void:
	var before: int = _canon_reload_events.size()
	super(peer_id, sector_id, presented)
	if _canon_reload_events.size() > before:
		var event: Dictionary = _canon_reload_events.back().duplicate(true)
		event["tick"] = _current_server_tick()
		_exp_observation["reload_events"].append(event)
		_exp_write()


func _emit_server_telemetry(event_type: String, peer_id: int, payload: Dictionary) -> void:
	if event_type.begins_with("canon.sector_"):
		_exp_observation["telemetry"].append({"event_type": event_type, "peer_id": peer_id, "payload": payload.duplicate(true), "tick": _current_server_tick()})
	super(event_type, peer_id, payload)


func _exp1236_on_physics_frame() -> void:
	_exp_frame += 1
	if _exp_frame % EXP1236_SAMPLE_FRAMES != 0 or _exp_finalized:
		return
	var samples: Array = _exp_observation["samples"]
	for peer_id: int in _player_states:
		var state: Node = _player_states[peer_id]
		var role: String = _exp1236_role(state)
		if not role.is_empty() and samples.size() < EXP1236_MAX_SAMPLES:
			samples.append({"role": role, "peer_id": peer_id, "tick": _current_server_tick(), "frame": _exp_frame, "position": _exp_vec(state.position)})
	_exp_write()


func _exp1236_poll_finalize() -> void:
	var path: String = OS.get_environment("EXP1236_FINALIZE")
	if _exp_finalized or path.is_empty() or not FileAccess.file_exists(path):
		return
	_exp_finalized = true
	_exp_observation["final"] = {
		"counters": _exp1236_counters(),
		"rows": _exp1236_rows(),
		"quarantine": sector_quarantine_evidence(),
		"tick": _current_server_tick(),
		"frame": _exp_frame,
		"connected_players": _player_states.size(),
	}
	_exp_write()
	quit(0)


func _exp1236_role(state: Node) -> String:
	if state == null:
		return ""
	var character_id: String = String(state.character_id)
	if character_id.is_empty():
		return ""
	if character_id == OS.get_environment("EXP1236_ACTOR_CID"):
		return "actor"
	if character_id == OS.get_environment("EXP1236_OBSERVER_CID"):
		return "observer"
	return ""


func _exp1236_store() -> SqliteStore:
	return _canon_store if _canon_store != null else _accounts_store


func _exp1236_counters() -> Dictionary:
	var store: SqliteStore = _exp1236_store()
	return {"canon_writes": store.canon_write_counters() if store != null else null, "generation_count": content_generation_count(),
		"tick": _current_server_tick(), "frame": _exp_frame}


func _exp1236_rows() -> Dictionary:
	var store: SqliteStore = _exp1236_store()
	var sectors: Dictionary = store.query("SELECT * FROM canon_sectors ORDER BY sector_id;")
	var mutations: Dictionary = store.query("SELECT * FROM canon_mutations ORDER BY sector_id, event_id;")
	return {
		"canon_sectors": sectors["rows"] if sectors.get("outcome") == "ok" else null,
		"canon_mutations": mutations["rows"] if mutations.get("outcome") == "ok" else null,
	}


func _exp_write() -> void:
	var path: String = OS.get_environment("EXP1236_OBSERVATION")
	if path.is_empty():
		return
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("EXP1236 observation write failed: %s" % path)
		return
	file.store_string(JSON.stringify(_exp_observation, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


static func _exp_vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
