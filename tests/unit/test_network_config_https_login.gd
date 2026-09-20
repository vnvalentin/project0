extends GutTest
## Slice 093: public-seam test for the client HTTPS-login flag
## (shared/network_config.gd::client_https_login_enabled). Precedence:
## PROJECT0_CLIENT_HTTPS_LOGIN="1" enables the flow; when unset it remains off
## for LAN development. See
## docs/slices/093-client-https-login-wiring.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_flag: String = ""


func before_each() -> void:
	_saved_flag = OS.get_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, _saved_flag)


func test_disabled_when_unset_and_no_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "")
	assert_false(NetworkConfigScript.client_https_login_enabled(), "LAN default (no flag, no tunnel) keeps the ENet path")


func test_explicit_one_forces_on_even_without_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "1")
	assert_true(NetworkConfigScript.client_https_login_enabled(), "PROJECT0_CLIENT_HTTPS_LOGIN=1 forces the flow on")


func test_explicit_zero_forces_off_even_under_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "0")
	assert_false(NetworkConfigScript.client_https_login_enabled(), "PROJECT0_CLIENT_HTTPS_LOGIN=0 forces the flow off despite tunnel mode")
