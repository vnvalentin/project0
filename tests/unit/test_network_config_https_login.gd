extends GutTest
## Slice 093: public-seam test for the client HTTPS-login flag
## (shared/network_config.gd::client_https_login_enabled). Precedence:
## PROJECT0_CLIENT_HTTPS_LOGIN="0" disables the flow; when unset it remains on
## for the portable public client. See
## docs/slices/093-client-https-login-wiring.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_flag: String = ""


func before_each() -> void:
	_saved_flag = OS.get_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, _saved_flag)


func test_enabled_when_unset() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "")
	assert_true(NetworkConfigScript.client_https_login_enabled(), "portable client defaults to HTTPS login")


func test_explicit_one_keeps_https_login_on() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "1")
	assert_true(NetworkConfigScript.client_https_login_enabled(), "PROJECT0_CLIENT_HTTPS_LOGIN=1 keeps the flow on")


func test_explicit_zero_forces_off_even_under_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "0")
	assert_false(NetworkConfigScript.client_https_login_enabled(), "PROJECT0_CLIENT_HTTPS_LOGIN=0 forces the flow off despite tunnel mode")
