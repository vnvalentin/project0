extends RefCounted

const SECRET_ENV: String = "PROJECT0_ASSERTION_SECRET"
const ASSERTION_ENV: String = "PROJECT0_TEST_CHARACTER_ASSERTION"


static func begin() -> Dictionary:
	var previous: Dictionary = {}
	for key: String in [SECRET_ENV, ASSERTION_ENV, "PROJECT0_ACCOUNTS_DB_PATH", "PROJECT0_CANON_DB_PATH"]:
		previous[key] = OS.get_environment(key) if OS.has_environment(key) else null
	OS.set_environment(SECRET_ENV, Crypto.new().generate_random_bytes(32).hex_encode())
	var database: String = "test_gameplay_%d_%d.db" % [OS.get_process_id(), Time.get_ticks_usec()]
	OS.set_environment("PROJECT0_ACCOUNTS_DB_PATH", database)
	OS.set_environment("PROJECT0_CANON_DB_PATH", "")
	refresh_identity()
	return {"environment": previous, "database": database}


static func refresh_identity() -> void:
	var issuer_script: Script = load("res://server/assertion_issuer.gd")
	var issuer: Object = issuer_script.new(OS.get_environment(SECRET_ENV), "project0-login", "project0-game")
	var identity: String = "test-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var token: String = issuer.issue(identity, identity, identity, int(Time.get_unix_time_from_system()), 120, "Test Player", {})
	OS.set_environment(ASSERTION_ENV, token)


static func seed_melee_journey(database: String) -> bool:
	if not database.begins_with("test_melee_1173_") or database.contains("/"):
		return false
	var parts: PackedStringArray = OS.get_environment(ASSERTION_ENV).split(".")
	if parts.size() != 2:
		return false
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(parts[0]))
	if not claims is Dictionary or String(claims.get("cid", "")).is_empty():
		return false
	var store_script: Script = load("res://server/sqlite_store.gd")
	var repository_script: Script = load("res://server/journey_repository.gd")
	var registry_script: Script = load("res://server/journey_registry.gd")
	var store: Object = store_script.new()
	if store.open(database).get("outcome", "") != "ok":
		return false
	var repository: Object = repository_script.new(store)
	var registry: Object = registry_script.new()
	registry.set_repository(repository)
	var character_id: String = String(claims["cid"])
	var now: int = int(Time.get_unix_time_from_system())
	var seeded: bool = repository.ensure_schema().get("outcome", "") == "ok"
	seeded = seeded and registry.enter(character_id, 1, now).get("outcome", "") == "ok"
	seeded = seeded and registry.checkpoint(character_id, Vector3(3, 1, 3), now).get("outcome", "") == "ok"
	seeded = seeded and registry.mark_disconnected(character_id, 1, now).get("outcome", "") == "ok"
	store.close()
	return seeded


static func restore(previous: Dictionary) -> bool:
	var success: bool = true
	var environment: Dictionary = previous["environment"]
	for key: String in environment:
		if environment[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, environment[key])
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = "user://" + String(previous["database"]) + suffix
		if FileAccess.file_exists(path):
			var removed: Error = DirAccess.remove_absolute(path)
			if removed != OK:
				success = false
	return success


static func enter_world(network: Node) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not String(network.status).begins_with("connected") and Time.get_ticks_msec() < deadline:
		await network.get_tree().process_frame
	var token: String = OS.get_environment(ASSERTION_ENV)
	if token.is_empty() or not String(network.status).begins_with("connected"):
		return false
	var session_result: Array[String] = []
	var session_callback: Callable = func(outcome: String) -> void: session_result.append(outcome)
	network.session_established_received.connect(session_callback)
	network.submit_present_assertion(token)
	deadline = Time.get_ticks_msec() + 5000
	while session_result.is_empty() and Time.get_ticks_msec() < deadline:
		await network.get_tree().process_frame
	network.session_established_received.disconnect(session_callback)
	if session_result.is_empty() or session_result[0] != "ok":
		return false
	var world_result: Array[String] = []
	var world_callback: Callable = func(outcome: String, _character: Dictionary) -> void: world_result.append(outcome)
	network.world_entry_received.connect(world_callback)
	network.submit_enter_world()
	deadline = Time.get_ticks_msec() + 5000
	while world_result.is_empty() and Time.get_ticks_msec() < deadline:
		await network.get_tree().process_frame
	network.world_entry_received.disconnect(world_callback)
	return not world_result.is_empty() and world_result[0] == "ok"
