extends "res://server/server_main.gd"

const PairedIssuer: Script = preload("res://server/assertion_issuer.gd")
const PairedValidator: Script = preload("res://server/assertion_validator.gd")
var _paired_identity: String = ""
var _paired_observation: Dictionary = {"authenticated": false, "input_ack_sequence": -1}


func _initialize() -> void:
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