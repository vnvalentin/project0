extends SceneTree
## Tiny standalone probe used only by scripts/test_lan_config.gd to observe
## NetworkConfig.resolve_client_target_host() from a real second OS process
## (a process's own command-line arguments are only visible to itself).
## Not part of the client or server runtime path.
## Run with: godot --headless --path . -s scripts/probe_client_target_host.gd -- --server-host=<host>

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")


func _initialize() -> void:
	print("RESOLVED:%s" % NetworkConfigScript.resolve_client_target_host())
	quit(0)
