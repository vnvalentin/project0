extends SceneTree
class_name MacOfflineProbe
## Runs as the temporary main-loop override from the app's built-in release PCK.
## HOME remains the caller's; the coordinator owns the fresh user-data directory.
## The temporary override suppresses automatic startup-scene instantiation.
## Require its exact binding before any account controls can read saved settings.
## This probe never authenticates or writes client settings.
## Evidence is written only to the caller's explicit, previously unused path.
## All captured values are allowlisted metadata or synthetic presentation data.
## Credential input values and identity/session properties are never sampled.

const PROBE_PATH: String = "res://scripts/macos/offline_probe.gd"
const NETWORK_PATH: String = "res://client/network_client.gd"
const VERSION_PATH: String = "res://shared/client_build_version.gd"
const SCHEMA_PATH: String = "res://shared/sector_blueprint_schema.gd"
const FALLBACK_PATH: String = "res://server/starting_town_hub_fixture.gd"
const PHYSICS_FRAME_BUDGET: int = 120
const TIMEOUT_MSEC: int = 45000
const INPUT_ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "attack", "jump", "dodge", "duck", "slide", "interact",
]

var _result: Dictionary = {
	"schema_version": 1,
	"probe": "macos-offline-client",
	"issue": 1353,
	"passed": false,
	"gameplay_acceptance": false,
	"paired_runtime_acceptance": false,
	"checks": {},
	"failures": [],
}
var _evidence_path: String = ""
var _expected_version: String = ""
var _expected_user_data: String = ""
var _started_msec: int = 0
var _finished: bool = false
var _account_gate: Control
var _gameplay: Node3D
var _geometry_root: Node3D


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			_evidence_path = argument.trim_prefix("--evidence=")
		elif argument.begins_with("--expected-version="):
			_expected_version = argument.trim_prefix("--expected-version=")
		elif argument.begins_with("--expected-user-data="):
			_expected_user_data = argument.trim_prefix("--expected-user-data=")
	if not _evidence_path.is_absolute_path() or FileAccess.file_exists(_evidence_path):
		push_error("Mac probe evidence path must be absolute and unused")
		quit(1)
		return
	if not _check_user_data_isolation():
		_finish()
		return
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_msec() - _started_msec > TIMEOUT_MSEC:
		_expect(false, "offline client probe exceeded its bounded runtime")
		_finish()
	return false


func _run() -> void:
	if _finished:
		return
	if not _check_user_data_isolation():
		_finish()
		return
	_clear_current_scene()
	_check_pack()
	_check_version()
	_check_rpc_contract()
	await _check_account_gate()
	await _check_geometry_readiness()
	await _check_input_and_character_sheet()
	_check_offline()
	await process_frame
	_finish()


func _check_user_data_isolation() -> bool:
	var matches: bool = _expected_user_data.is_absolute_path() and OS.get_user_data_dir().simplify_path() == _expected_user_data.simplify_path()
	_result["checks"]["user_data_isolation"] = {"matches_expected_directory": matches}
	_expect(matches, "runtime user-data directory matches the coordinator's fresh isolated directory")
	return matches


