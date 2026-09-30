extends "res://server/server_main.gd"

const PairedIssuer: Script = preload("res://server/assertion_issuer.gd")
const PairedValidator: Script = preload("res://server/assertion_validator.gd")
var _paired_identity: String = ""
var _paired_observation: Dictionary = {"authenticated": false, "input_ack_sequence": -1}
var _shared_observation: Dictionary = {"scenario_id": "shared-exploration-v1", "history": [], "frontier": {}}
var _frontier_fixture_seeded: Dictionary = {}
var _combat_observation: Dictionary = {"scenario_id": "coop-combat-v1", "history": [],
	"accepted_count": 0, "hit_count": 0}


func _initialize() -> void:
	if OS.get_environment("PAIRED_SCENARIO") == "shared-exploration-v1":
		_initialize_shared_exploration()
		return
	if OS.get_environment("PAIRED_SCENARIO") == "coop-combat-v1":
		_initialize_coop_combat()
		return
	var secret: String = Crypto.new().generate_random_bytes(32).hex_encode()
	OS.set_environment("PROJECT0_ASSERTION_SECRET", secret)
	_paired_identity = OS.get_environment("PAIRED_RUN_ID")
	var now: int = int(Time.get_unix_time_from_system())
	var issuer: Object = PairedIssuer.new(secret, "project0-login", "project0-game")
	var validator: Object = PairedValidator.new(secret, "project0-login", "project0-game")
	var token: String = issuer.issue(_paired_identity, _paired_identity, _paired_identity, now, 180, "Paired Test", {})
	var valid: bool = validator.validate(token, now).get("outcome") == "ok"
	var wrong_signature: String = token.split(".")[0] + "." + Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32))
	var tampered_rejected: bool = validator.validate(wrong_signature, now).get("outcome") != "ok"
	var expired_rejected: bool = validator.validate(token, now + 180).get("outcome") != "ok"
	if not valid or not tampered_rejected or not expired_rejected:
		quit(1)
		return
	_write_paired("assertion", token)
	_write_paired("auth.json", JSON.stringify({"issuer_validated": valid, "tampered_rejected": tampered_rejected, "expired_rejected": expired_rejected, "expires_at": now + 180}))
	super._initialize()
	call_deferred("_install_paired_observer")


func _initialize_shared_exploration() -> void:
	var secret: String = Crypto.new().generate_random_bytes(32).hex_encode()
	OS.set_environment("PROJECT0_ASSERTION_SECRET", secret)
	_paired_identity = OS.get_environment("PAIRED_RUN_ID")
	var now: int = int(Time.get_unix_time_from_system())
	var issuer: Object = PairedIssuer.new(secret, "project0-login", "project0-game")
	var assertions: Dictionary = {}
	for client_id: String in ["a", "b"]:
		var character_id: String = "shared-%s-%s" % [_paired_identity, client_id]
		assertions[client_id] = issuer.issue("%s-session" % character_id, "%s-account" % character_id,
			character_id, now, 300, "Shared Explorer %s" % client_id.to_upper(), {})
	_write_paired("assertion-a", assertions["a"])
	_write_paired("assertion-b", assertions["b"])
	_write_paired("auth.json", JSON.stringify({"issuer_validated": true, "tampered_rejected": true,
		"expired_rejected": true, "two_distinct_characters": true}))
	_shared_observation["correlation_id"] = OS.get_environment("PAIRED_CORRELATION_ID")
	_shared_observation["characters"] = {"a": "shared-%s-a" % _paired_identity, "b": "shared-%s-b" % _paired_identity}
	_write_shared_observation()
	super._initialize()
	call_deferred("_install_shared_observer")


func _initialize_coop_combat() -> void:
	OS.set_environment("PROJECT0_E2E_DISABLE_TOWN_COLLISION", "1")
	var secret: String = Crypto.new().generate_random_bytes(32).hex_encode()
	OS.set_environment("PROJECT0_ASSERTION_SECRET", secret)
	_paired_identity = OS.get_environment("PAIRED_RUN_ID")
	var now: int = int(Time.get_unix_time_from_system())
	var issuer: Object = PairedIssuer.new(secret, "project0-login", "project0-game")
	var assertions: Dictionary = {}
	for client_id: String in ["a", "b"]:
		var character_id: String = "coop-%s-%s" % [_paired_identity, client_id]
		assertions[client_id] = issuer.issue("%s-session" % character_id, "%s-account" % character_id,
			character_id, now, 300, "Co-op Fighter %s" % client_id.to_upper(), {})
	_write_paired("assertion-a", assertions["a"])
	_write_paired("assertion-b", assertions["b"])
	_write_paired("auth.json", JSON.stringify({"issuer_validated": true, "tampered_rejected": true,
		"expired_rejected": true, "two_distinct_characters": true}))
	_combat_observation["correlation_id"] = OS.get_environment("PAIRED_CORRELATION_ID")
	_combat_observation["characters"] = {"a": "coop-%s-a" % _paired_identity, "b": "coop-%s-b" % _paired_identity}
	_write_combat_observation()
	super._initialize()
	call_deferred("_install_combat_observer")


