extends RefCounted
class_name AssertionIssuer
## Slice 059: server-only session-assertion issuer. Signs the canonical
## SessionAssertion payload with HMAC-SHA256 under a shared secret key. Per
## CLAUDE.md's Runtime Ownership rule the secret key is server-only and MUST
## NEVER appear in shared/ or client/. In the target architecture the login
## authority holds this; the game server holds the matching validator.
##
## HMAC (shared secret) is the home-hosted trust choice, consistent with the
## repo's existing Crypto.hmac_digest usage (server/password_hasher.gd).

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

var _secret: PackedByteArray = PackedByteArray()
var _issuer: String = ""
var _audience: String = ""


func _init(secret_key_hex: String, issuer: String, audience: String) -> void:
	_secret = secret_key_hex.hex_decode()
	_issuer = issuer
	_audience = audience


## Mints a signed token. `character_id` is empty for an account-only assertion
## and set for a refreshed selected-Character assertion. `ttl_seconds` bounds
## the validity window from `issued_at_unix` (the caller supplies the clock so
## this stays deterministic and testable).
func issue(session_id: String, account_id: String, character_id: String, issued_at_unix: int, ttl_seconds: int) -> String:
	var claims: Dictionary = {
		SessionAssertionScript.KEY_VERSION: SessionAssertionScript.SCHEMA_VERSION,
		SessionAssertionScript.KEY_SESSION_ID: session_id,
		SessionAssertionScript.KEY_ACCOUNT_ID: account_id,
		SessionAssertionScript.KEY_CHARACTER_ID: character_id,
		SessionAssertionScript.KEY_ISSUED_AT: issued_at_unix,
		SessionAssertionScript.KEY_EXPIRES_AT: issued_at_unix + ttl_seconds,
		SessionAssertionScript.KEY_ISSUER: _issuer,
		SessionAssertionScript.KEY_AUDIENCE: _audience,
	}
	var payload_b64: String = Marshalls.utf8_to_base64(SessionAssertionScript.build_payload(claims))
	var crypto := Crypto.new()
	var signature: PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA256, _secret, payload_b64.to_utf8_buffer())
	return SessionAssertionScript.encode_token(payload_b64, Marshalls.raw_to_base64(signature))
