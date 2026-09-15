extends GutTest
## Slice 078: public-seam test for the opt-in client login-split flag
## (shared/network_config.gd::client_login_split_enabled). True only for
## PROJECT0_CLIENT_LOGIN_SPLIT=1; off when unset or any other value, so the
## single-connection flow stays the default. See
## docs/slices/078-wire-gates-to-login-process.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_env: String = ""


func before_each() -> void:
	_saved_env = OS.get_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, _saved_env)


func test_disabled_when_unset() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "")
	assert_false(NetworkConfigScript.client_login_split_enabled(), "unset means the split is off")


func test_enabled_when_one() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "1")
	assert_true(NetworkConfigScript.client_login_split_enabled(), "PROJECT0_CLIENT_LOGIN_SPLIT=1 enables the split")


func test_disabled_for_other_values() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "true")
	assert_false(NetworkConfigScript.client_login_split_enabled(), "any value other than 1 is off")
