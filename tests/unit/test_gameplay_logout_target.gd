extends GutTest
## Public-seam test for the split-flow in-world return to Character selection
## (client/gameplay_logout.gd + Slice 087 login-session resume). Under the split
## the button re-establishes a login session from the stored resume token and
## returns to the Character list, falling back to the login screen when the token
## is missing or expired; combined mode returns straight to Character selection.
## Also covers the server-owned resume-token TTL resolution.

const LogoutButtonScript: Script = preload("res://client/gameplay_logout.gd")
const NetworkClientScript: Script = preload("res://client/network_client.gd")

var _saved_ttl: String = ""


func before_each() -> void:
	_saved_ttl = OS.get_environment("PROJECT0_RESUME_TTL_SECONDS")


func after_each() -> void:
	OS.set_environment("PROJECT0_RESUME_TTL_SECONDS", _saved_ttl)


func _new_button() -> Button:
	var button: Button = LogoutButtonScript.new()
	add_child_autofree(button)
	return button


func test_button_is_labeled_character_select() -> void:
	assert_eq(_new_button().text, "Character Select", "the in-world return button reads Character Select")


func test_successful_resume_returns_to_character_list() -> void:
	assert_eq(_new_button()._return_target_scene("ok"), "res://client/character_gate.tscn", "a re-established login session lands on the Character list")


func test_failed_resume_falls_back_to_login_screen() -> void:
	var button: Button = _new_button()
	assert_eq(button._return_target_scene("no_resume_token"), "res://client/account_gate.tscn", "a missing resume token falls back to the login screen")
	assert_eq(button._return_target_scene("expired"), "res://client/account_gate.tscn", "an expired/rejected token falls back to the login screen")


func test_resume_ttl_defaults_when_unset() -> void:
	OS.set_environment("PROJECT0_RESUME_TTL_SECONDS", "")
	assert_eq(NetworkClientScript.resolve_resume_ttl_seconds(), NetworkClientScript.RESUME_ASSERTION_DEFAULT_TTL_SECONDS, "unset defaults to one hour")


func test_resume_ttl_reads_valid_override() -> void:
	OS.set_environment("PROJECT0_RESUME_TTL_SECONDS", "1800")
	assert_eq(NetworkClientScript.resolve_resume_ttl_seconds(), 1800, "a valid in-range override is used")


func test_resume_ttl_clamps_and_defaults_out_of_range() -> void:
	OS.set_environment("PROJECT0_RESUME_TTL_SECONDS", "5")
	assert_eq(NetworkClientScript.resolve_resume_ttl_seconds(), NetworkClientScript.RESUME_ASSERTION_MIN_TTL_SECONDS, "a too-small override clamps up to the floor")
	OS.set_environment("PROJECT0_RESUME_TTL_SECONDS", "999999999")
	assert_eq(NetworkClientScript.resolve_resume_ttl_seconds(), NetworkClientScript.RESUME_ASSERTION_MAX_TTL_SECONDS, "a too-large override clamps down to the ceiling")
	OS.set_environment("PROJECT0_RESUME_TTL_SECONDS", "abc")
	assert_eq(NetworkClientScript.resolve_resume_ttl_seconds(), NetworkClientScript.RESUME_ASSERTION_DEFAULT_TTL_SECONDS, "a non-integer override falls back to the default")
