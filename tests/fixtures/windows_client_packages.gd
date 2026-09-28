extends SceneTree


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() == 2 or arguments.size() == 3:
		var mode: String = arguments[2] if arguments.size() == 3 else ""
		quit(_pack_export(arguments[0], arguments[1], mode))
		return
	if arguments.size() != 1:
		quit(1)
		return
	var root: String = arguments[0]
	var source: String = root.path_join("fixture.txt")
	var output: FileAccess = FileAccess.open(source, FileAccess.WRITE)
	output.store_string("extends RefCounted\n")
	output.close()
	var cases: Dictionary = {
		"valid": ["res://client/player.gd"],
		"fallback": ["res://client/player.gd", "res://server/starting_town_hub_fixture.gd"],
		"persistence": ["res://client/player.gd", "res://server/canon_repository.gd"],
		"compiled_persistence": ["res://client/player.gd", "res://server/canon_repository.gd.remap"],
		"sqlite": ["res://client/player.gd", "res://addons/godot-sqlite/bin/gdsqlite.dll"],
		"unknown_native": ["res://client/player.gd", "res://addons/other/store.dll"],
		"native_remap": ["res://client/player.gd", "res://addons/other/store.gdextension.remap"],
		"oversized": ["res://client/player.gd"],
		"no_client": ["res://shared/value.gd"],
	}
	for case_name: String in cases:
		var packer: PCKPacker = PCKPacker.new()
		if packer.pck_start(root.path_join(case_name + ".pck")) != OK:
			quit(1)
			return
		for resource_path: String in cases[case_name]:
			if packer.add_file(resource_path, source) != OK:
				quit(1)
				return
		if case_name == "oversized":
			for index: int in range(20000):
				if packer.add_file("res://client/value_%d.gd" % index, source) != OK:
					quit(1)
					return
		if packer.flush() != OK:
			quit(1)
			return
	quit(0)


func _pack_export(source_root: String, destination: String, mode: String) -> int:
	var source: String = source_root.path_join("shared/client_build_version.gd")
	var packer: PCKPacker = PCKPacker.new()
	if packer.pck_start(destination) != OK:
		return 1
	for resource: String in ["res://client/player.gd", "res://shared/client_build_version.gd"]:
		if packer.add_file(resource, source) != OK:
			return 1
	if mode == "persistence" and packer.add_file("res://server/canon_repository.gd", source) != OK:
		return 1
	return 0 if packer.flush() == OK else 1