func _check_pack() -> void:
	var engine: Dictionary = Engine.get_version_info()
	_expect(OS.get_name() == "macOS", "native macOS runtime")
	_expect(engine["major"] == 4 and engine["minor"] == 7 and engine["patch"] == 2 and engine["status"] == "stable", "qualified 4.7.2 stable release engine")
	_expect(not OS.is_debug_build(), "release template rather than editor/debug runtime")
	var compiled: Dictionary = {}
	for path: String in [NETWORK_PATH, VERSION_PATH, SCHEMA_PATH, FALLBACK_PATH, PROBE_PATH, "res://client/player.gd", "res://client/account_gate.gd", "res://client/character_sheet_panel.gd"]:
		var script: GDScript = load(path) as GDScript
		compiled[path] = {"loaded": script != null, "has_source_code": script != null and script.has_source_code()}
		_expect(script != null, "%s loads from the pack" % path)
		_expect(script != null and not script.has_source_code(), "%s is compiled" % path)
	var player_identity_present: bool = root.get_node_or_null("PlayerIdentity") != null
	var network_present: bool = root.get_node_or_null("NetworkClient") != null
	var loose_project: bool = FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("project.godot"))
	_result["checks"]["pack"] = {
		"os": OS.get_name(),
		"engine": engine["string"],
		"debug_build": OS.is_debug_build(),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"probe_resource": get_script().resource_path,
		"player_identity_autoload": player_identity_present,
		"network_client_autoload": network_present,
		"loose_project_godot": loose_project,
		"sqlite_class_present": ClassDB.class_exists("SQLite"),
		"scripts": compiled,
	}
	_expect(ProjectSettings.get_setting("application/config/name", "") == "Project0", "Project0 PCK is mounted")
	_expect(ProjectSettings.get_setting("application/run/main_scene", "") == "", "startup scene is suppressed for the contained offline probe")
	_expect(player_identity_present and network_present, "both client autoloads are present")
	_expect(not loose_project, "no loose project.godot beside the app executable")
	_expect(not ClassDB.class_exists("SQLite"), "server SQLite extension is absent")
	_expect(not ResourceLoader.exists("res://server/server_main.gd"), "server runtime is absent from the app")
	_expect(get_script().resource_path == PROBE_PATH, "fixed compiled Mac probe is executing")


func _check_version() -> void:
	var script: Script = load(VERSION_PATH) as Script
	var actual: Variant = script.get_script_constant_map().get("CLIENT_BUILD_VERSION") if script != null else null
	_result["checks"]["version"] = {"expected": _expected_version, "actual": actual}
	_expect(not _expected_version.is_empty(), "expected client version is configured")
	_expect(actual is String and actual == _expected_version, "compiled client version equals package manifest")


func _check_rpc_contract() -> void:
	var network: Node = root.get_node_or_null("NetworkClient")
	var script: Script = network.get_script() as Script if network != null else null
	var method: Dictionary = {}
	if script != null:
		for candidate: Dictionary in script.get_script_method_list():
			if candidate["name"] == "receive_sector_blueprint":
				method = candidate
	var names: Array = []
	for argument: Dictionary in method.get("args", []):
		names.append(argument["name"])
	_result["checks"]["receive_sector_blueprint"] = {"found": not method.is_empty(), "arg_names": names}
	_expect(names == ["blueprint", "ingress", "trace"], "packaged sector-presentation RPC retains its three-argument contract")


func _check_account_gate() -> void:
	var scene: PackedScene = load("res://client/account_gate.tscn") as PackedScene
	_expect(scene != null, "account gate scene loads")
	if scene == null:
		return
	_account_gate = scene.instantiate() as Control
	root.add_child(_account_gate)
	await process_frame
	var username: LineEdit = _account_gate.get_node_or_null("VBoxContainer/UsernameInput") as LineEdit
	var password: LineEdit = _account_gate.get_node_or_null("VBoxContainer/PasswordInput") as LineEdit
	var login: Button = _account_gate.get_node_or_null("VBoxContainer/ButtonContainer/LoginButton") as Button
	var register: Button = _account_gate.get_node_or_null("VBoxContainer/ButtonContainer/RegisterButton") as Button
	var settings: Button = _account_gate.get_node_or_null("VBoxContainer/SettingsButton") as Button
	var panel: Control = _account_gate.get_node_or_null("VBoxContainer/SettingsPanel") as Control
	var password_is_secret: bool = password != null and password.secret
	_expect(username != null and password != null and login != null and register != null and settings != null and panel != null, "startup account controls instantiate")
	_expect(password_is_secret, "password input uses secret rendering")
	var initially_hidden: bool = panel != null and not panel.visible
	var opens: bool = false
	var closes: bool = false
	if settings != null and panel != null:
		settings.pressed.emit()
		await process_frame
		opens = panel.visible
		settings.pressed.emit()
		await process_frame
		closes = not panel.visible
	_expect(initially_hidden and opens and closes, "account Settings button opens and closes its panel")
	_result["checks"]["account_gate"] = {
		"instantiated": true,
		"credential_controls_present": username != null and password != null,
		"password_is_secret": password_is_secret,
		"settings_opens": opens,
		"settings_closes": closes,
		"credential_values_captured": false,
		"authentication_attempted": false,
	}
	_account_gate.free()
	_account_gate = null
	_check_offline()


