extends GutTest
## Public-seam test for the split-aware logout return path
## (client/gameplay_logout.gd::_logout_target_scene). Under the login split the
## world handoff has already disconnected from the login process, so logout must
## return to the login screen to re-authenticate — returning to the Character
## screen would list characters against the assertion-only game server and fail
## with account_authority_disabled. Combined mode keeps one authenticated
## connection and returns straight to Character selection. Regression for the
## Slice 084 cutover GUI confirmation.

const LogoutButtonScript: Script = preload("res://client/gameplay_logout.gd")
const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_env: String = ""


func before_each() -> void:
	_saved_env = OS.get_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, _saved_env)


func _new_button() -> Button:
	var button: Button = LogoutButtonScript.new()
	add_child_autofree(button)
	return button


func test_split_logout_returns_to_login_screen() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "1")
	assert_eq(_new_button()._logout_target_scene(), "res://client/account_gate.tscn", "under the split, logout returns to the login screen to re-authenticate")


func test_combined_logout_returns_to_character_screen() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "0")
	assert_eq(_new_button()._logout_target_scene(), "res://client/character_gate.tscn", "in combined mode, logout returns straight to Character selection")


func test_split_button_is_labeled_logout() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "1")
	assert_eq(_new_button()._logout_label(), "Logout", "under the split the button logs out to the login screen, so it reads Logout")


func test_combined_button_is_labeled_character_select() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "0")
	assert_eq(_new_button()._logout_label(), "Character Select", "in combined mode it returns to the character list, so it reads Character Select")
