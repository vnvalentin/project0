extends Node

const NETWORK_CLIENT_PATH: String = "res://client/network_client.gd"
const VERSION_PATH: String = "res://shared/client_build_version.gd"
const SCHEMA_PATH: String = "res://shared/sector_blueprint_schema.gd"
const FALLBACK_FIXTURE_PATH: String = "res://server/starting_town_hub_fixture.gd"
const PROBE_PATH: String = "res://client/standalone_package_probe.gd"
const PHYSICS_FRAME_BUDGET: int = 120

var _result: Dictionary = {
	"probe": "standalone_package_probe",
	"issue": 1213,
	"passed": false,
	"gameplay_acceptance": false,
	"checks": {},
	"failures": [],
}
var _geometry_root: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_pack()
	_check_version(OS.get_environment("PROJECT0_PACKAGE_PROBE_EXPECTED_VERSION"))
	_check_rpc_contract()
	await _check_geometry_readiness()
	_check_offline()
	await _finish(OS.get_environment("PROJECT0_PACKAGE_PROBE_EVIDENCE"))


func _check_pack() -> void:
	var executable_dir: String = OS.get_executable_path().get_base_dir()
	var engine: Dictionary = Engine.get_version_info()
	_expect(engine["major"] == 4 and engine["minor"] == 7 and engine["patch"] == 2 and engine["status"] == "stable", "qualified 4.7.2 stable release engine")
	_expect(not OS.is_debug_build(), "release template, not a debug or editor binary")
	var compiled: Dictionary = {}
	for path: String in [NETWORK_CLIENT_PATH, VERSION_PATH, SCHEMA_PATH, FALLBACK_FIXTURE_PATH, PROBE_PATH]:
		var script: GDScript = load(path) as GDScript
		compiled[path] = {
			"loaded": script != null,
			"has_source_code": script != null and script.has_source_code(),
			"gdc_in_pack": FileAccess.file_exists(path.get_basename() + ".gdc"),
		}
		_expect(script != null, "%s loads from the pack" % path)
		_expect(script != null and not script.has_source_code(), "%s is compiled, not external source" % path)
	_result["checks"]["pack"] = {
		"executable": OS.get_executable_path(),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"loose_project_godot": FileAccess.file_exists(executable_dir.path_join("project.godot")),
		"network_client_autoload": get_tree().root.get_node_or_null("NetworkClient") != null,
		"engine_version": engine["string"],
		"debug_build": OS.is_debug_build(),
		"probe_resource": get_script().resource_path,
		"scripts": compiled,
	}
	_expect(_result["checks"]["pack"]["project_name"] == "Project0", "adjacent Project0.pck is mounted")
	_expect(not _result["checks"]["pack"]["loose_project_godot"], "no loose project.godot beside the EXE")
	_expect(_result["checks"]["pack"]["network_client_autoload"], "NetworkClient autoload is present")
	_expect(not ResourceLoader.exists("res://server/server_main.gd"), "authoritative server runtime is not packaged")
	_expect(get_script().resource_path == PROBE_PATH, "fixed packaged probe is running")


func _check_version(expected: String) -> void:
	var script: Script = load(VERSION_PATH) as Script
	var actual: Variant = null
	if script != null:
		actual = script.get_script_constant_map().get("CLIENT_BUILD_VERSION")
	_result["checks"]["version"] = {"expected": expected, "actual": actual}
	_expect(not expected.is_empty(), "expected version is configured")
	_expect(actual is String and actual == expected, "CLIENT_BUILD_VERSION equals manifest version")


func _check_rpc_contract() -> void:
	var network: Node = get_tree().root.get_node_or_null("NetworkClient")
	var script: Script = network.get_script() as Script if network != null else null
	var method: Dictionary = {}
	if script != null:
		for candidate: Dictionary in script.get_script_method_list():
			if candidate["name"] == "receive_sector_blueprint":
				method = candidate
	var names: Array = []
	for argument: Dictionary in method.get("args", []):
		names.append(argument["name"])
	_result["checks"]["receive_sector_blueprint"] = {
		"found": not method.is_empty(),
		"arg_count": names.size(),
		"arg_names": names,
		"default_arg_count": (method.get("default_args", []) as Array).size(),
	}
	_expect(not method.is_empty(), "receive_sector_blueprint exists on the packaged NetworkClient")
	_expect(names == ["blueprint", "ingress", "trace"], "receive_sector_blueprint has the expected three arguments")