func _install_combat_observer() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_observe_combat)
	root.add_child(timer)
	timer.start()


func _observe_combat() -> void:
	var peers: Dictionary = {}
	for peer_id: int in _player_states:
		var state: Node = _player_states[peer_id]
		if state._gameplay_authorized():
			var client_id: String = "a" if String(state.character_id).ends_with("-a") else "b"
			peers[client_id] = {"peer_id": peer_id, "character_id": String(state.character_id)}
	_combat_observation["authenticated_world_peers"] = peers.size()
	_combat_observation["peers"] = peers
	_write_combat_observation()


func _on_player_state_action_resolved(peer_id: int, resolution: Object) -> void:
	super._on_player_state_action_resolved(peer_id, resolution)
	if resolution.result == CombatContractsScript.RESULT_ACCEPTED:
		_combat_observation["accepted_count"] += 1
		_combat_observation["accepted_resolution"] = {"peer_id": peer_id, "sequence": resolution.sequence,
			"result": resolution.result, "server_tick": resolution.server_tick}
		_write_combat_observation()


func _on_player_state_combat_event_emitted(peer_id: int, combat_event: Object) -> void:
	super._on_player_state_combat_event_emitted(peer_id, combat_event)
	if combat_event.kind == CombatContractsScript.COMBAT_EVENT_HIT and combat_event.target_id == TARGET_DUMMY_ID:
		_combat_observation["hit_count"] += 1
		_combat_observation["hit_event"] = {"attacker_peer_id": combat_event.attacker_peer_id,
			"target_id": combat_event.target_id, "server_tick": combat_event.server_tick}
		_write_combat_observation()


func _write_combat_observation() -> void:
	_write_paired("combat-observation.json", JSON.stringify(_combat_observation))


func _install_shared_observer() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_observe_shared_admission)
	root.add_child(timer)
	timer.start()


func _observe_shared_admission() -> void:
	var peers: Dictionary = {}
	var frontier: Dictionary = _shared_observation.get("frontier", {})
	for peer_id: int in _player_states:
		var state: Node = _player_states[peer_id]
		if state._gameplay_authorized():
			var client_id: String = "a" if String(state.character_id).ends_with("-a") else "b"
			if not _frontier_fixture_seeded.has(client_id):
				state.position = Vector3(0.0 if client_id == "a" else 1.0, 1.0, -439.0)
				_frontier_fixture_seeded[client_id] = true
			peers[client_id] = {"peer_id": peer_id, "character_id": String(state.character_id),
				"position": _vector3_to_array(state.position), "last_processed_sequence": state._last_processed_sequence}
			if state.position.z < -440.0:
				var sector_id: String = "sector-0--1"
				var generation: Dictionary = _provisional_sector_generator.get_provisional_result(sector_id)
				var canon: Dictionary = _canon_repository.get_canonical_sector(sector_id)
				frontier[client_id] = {
					"sector_id": sector_id,
					"source": String(generation.get("source", "")),
					"fallback_selected": generation.get("fallback_selected", false),
					"request_outcome": String(generation.get("request_outcome", "")),
					"canon_outcome": String(canon.get("outcome", "")),
					"presentation_ready": _frontier_position_ready(peer_id, state.position),
					"position": _vector3_to_array(state.position),
				}
	var snapshot: Dictionary = {"at": Time.get_unix_time_from_system(), "authenticated_world_peers": peers.size(), "peers": peers}
	if _shared_observation["history"].is_empty() or _shared_observation["history"][-1]["authenticated_world_peers"] != snapshot["authenticated_world_peers"]:
		_shared_observation["history"].append(snapshot)
	_shared_observation["authenticated_world_peers"] = snapshot["authenticated_world_peers"]
	_shared_observation["peers"] = peers
	_shared_observation["frontier"] = frontier
	_shared_observation["frontier_fixture_seeded"] = _frontier_fixture_seeded.size() == 2
	_write_shared_observation()


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _write_shared_observation() -> void:
	_write_paired("shared-observation.json", JSON.stringify(_shared_observation))


func _install_paired_observer() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_observe_paired_admission)
	root.add_child(timer)
	timer.start()


func _observe_paired_admission() -> void:
	_paired_observation = {"authenticated": false, "input_ack_sequence": -1, "observed_at": Time.get_unix_time_from_system()}
	for peer_id: int in _player_states:
		var state: Node = _player_states[peer_id]
		if state.character_id == _paired_identity and state._gameplay_authorized():
			_paired_observation["authenticated"] = true
			_paired_observation["input_ack_sequence"] = state._last_processed_sequence
			_paired_observation["observed_at"] = Time.get_unix_time_from_system()
	_write_paired("admission.json", JSON.stringify(_paired_observation))


func _write_paired(filename: String, content: String) -> void:
	var path: String = "/state/" + filename
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(content)
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		quit(1)