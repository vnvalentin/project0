extends RefCounted
## Experiment #1237 remote-client seam. The validated #1234/#1235 orchestrators
## run the owned authoritative server on okami's LAN address; each client phase
## is published as a request plus a private token file, and the SETSUJOKU
## coordinator answers it with two packaged Windows clients. Server fixtures,
## oracles and the consolidated report are unchanged.

const LAN_HOST: String = "192.168.1.254"
const PHASE_TIMEOUT_MSEC: int = 240000
const TOKEN_TTL_SECONDS: int = 240
const SECRET_ENV: String = "PROJECT0_ASSERTION_SECRET"


static func lan_environment(values: Dictionary) -> Dictionary:
	var result: Dictionary = values.duplicate()
	if result.has("PROJECT0_SERVER_BIND_ADDRESS"):
		result["PROJECT0_SERVER_BIND_ADDRESS"] = LAN_HOST
	if result.has("PROJECT0_SERVER_PORT"):
		result["PROJECT0_REQUIRED_CLIENT_VERSION"] = OS.get_environment("EXP1237_CLIENT_VERSION")
	return result


static func free_lan_port() -> int:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	socket.bind(0, LAN_HOST)
	var port: int = socket.get_local_port()
	socket.close()
	return port


## Same identity, fresh expiry: a returning player must reclaim the same Character.
static func reissue(token: String) -> String:
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(token.split(".")[0]))
	var identity: String = String(claims.get("cid", "")) if claims is Dictionary else ""
	var issuer: Object = load("res://server/assertion_issuer.gd").new(OS.get_environment(SECRET_ENV), "project0-login", "project0-game")
	return issuer.issue(identity, identity, identity, int(Time.get_unix_time_from_system()), TOKEN_TTL_SECONDS, "Test Player", {})


static func publish_phase(tree: SceneTree, phase: String, case_dir: String, observation: String, actor_token: String, occluder_token: String) -> Dictionary:
	var tokens_path: String = "%s/private-phase-%s.tokens.json" % [case_dir, phase]
	var done_path: String = "%s/phase-%s.done" % [case_dir, phase]
	_write(tokens_path, {"actor": reissue(actor_token), "occluder": reissue(occluder_token)})
	OS.execute("chmod", ["600", tokens_path])
	var request: Dictionary = {
		"schema_version": 1, "experiment": 1237, "phase": phase, "case": case_dir.get_file(),
		"host": LAN_HOST, "port": int(OS.get_environment("PROJECT0_SERVER_PORT")),
		"client_version": OS.get_environment("EXP1237_CLIENT_VERSION"), "client_sha256": OS.get_environment("EXP1237_CLIENT_SHA256"),
		"observation": observation, "tokens": tokens_path, "done": done_path,
		"results": {"actor": "%s/actor-%s.json" % [case_dir, phase], "occluder": "%s/occluder-%s.json" % [case_dir, phase]},
		"published_unix": Time.get_unix_time_from_system(),
	}
	_write("%s/phase-%s.request.json" % [case_dir, phase], request)
	var started: int = Time.get_ticks_msec()
	while not FileAccess.file_exists(done_path) and Time.get_ticks_msec() - started < PHASE_TIMEOUT_MSEC:
		await tree.process_frame
	DirAccess.remove_absolute(tokens_path)
	return {"phase": phase, "completed": FileAccess.file_exists(done_path), "waited_msec": Time.get_ticks_msec() - started,
		"tokens_removed": not FileAccess.file_exists(tokens_path)}


## Packaged-client evidence the headless oracles cannot see; appended to each case's assertions.
static func client_checks(assertions: Array[Dictionary], check: Callable, results: Dictionary, phases: Array, returned: bool) -> void:
	check.call(assertions, "every remote client phase completed", phases.map(func(entry: Dictionary) -> bool: return entry.get("completed") == true), phases.map(func(_entry: Dictionary) -> bool: return true))
	for key: String in results:
		var result: Dictionary = results[key] if results[key] is Dictionary else {}
		check.call(assertions, "%s ran in the verified packaged client" % key,
			[result.get("client_mode"), result.get("pck_sha256"), result.get("client_version")],
			["godot-4.7.2-editor-hosting-package-pck", OS.get_environment("EXP1237_CLIENT_SHA256"), OS.get_environment("EXP1237_CLIENT_VERSION")])
		check.call(assertions, "%s geometry readiness completed for the hub" % key, (result.get("geometry_ready", []) as Array).has("starting_town_hub") if result.get("geometry_ready") is Array else null, true)
	if returned:
		for role: String in ["actor", "occluder"]:
			var result: Dictionary = results.get("%s_return" % role) if results.get("%s_return" % role) is Dictionary else {}
			check.call(assertions, "%s client showed the restored unlocked-but-closed gate before opening" % role,
				[result.get("gate_unlocked_before_open"), result.get("gate_opened_before_open")], [true, false])
			check.call(assertions, "%s client cleared its local gate collider after the accepted open" % role, result.get("gate_opened_after_open"), true)


static func _write(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
