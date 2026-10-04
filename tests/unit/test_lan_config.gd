extends GutTest
## GUT migration of Slice 003's LAN configuration smoke test.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const NETWORK_ENVIRONMENT_VARIABLES: Array[String] = [
	NetworkConfigScript.BIND_ADDRESS_ENV_VAR,
	NetworkConfigScript.TARGET_HOST_ENV_VAR,
	NetworkConfigScript.SERVER_PORT_ENV_VAR,
]


func test_defaults_to_localhost_with_no_override() -> void:
	var original_environment: Dictionary = _capture_network_environment()
	for variable: String in NETWORK_ENVIRONMENT_VARIABLES:
		OS.unset_environment(variable)

	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()
	var target_host: String = NetworkConfigScript.resolve_client_target_host()
	var server_port: int = NetworkConfigScript.resolve_server_port()
	_restore_network_environment(original_environment)

	assert_true(_capture_network_environment() == original_environment, "default check restores inherited environment")
	assert_eq(bind_address, NetworkConfigScript.SERVER_ADDRESS, "server bind address defaults to localhost")
	assert_eq(
		target_host,
		NetworkConfigScript.DEFAULT_TARGET_HOST,
		"client target host defaults to WAN default target host"
	)
	assert_eq(server_port, NetworkConfigScript.SERVER_PORT, "server port defaults to the shared default")


func test_empty_network_environment_overrides_fall_back_to_defaults() -> void:
	var original_environment: Dictionary = _capture_network_environment()
	for variable: String in NETWORK_ENVIRONMENT_VARIABLES:
		OS.set_environment(variable, "")

	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()
	var target_host: String = NetworkConfigScript.resolve_client_target_host()
	var server_port: int = NetworkConfigScript.resolve_server_port()
	_restore_network_environment(original_environment)

	assert_true(_capture_network_environment() == original_environment, "empty-override check restores inherited environment")
	assert_eq(bind_address, NetworkConfigScript.SERVER_ADDRESS)
	assert_eq(target_host, NetworkConfigScript.DEFAULT_TARGET_HOST)
	assert_eq(server_port, NetworkConfigScript.SERVER_PORT)


func test_cli_arg_overrides_bind_address_on_real_server() -> void:
	var port: int = _reserve_ephemeral_port()
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
		"--quit-after", "1",
		"--", "--server-bind-address=127.0.0.1", "--server-port=%d" % port,
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "bind-address server process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"Server listening on 127.0.0.1:%d" % port,
		"server honors --server-bind-address and --server-port"
	)


func test_cli_arg_overrides_target_host() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "scripts/probe_client_target_host.gd",
		"--", "--server-host=192.168.1.50",
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "target-host probe process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"RESOLVED:192.168.1.50",
		"client honors --server-host"
	)


func test_cli_arg_binds_server_to_wan_wildcard_address() -> void:
	var port: int = _reserve_ephemeral_port()
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
		"--quit-after", "1",
		"--", "--server-bind-address=0.0.0.0", "--server-port=%d" % port,
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "WAN wildcard-bind server process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"Server listening on 0.0.0.0:%d" % port,
		"server honors --server-bind-address=0.0.0.0 and --server-port for WAN binding"
	)


func test_cli_arg_overrides_target_host_for_wan_hostname() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "scripts/probe_client_target_host.gd",
		"--", "--server-host=play.example.com",
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "target-host probe process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"RESOLVED:play.example.com",
		"client honors --server-host for a WAN domain name"
	)


func test_cli_arg_overrides_target_host_for_wan_public_ip() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "scripts/probe_client_target_host.gd",
		"--", "--server-host=203.0.113.42",
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "target-host probe process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"RESOLVED:203.0.113.42",
		"client honors --server-host for a WAN public IP"
	)


func test_server_fails_closed_on_unbindable_address() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
		"--quit-after", "1",
		"--", "--server-bind-address=203.0.113.5",
	], output, true)

	var printed: String = "\n".join(output)
	assert_ne(exit_code, 0, "server fails closed on an unbindable address")
	assert_false(
		printed.contains("Server listening"),
		"server does not report listening on an unbindable address"
	)


## Reserves an OS-assigned free UDP port so a spawned test server never collides
## with a game server already bound to the shared default port (DT-007).
func _reserve_ephemeral_port() -> int:
	var probe := PacketPeerUDP.new()
	assert_eq(probe.bind(0, "127.0.0.1"), OK, "reserved an ephemeral UDP port")
	var port: int = probe.get_local_port()
	probe.close()
	return port


func test_server_port_env_override_and_invalid_fallback() -> void:
	var original_environment: Dictionary = _capture_network_environment()
	OS.set_environment(NetworkConfigScript.BIND_ADDRESS_ENV_VAR, "0.0.0.0")
	OS.set_environment(NetworkConfigScript.TARGET_HOST_ENV_VAR, "play.example.com")
	OS.set_environment(NetworkConfigScript.SERVER_PORT_ENV_VAR, "40000")
	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()
	var target_host: String = NetworkConfigScript.resolve_client_target_host()
	var server_port: int = NetworkConfigScript.resolve_server_port()
	OS.set_environment(NetworkConfigScript.SERVER_PORT_ENV_VAR, "not-a-port")
	var invalid_server_port: int = NetworkConfigScript.resolve_server_port()
	OS.set_environment(NetworkConfigScript.SERVER_PORT_ENV_VAR, "70000")
	var out_of_range_server_port: int = NetworkConfigScript.resolve_server_port()
	_restore_network_environment(original_environment)

	assert_true(_capture_network_environment() == original_environment, "populated-override check restores inherited environment")
	assert_eq(bind_address, "0.0.0.0", "env var overrides the server bind address")
	assert_eq(target_host, "play.example.com", "env var overrides the client target host")
	assert_eq(server_port, 40000, "env var overrides the server port")
	assert_eq(invalid_server_port, NetworkConfigScript.SERVER_PORT, "a non-numeric env port falls back to the default")
	assert_eq(
		out_of_range_server_port,
		NetworkConfigScript.SERVER_PORT,
		"an out-of-range env port falls back to the default"
	)


func _capture_network_environment() -> Dictionary:
	var snapshot: Dictionary = {}
	for variable: String in NETWORK_ENVIRONMENT_VARIABLES:
		snapshot[variable] = {
			"present": OS.has_environment(variable),
			"value": OS.get_environment(variable),
		}
	return snapshot


func _restore_network_environment(snapshot: Dictionary) -> void:
	for variable: String in NETWORK_ENVIRONMENT_VARIABLES:
		var original: Dictionary = snapshot[variable]
		if original["present"]:
			OS.set_environment(variable, original["value"])
		else:
			OS.unset_environment(variable)
