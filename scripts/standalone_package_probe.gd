extends SceneTree
## #1213: headless probe run by scripts/verify_standalone_package.ps1 inside the
## extracted packaged Project0.exe (never the editor). Every res:// script it
## touches comes from the mounted Project0.pck. It asserts the pack is mounted
## with compiled scripts, CLIENT_BUILD_VERSION equals the manifest version,
## receive_sector_blueprint keeps its three-argument RPC contract, and packaged
## geometry readiness matches tests/integration/test_blueprint_replication.gd
## (experiment 1001 safe ingress and unsafe-ingress fallback). It never connects
## anywhere. Passing is a packaged-contract check, not gameplay acceptance.

const NETWORK_CLIENT_PATH: String = "res://client/network_client.gd"
const VERSION_PATH: String = "res://shared/client_build_version.gd"
const SCHEMA_PATH: String = "res://shared/sector_blueprint_schema.gd"
const FALLBACK_FIXTURE_PATH: String = "res://server/starting_town_hub_fixture.gd"
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


func _initialize() -> void:
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
	var compiled: Dictionary = {}
	for path: String in [NETWORK_CLIENT_PATH, VERSION_PATH, SCHEMA_PATH, FALLBACK_FIXTURE_PATH]:
		var script: GDScript = load(path) as GDScript
		compiled[path] = {
			"loaded": script != null,
			"has_source_code": script != null and script.has_source_code(),
			"gdc_in_pack": FileAccess.file_exists(path.get_basename() + ".gdc"),
		}
		_expect(script != null, "%s loads from the pack" % path)
		_expect(script != null and not script.has_source_code(), "%s is a compiled (token) script, not source" % path)
	_result["checks"]["pack"] = {
		"executable": OS.get_executable_path(),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"loose_project_godot": FileAccess.file_exists(executable_dir.path_join("project.godot")),
		"network_client_autoload": root.get_node_or_null("NetworkClient") != null,
		"engine_version": Engine.get_version_info()["string"],
		"debug_build": OS.is_debug_build(),
		"scripts": compiled,
	}
	_expect(_result["checks"]["pack"]["project_name"] == "Project0", "adjacent Project0.pck is mounted")
	_expect(not _result["checks"]["pack"]["loose_project_godot"], "no loose project.godot beside the EXE")
	_expect(_result["checks"]["pack"]["network_client_autoload"], "NetworkClient autoload is present")
	_expect(not ResourceLoader.exists("res://server/server_main.gd"), "authoritative server runtime is not packaged")


func _check_version(expected: String) -> void:
	var script: Script = load(VERSION_PATH) as Script
	var actual: Variant = null
	if script != null:
		actual = script.get_script_constant_map().get("CLIENT_BUILD_VERSION")
	_result["checks"]["version"] = {"expected": expected, "actual": actual}
	_expect(not expected.is_empty(), "expected version is configured")
	_expect(actual is String and actual == expected, "CLIENT_BUILD_VERSION equals manifest version")


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
	var rpc_config: Variant = null
	if script != null and script.has_method("get_rpc_config"):
		rpc_config = (script.get_rpc_config() as Dictionary).get("receive_sector_blueprint")
	_result["checks"]["receive_sector_blueprint"] = {
		"found": not method.is_empty(),
		"arg_count": names.size(),
		"arg_names": names,
		"default_arg_count": (method.get("default_args", []) as Array).size(),
		"rpc_config": rpc_config,
	}
	_expect(not method.is_empty(), "receive_sector_blueprint exists on the packaged NetworkClient")
	_expect(names.size() == 3, "receive_sector_blueprint has 3 args")
	_expect(rpc_config == null or rpc_config is Dictionary, "receive_sector_blueprint RPC config is readable")


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
	root.add_child(_geometry_root)
	var safe_parent: Node3D = Node3D.new()
	var unsafe_parent: Node3D = Node3D.new()
	_geometry_root.add_child(safe_parent)
	_geometry_root.add_child(unsafe_parent)
	var fallback_in_pack: bool = ResourceLoader.exists(FALLBACK_FIXTURE_PATH)
	var safe: Dictionary = network_script.render_sector_blueprint(blueprint, safe_parent, Vector3.ZERO, Vector3(2.0, 0.0, 0.0))
	var unsafe: Dictionary = network_script.render_sector_blueprint(blueprint, unsafe_parent, Vector3(100.0, 0.0, 100.0), Vector3(2.0, 0.0, 0.0))
	var frames: int = 0
	while frames < PHYSICS_FRAME_BUDGET and not (safe["geometry_assembly_completed"] and unsafe["geometry_assembly_completed"]):
		await physics_frame
		frames += 1
	_result["checks"]["geometry_readiness"] = {
		"physics_frames_waited": frames,
		"fallback_fixture_in_pack": fallback_in_pack,
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
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
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
	await process_frame
	if _geometry_root != null:
		for area: Area3D in _geometry_root.find_children("*", "Area3D", true, false):
			area.monitoring = false
			area.monitorable = false
		await physics_frame
		await physics_frame
		await process_frame
		_geometry_root.queue_free()
		_geometry_root = null
	await process_frame
	_result["passed"] = (_result["failures"] as Array).is_empty()
	var text: String = JSON.stringify(_result, "\t")
	if evidence_path.is_empty():
		push_error("Package probe evidence path is not configured")
		quit(1)
		return
	var output: FileAccess = FileAccess.open(evidence_path, FileAccess.WRITE)
	if output == null:
		push_error("Package probe evidence write failed")
		quit(1)
		return
	output.store_string(text)
	output.close()
	print(text)
	quit(0 if _result["passed"] else 1)
