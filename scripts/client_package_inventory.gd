extends SceneTree


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 4:
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[2]))
	var engine: Dictionary = Engine.get_version_info()
	var engine_version: String = "%d.%d.%d" % [engine["major"], engine["minor"], engine["patch"]]
	var result: Dictionary = {
		"passed": false, "engine": Engine.get_version_info()["string"],
		"files": [], "failures": [], "client_files": 0,
	}
	if engine_version != arguments[3]:
		result["failures"].append("Inspector engine mismatch: expected %s, actual %s" % [arguments[3], engine_version])
	elif not manifest is Dictionary or not manifest.get("server_data_exceptions") is Array:
		result["failures"].append("Ownership manifest is invalid")
	elif ClassDB.class_exists("SQLite"):
		result["failures"].append("Inspector environment already contains server-only SQLite")
	elif not ProjectSettings.load_resource_pack(arguments[0]):
		result["failures"].append("Unable to mount PCK")
	else:
		_scan("res://", manifest["server_data_exceptions"], result, 0)
		if result["client_files"] == 0:
			result["failures"].append("PCK contains no client resources")
	result["passed"] = result["failures"].is_empty()
	var output: FileAccess = FileAccess.open(arguments[1], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	quit(0 if result["passed"] else 1)


func _scan(path: String, exceptions: Array, result: Dictionary, depth: int) -> void:
	if depth > 64 or result["files"].size() > 20000:
		result["failures"].append("PCK inventory bound exceeded")
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		result["failures"].append("Unreadable resource directory: " + path)
		return
	directory.include_hidden = true
	for filename: String in directory.get_files():
		if result["files"].size() >= 20000:
			result["failures"].append("PCK inventory bound exceeded")
			return
		var resource: String = path.path_join(filename).trim_prefix("res://")
		result["files"].append(resource)
		if resource.begins_with("client/"):
			result["client_files"] += 1
		var normalized: String = resource.to_lower().simplify_path().trim_suffix(".remap").trim_suffix(".uid")
		if normalized.ends_with(".gdc"):
			normalized = normalized.trim_suffix(".gdc") + ".gd"
		var forbidden_server: bool = normalized.begins_with("server/") and normalized not in exceptions
		var unknown_native: bool = normalized.get_extension() in ["gdextension", "dll", "so", "dylib"]
		if forbidden_server or normalized.contains("sqlite") or normalized.begins_with("native/") or unknown_native:
			result["failures"].append("Forbidden or unapproved packaged dependency: " + resource)
	for child: String in directory.get_directories():
		_scan(path.path_join(child), exceptions, result, depth + 1)