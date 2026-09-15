extends GutTest
## Slice 071: public-seam test for the pure assertion-secret resolver
## (server/login_runtime.gd::resolve_assertion_secret_details). A configured
## value passes through (trimmed) and reports the "configured" source; an empty
## value yields a fresh 64-hex-character ephemeral key. This is the resolver both
## the game and login entrypoints use to share one HMAC secret. See
## docs/slices/071-shared-assertion-secret.md.

const LoginRuntimeScript: Script = preload("res://server/login_runtime.gd")


func test_configured_value_is_trimmed_and_reported_as_configured() -> void:
	var details: Dictionary = LoginRuntimeScript.resolve_assertion_secret_details("  0f1e2d3c4b5a  ")
	assert_eq(details["source"], LoginRuntimeScript.SECRET_SOURCE_CONFIGURED, "a non-empty value is the configured source")
	assert_eq(details["secret"], "0f1e2d3c4b5a", "the configured secret is trimmed and passed through unchanged")


func test_empty_value_yields_an_ephemeral_hex_key() -> void:
	var details: Dictionary = LoginRuntimeScript.resolve_assertion_secret_details("")
	assert_eq(details["source"], LoginRuntimeScript.SECRET_SOURCE_EPHEMERAL, "an empty value falls back to an ephemeral key")
	assert_eq(String(details["secret"]).length(), 64, "a 32-byte key encodes to 64 hex characters")
	assert_true(String(details["secret"]).is_valid_hex_number(false), "the ephemeral key is valid hex")


func test_whitespace_only_value_is_ephemeral() -> void:
	var details: Dictionary = LoginRuntimeScript.resolve_assertion_secret_details("   ")
	assert_eq(details["source"], LoginRuntimeScript.SECRET_SOURCE_EPHEMERAL, "a whitespace-only value falls back to ephemeral")


func test_two_ephemeral_resolutions_differ() -> void:
	var first: String = LoginRuntimeScript.resolve_assertion_secret_details("")["secret"]
	var second: String = LoginRuntimeScript.resolve_assertion_secret_details("")["secret"]
	assert_ne(first, second, "each ephemeral resolution generates a distinct key")
