extends SceneTree
## Mount a client PCK as data in an otherwise empty macOS inspector project.
## Never load a packaged scene or script while auditing its dependency boundary.

const MAX_FILES: int = 20000
const MAX_DEPTH: int = 64
const APPROVED_SERVER_DATA: String = "server/starting_town_hub_fixture.gd"
const NATIVE_EXTENSIONS: Array[String] = [
	"gdextension", "dll", "so", "dylib", "bundle", "framework", "exe", "pyd", "a", "lib", "o",
]

var _result: Dictionary = {
	"schema_version": 1,
	"check": "macos-client-package-boundary",
	"passed": false,
	"runtime_acceptance": false,
	"platform": "macos",
	"engine": "",
	"files": [],
	"failures": [],
	"client_files": 0,
}


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 4:
		push_error("Package inventory requires PCK, new evidence path, ownership manifest and engine version")
		quit(1)
		return
	var output_path: String = arguments[1]
	if not output_path.is_absolute_path() or FileAccess.file_exists(output_path):
		push_error("Package inventory evidence path must be absolute and unused")
		quit(1)
		return
	var engine: Dictionary = Engine.get_version_info()
	_result["engine"] = engine["string"]
	var engine_version: String = "%d.%d.%d" % [engine["major"], engine["minor"], engine["patch"]]
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[2]))
	if OS.get_name() != "macOS":
		_fail("macOS execution required")
	elif engine_version != arguments[3] or engine["status"] != "stable":
		_fail("Inspector engine is not the expected stable release")
	elif not _valid_manifest(manifest):
		_fail("Ownership manifest must contain only the exact reviewed server-data exception")
	elif ClassDB.class_exists("SQLite") or root.get_node_or_null("NetworkClient") != null or root.get_node_or_null("PlayerIdentity") != null:
		_fail("Inspector is not isolated from application autoloads and server extensions")
	elif not ProjectSettings.load_resource_pack(arguments[0]):
		_fail("Unable to mount PCK")
	else:
		_scan("res://", 0)
		if int(_result["client_files"]) == 0:
			_fail("PCK contains no client resources")
	_result["passed"] = (_result["failures"] as Array).is_empty()
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("Package inventory evidence write failed")
		quit(1)
		return
	output.store_string(JSON.stringify(_result, "\t"))
	output.close()
	quit(0 if _result["passed"] else 1)


func _valid_manifest(manifest: Variant) -> bool:
	if not manifest is Dictionary or not manifest.get("server_data_exceptions") is Array:
		return false
	var exceptions: Array = manifest["server_data_exceptions"]
	return exceptions.size() == 1 and exceptions[0] == APPROVED_SERVER_DATA


func _scan(path: String, depth: int) -> void:
	if depth > MAX_DEPTH:
		_fail("PCK inventory depth bound exceeded")
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		_fail("Unreadable resource directory: " + path)
		return
	directory.include_hidden = true
	for filename: String in directory.get_files():
		if (_result["files"] as Array).size() >= MAX_FILES:
			_fail("PCK inventory file bound exceeded")
			return
		var full_path: String = path.path_join(filename)
		var resource: String = full_path.trim_prefix("res://")
		(_result["files"] as Array).append(resource)
		if resource.begins_with("client/"):
			_result["client_files"] = int(_result["client_files"]) + 1
		var normalized: String = _normalize(resource)
		var forbidden_server: bool = normalized.begins_with("server/") and normalized != APPROVED_SERVER_DATA
		if forbidden_server or _forbidden_native(normalized) or _native_header(full_path):
			_fail("Forbidden or unapproved packaged dependency: " + resource)
	for child: String in directory.get_directories():
		var full_path: String = path.path_join(child)
		if _forbidden_native(_normalize(full_path.trim_prefix("res://"))):
			_fail("Forbidden or unapproved packaged directory: " + full_path.trim_prefix("res://"))
		_scan(full_path, depth + 1)


func _normalize(resource: String) -> String:
	var normalized: String = resource.to_lower().simplify_path().trim_suffix(".remap").trim_suffix(".uid")
	if normalized.ends_with(".gdc"):
		normalized = normalized.trim_suffix(".gdc") + ".gd"
	return normalized


func _forbidden_native(resource: String) -> bool:
	return resource.contains("sqlite") or resource.begins_with("native/") or resource.get_extension() in NATIVE_EXTENSIONS or resource == ".godot/extension_list.cfg"


func _native_header(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Unreadable packaged file: " + path.trim_prefix("res://"))
		return false
	var header: PackedByteArray = file.get_buffer(4)
	file.close()
	if header.size() < 4:
		return false
	# Reject renamed Mach-O/fat binaries, ELF libraries and Windows executables.
	var signature: String = header.hex_encode()
	return signature in ["feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca", "7f454c46"] or (header[0] == 0x4d and header[1] == 0x5a)


func _fail(description: String) -> void:
	(_result["failures"] as Array).append(description)