func _check_geometry_readiness() -> void:
	var network_script: Script = load(NETWORK_PATH) as Script
	var schema: Script = load(SCHEMA_PATH) as Script
	if network_script == null or schema == null:
		_expect(false, "geometry probe dependencies load")
		return
	var valid: String = schema.get_script_constant_map()["OUTCOME_VALID"]
	var blueprint: Dictionary = {
		"schema_version": 2,
		"sector_id": "macos-offline-safe",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}, {"x": 1, "y": 0, "kind": "floor"}, {"x": 2, "y": 0, "kind": "floor"}],
		"structures": [],
	}
	_geometry_root = Node3D.new()
	root.add_child(_geometry_root)
	var safe_parent: Node3D = Node3D.new()
	var unsafe_parent: Node3D = Node3D.new()
	_geometry_root.add_child(safe_parent)
	_geometry_root.add_child(unsafe_parent)
	var safe: Dictionary = network_script.render_sector_blueprint(blueprint, safe_parent, Vector3.ZERO, Vector3(2.0, 0.0, 0.0))
	var unsafe: Dictionary = network_script.render_sector_blueprint(blueprint, unsafe_parent, Vector3(100.0, 0.0, 100.0), Vector3(2.0, 0.0, 0.0))
	var frames: int = 0
	while frames < PHYSICS_FRAME_BUDGET and not (safe.get("geometry_assembly_completed", false) and unsafe.get("geometry_assembly_completed", false)):
		await physics_frame
		frames += 1
	_result["checks"]["geometry_readiness"] = {"physics_frames_waited": frames, "safe": _summary(safe), "unsafe": _summary(unsafe)}
	_expect(safe.get("outcome", "") == valid, "safe sector blueprint passes schema validation")
	_expect(safe.get("geometry_assembly_completed", false) and safe.get("navigation_ready", false), "safe sector completes actual geometry and navigation")
	_expect((safe.get("path", PackedVector3Array()) as PackedVector3Array).size() > 0, "safe ingress reaches its target")
	_expect(unsafe.get("outcome", "") == "fallback_selected" and unsafe.get("fallback_sector_id", "") == "starting_town_hub", "unsafe ingress selects the deterministic town fallback")
	_expect(unsafe.get("geometry_assembly_completed", false) and unsafe.get("navigation_ready", false), "fallback completes actual geometry and navigation")
	_expect((unsafe.get("path", PackedVector3Array()) as PackedVector3Array).size() > 0 and unsafe_parent.get_child_count() > 0, "fallback renders reachable geometry")
	_geometry_root.free()
	_geometry_root = null
	await process_frame