func _check_geometry_readiness() -> void:
	var network_script: Script = load(NETWORK_CLIENT_PATH) as Script
	var valid: String = (load(SCHEMA_PATH) as Script).get_script_constant_map()["OUTCOME_VALID"]
	var blueprint: Dictionary = {
		"schema_version": 2,
		"sector_id": "issue-1001-safe",
		"origin": {"x": 0, "y": 0},
		"tiles": [
			{"x": 0, "y": 0, "kind": "floor"},
			{"x": 1, "y": 0, "kind": "floor"},
			{"x": 2, "y": 0, "kind": "floor"},
		],
		"structures": [],
	}
	_geometry_root = Node3D.new()
	get_tree().root.add_child(_geometry_root)
	var safe_parent: Node3D = Node3D.new()
	var unsafe_parent: Node3D = Node3D.new()
	_geometry_root.add_child(safe_parent)
	_geometry_root.add_child(unsafe_parent)
	var safe: Dictionary = network_script.render_sector_blueprint(blueprint, safe_parent, Vector3.ZERO, Vector3(2.0, 0.0, 0.0))
	var unsafe: Dictionary = network_script.render_sector_blueprint(blueprint, unsafe_parent, Vector3(100.0, 0.0, 100.0), Vector3(2.0, 0.0, 0.0))
	var frames: int = 0
	while frames < PHYSICS_FRAME_BUDGET and not (safe["geometry_assembly_completed"] and unsafe["geometry_assembly_completed"]):
		await get_tree().physics_frame
		frames += 1
	_result["checks"]["geometry_readiness"] = {
		"physics_frames_waited": frames,
		"fallback_fixture_in_pack": ResourceLoader.exists(FALLBACK_FIXTURE_PATH),
		"safe": _summary(safe),
		"unsafe": _summary(unsafe),
		"unsafe_parent_children": unsafe_parent.get_child_count(),
	}
	_expect(safe["outcome"] == valid, "safe blueprint is schema-valid")
	_expect(safe["geometry_assembly_completed"] and safe["navigation_ready"], "safe blueprint completes assembly and navigation")
	_expect((safe["path"] as PackedVector3Array).size() > 0, "safe ingress reaches the target")
	_expect(unsafe["outcome"] == "fallback_selected", "unsafe ingress selects the deterministic fallback")
	_expect(unsafe.get("fallback_sector_id", "") == "starting_town_hub", "unsafe ingress selects the starting-town fallback")
	_expect(unsafe["geometry_assembly_completed"] and unsafe["navigation_ready"], "fallback completes assembly and navigation")
	_expect((unsafe["path"] as PackedVector3Array).size() > 0, "fallback ingress reaches its target")
	_expect(unsafe_parent.get_child_count() > 0, "unsafe ingress renders the fallback")


func _check_offline() -> void:
	var peer: MultiplayerPeer = get_tree().root.multiplayer.multiplayer_peer
	_result["checks"]["offline"] = {"multiplayer_peer": peer.get_class() if peer != null else "null"}
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


func _finish(evidence_path: String) -> void:
	await get_tree().process_frame
	if _geometry_root != null:
		_geometry_root.queue_free()
		_geometry_root = null
	await get_tree().process_frame
	_result["passed"] = (_result["failures"] as Array).is_empty()
	var text: String = JSON.stringify(_result, "\t")
	if evidence_path.is_empty() or FileAccess.file_exists(evidence_path):
		push_error("Package probe evidence path is missing or already exists")
		get_tree().quit(1)
		return
	var output: FileAccess = FileAccess.open(evidence_path, FileAccess.WRITE)
	if output == null:
		push_error("Package probe evidence write failed")
		get_tree().quit(1)
		return
	output.store_string(text)
	output.close()
	print(text)
	get_tree().quit(0 if _result["passed"] else 1)