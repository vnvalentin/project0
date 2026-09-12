extends GutTest
## GUT migration of Slice 003's LAN configuration smoke test.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")


func test_defaults_to_localhost_with_no_override() -> void:
	assert_eq(
		NetworkConfigScript.resolve_server_bind_address(),
		NetworkConfigScript.SERVER_ADDRESS,
		"server bind address defaults to localhost"
	)
	assert_eq(
		NetworkConfigScript.resolve_client_target_host(),
		NetworkConfigScript.DEFAULT_TARGET_HOST,
		"client target host defaults to WAN default target host"
	)


func test_cli_arg_overrides_bind_address_on_real_server() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
		"--quit-after", "1",
		"--", "--server-bind-address=127.0.0.1",
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "bind-address server process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"Server listening on 127.0.0.1:9999",
		"server honors --server-bind-address"
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
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
		"--quit-after", "1",
		"--", "--server-bind-address=0.0.0.0",
	], output, true)

	var printed: String = "\n".join(output)
	assert_eq(exit_code, 0, "WAN wildcard-bind server process exits successfully: %s" % printed)
	assert_string_contains(
		printed,
		"Server listening on 0.0.0.0:9999",
		"server honors --server-bind-address=0.0.0.0 for WAN binding"
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
