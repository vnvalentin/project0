extends SceneTree
## Bounded native UI smoke runner for Slice 044.
## Loads each client gate/gameplay scene, verifies its public control paths, and
## writes screenshots plus machine-readable evidence without contacting a server.

const RESULT_PATH: String = "res://build/validation/client-ui-summary.json"
const SCREENSHOT_DIR: String = "res://build/validation/ui"

var _results: Array[Dictionary] = []
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	await _check_scene(
		"account_gate",
		"res://client/account_gate.tscn",
		["VBoxContainer/UsernameInput", "VBoxContainer/PasswordInput", "VBoxContainer/HostInput", "VBoxContainer/ButtonContainer/LoginButton", "VBoxContainer/ButtonContainer/RegisterButton"]
	)
	await _check_scene(
		"character_gate",
		"res://client/character_gate.tscn",
		["VBoxContainer/CharacterList", "VBoxContainer/ButtonContainer/SelectButton", "VBoxContainer/ButtonContainer/CreateButton", "VBoxContainer/ButtonContainer/DeleteButton", "CreateCharacterDialog"]
	)
	await _check_scene(
		"gameplay",
		"res://client/gameplay.tscn",
		["Player", "UI/ConnectionStatus", "UI/LogoutButton", "FlatPlane"]
	)

	var summary: Dictionary = {
		"runner": "client-ui-smoke",
		"status": "passed" if _failures.is_empty() else "failed",
		"scenes_expected": 3,
		"scenes_checked": _results.size(),
		"failures": _failures,
		"scenes": _results,
	}
	var result_file: FileAccess = FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file == null:
		push_error("Could not write UI smoke result: %s" % RESULT_PATH)
		quit(1)
		return
	result_file.store_string(JSON.stringify(summary, "  "))
	result_file.flush()
	result_file.close()
	print(JSON.stringify(summary))
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _check_scene(scene_name: String, scene_path: String, required_paths: Array[String]) -> void:
	var packed_scene: PackedScene = load(scene_path)
	if packed_scene == null:
		_failures.append("%s: scene failed to load" % scene_name)
		return
	var instance: Node = packed_scene.instantiate()
	root.add_child(instance)
	current_scene = instance
	await process_frame
	await process_frame

	var missing: Array[String] = []
	for required_path: String in required_paths:
		if instance.get_node_or_null(required_path) == null:
			missing.append(required_path)
	if not missing.is_empty():
		_failures.append("%s: missing %s" % [scene_name, ", ".join(missing)])

	var screenshot_path: String = ""
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		var viewport_texture: Texture2D = root.get_viewport().get_texture()
		if viewport_texture != null:
			image = viewport_texture.get_image()
	if image != null:
		screenshot_path = "%s/%s.png" % [SCREENSHOT_DIR, scene_name]
		image.save_png(ProjectSettings.globalize_path(screenshot_path))
	_results.append({
		"scene": scene_name,
		"required_paths": required_paths.size() - missing.size(),
		"missing_paths": missing,
		"screenshot": screenshot_path,
	})
	instance.queue_free()
	await process_frame
