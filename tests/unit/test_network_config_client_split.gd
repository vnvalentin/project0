extends GutTest
## Slice 084 cutover: public-seam test for the client login-split flag
## (shared/network_config.gd::client_login_split_enabled). The split is now the
## default (ON); only PROJECT0_CLIENT_LOGIN_SPLIT=0 selects the legacy
## single-connection flow. See docs/slices/084-login-split-cutover.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_env: String = ""


func before_each() -> void:
	_saved_env = OS.get_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, _saved_env)


func test_enabled_when_unset() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "")
	assert_true(NetworkConfigScript.client_login_split_enabled(), "the split is the default when unset")


func test_disabled_when_zero() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "0")
	assert_false(NetworkConfigScript.client_login_split_enabled(), "PROJECT0_CLIENT_LOGIN_SPLIT=0 selects the legacy flow")


func test_enabled_for_other_values() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "1")
	assert_true(NetworkConfigScript.client_login_split_enabled(), "any value other than 0 keeps the split on")
