extends GutTest
## Slice 093: public-seam test for the client HTTPS-login flag
## (shared/network_config.gd::client_https_login_enabled). Precedence:
## PROJECT0_CLIENT_HTTPS_LOGIN="1"/"0" forces the flow on/off; when unset it
## defaults to tunnel mode (PROJECT0_TUNNEL="1"), so the WAN launcher enables it
## implicitly while LAN development keeps the ENet path. See
## docs/slices/093-client-https-login-wiring.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_flag: String = ""
var _saved_tunnel: String = ""


func before_each() -> void:
	_saved_flag = OS.get_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR)
	_saved_tunnel = OS.get_environment(NetworkConfigScript.TUNNEL_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, _saved_flag)
	OS.set_environment(NetworkConfigScript.TUNNEL_ENV_VAR, _saved_tunnel)


func test_disabled_when_unset_and_no_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "")
	OS.set_environment(NetworkConfigScript.TUNNEL_ENV_VAR, "")
	assert_false(NetworkConfigScript.client_https_login_enabled(), "LAN default (no flag, no tunnel) keeps the ENet path")


func test_defaults_on_under_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "")
	OS.set_environment(NetworkConfigScript.TUNNEL_ENV_VAR, "1")
	assert_true(NetworkConfigScript.client_https_login_enabled(), "tunnel mode enables HTTPS login implicitly")


func test_explicit_one_forces_on_even_without_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "1")
	OS.set_environment(NetworkConfigScript.TUNNEL_ENV_VAR, "")
	assert_true(NetworkConfigScript.client_https_login_enabled(), "PROJECT0_CLIENT_HTTPS_LOGIN=1 forces the flow on")


func test_explicit_zero_forces_off_even_under_tunnel() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "0")
	OS.set_environment(NetworkConfigScript.TUNNEL_ENV_VAR, "1")
	assert_false(NetworkConfigScript.client_https_login_enabled(), "PROJECT0_CLIENT_HTTPS_LOGIN=0 forces the flow off despite tunnel mode")