func _check_input_and_character_sheet() -> void:
	var bindings: Dictionary = {}
	for action: String in INPUT_ACTIONS:
		var present: bool = InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty()
		bindings[action] = present
		_expect(present, "configured input action: " + action)
	var scene: PackedScene = load("res://client/gameplay.tscn") as PackedScene
	_expect(scene != null, "gameplay scene loads offline")
	if scene == null:
		return
	_gameplay = scene.instantiate() as Node3D
	# ConnectionStatus normally reconnects on gameplay entry. Remove that one
	# bootstrap node while detached, before _ready can open any network peer.
	var bootstrap: Node = _gameplay.get_node_or_null("UI/ConnectionStatus")
	_expect(bootstrap != null, "gameplay network bootstrap is identified before startup")
	if bootstrap == null:
		_gameplay.free()
		_gameplay = null
		return
	bootstrap.free()
	root.add_child(_gameplay)
	var player: CharacterBody3D = _gameplay.get_node_or_null("Player") as CharacterBody3D
	var toggle: Button = _gameplay.get_node_or_null("UI/CharacterSheetToggle") as Button
	var sheet: Control = _gameplay.get_node_or_null("UI/CharacterSheetPanel") as Control
	_expect(player != null and toggle != null and sheet != null, "real Player and Character Sheet controls instantiate")
	if player == null or toggle == null or sheet == null:
		return
	for frame: int in range(6):
		await physics_frame
	var start: Vector3 = player.position
	Input.action_press("move_right")
	var right_intent: Vector2 = player.call("get_planar_input")
	for frame: int in range(12):
		await physics_frame
	Input.action_release("move_right")
	var delta_x: float = player.position.x - start.x
	_expect(right_intent == Vector2.RIGHT and delta_x > 0.05, "right input produces disposable client movement")
	Input.action_press("duck")
	var duck_mode: String = String(player.call("get_locomotion_mode", Vector2.ZERO))
	Input.action_release("duck")
	Input.action_press("slide")
	var slide_mode: String = String(player.call("get_locomotion_mode", Vector2.RIGHT))
	Input.action_release("slide")
	var locomotion: Script = load("res://shared/locomotion_contract.gd") as Script
	var modes: Dictionary = locomotion.get_script_constant_map() if locomotion != null else {}
	_expect(duck_mode == modes.get("MODE_DUCK", "") and slide_mode == modes.get("MODE_SLIDE", ""), "duck and moving-slide input reach the actual Player seam")
	var hidden_before: bool = not sheet.visible
	toggle.pressed.emit()
	await process_frame
	var opened: bool = sheet.visible
	var missing_stats: bool = sheet.call("displayed_value", "STR") == "—" and sheet.call("displayed_value", "BaseHP") == "—"
	toggle.pressed.emit()
	await process_frame
	var closed: bool = not sheet.visible
	_expect(hidden_before and opened and closed, "Character Sheet button opens and closes the real panel")
	_expect(missing_stats, "offline Character Sheet does not invent authoritative stats")
	_result["checks"]["input_and_character_sheet"] = {
		"bindings": bindings,
		"gameplay_connection_bootstrap_removed_before_ready": true,
		"right_intent": right_intent == Vector2.RIGHT,
		"predicted_right_distance": delta_x,
		"duck_mode": duck_mode,
		"slide_mode": slide_mode,
		"sheet_opens": opened,
		"sheet_closes": closed,
		"sheet_uses_missing_authoritative_values": missing_stats,
		"prediction_is_authoritative": false,
	}
	_gameplay.free()
	_gameplay = null
	await process_frame


func _check_offline() -> void:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	_result["checks"]["offline"] = {"multiplayer_peer": peer.get_class() if peer != null else "null", "authentication_attempted": false}
	_expect(peer == null or peer is OfflineMultiplayerPeer, "probe opened no network peer")


func _summary(result: Dictionary) -> Dictionary:
	return {
		"outcome": result.get("outcome", ""),
		"fallback_sector_id": result.get("fallback_sector_id", ""),
		"tile_count": result.get("tile_count", 0),
		"structure_count": result.get("structure_count", 0),
		"geometry_assembly_completed": result.get("geometry_assembly_completed", false),
		"navigation_ready": result.get("navigation_ready", false),
		"path_points": (result.get("path", PackedVector3Array()) as PackedVector3Array).size(),
	}


func _expect(condition: bool, description: String) -> void:
	if not condition:
		(_result["failures"] as Array).append(description)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for action: String in INPUT_ACTIONS:
		Input.action_release(action)
	if is_instance_valid(_account_gate):
		_account_gate.free()
	if is_instance_valid(_gameplay):
		_gameplay.free()
	if is_instance_valid(_geometry_root):
		_geometry_root.free()
	_clear_current_scene()
	_result["elapsed_msec"] = Time.get_ticks_msec() - _started_msec
	_result["passed"] = (_result["failures"] as Array).is_empty()
	var output: FileAccess = FileAccess.open(_evidence_path, FileAccess.WRITE)
	if output == null:
		push_error("Mac probe evidence write failed")
		quit(1)
		return
	output.store_string(JSON.stringify(_result, "\t"))
	output.close()
	print("Mac offline client probe: passed=%s" % _result["passed"])
	quit(0 if _result["passed"] else 1)


func _clear_current_scene() -> void:
	if current_scene != null:
		var startup_scene: Node = current_scene
		current_scene = null
		startup_scene.free()
