extends GutTest
## Slice 072: public-seam test for the login-endpoint port resolver
## (shared/network_config.gd::resolve_login_port). Mirrors the game-port resolver
## tests: the PROJECT0_LOGIN_PORT env value wins when valid, and a malformed or
## out-of-range value falls back to the bounded default. No CLI arg is set here,
## so precedence falls through to env then default. See
## docs/slices/072-login-endpoint-config.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_login_port_env: String = ""


func before_each() -> void:
	_saved_login_port_env = OS.get_environment(NetworkConfigScript.LOGIN_PORT_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.LOGIN_PORT_ENV_VAR, _saved_login_port_env)


func test_defaults_when_unset() -> void:
	OS.set_environment(NetworkConfigScript.LOGIN_PORT_ENV_VAR, "")
	assert_eq(NetworkConfigScript.resolve_login_port(), NetworkConfigScript.LOGIN_PORT, "an unset login port resolves to the default")


func test_env_override_when_valid() -> void:
	OS.set_environment(NetworkConfigScript.LOGIN_PORT_ENV_VAR, "19998")
	assert_eq(NetworkConfigScript.resolve_login_port(), 19998, "a valid PROJECT0_LOGIN_PORT is honored")


func test_falls_back_on_non_numeric() -> void:
	OS.set_environment(NetworkConfigScript.LOGIN_PORT_ENV_VAR, "not-a-port")
	assert_eq(NetworkConfigScript.resolve_login_port(), NetworkConfigScript.LOGIN_PORT, "a non-numeric override falls back to the default")


func test_falls_back_on_out_of_range() -> void:
	OS.set_environment(NetworkConfigScript.LOGIN_PORT_ENV_VAR, "70000")
	assert_eq(NetworkConfigScript.resolve_login_port(), NetworkConfigScript.LOGIN_PORT, "an out-of-range port falls back to the default")
