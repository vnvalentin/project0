extends RefCounted
class_name AssertionValidator
## Slice 059: server-only session-assertion validator. Verifies the HMAC-SHA256
## signature (constant-time) BEFORE trusting any claim, then checks schema,
## issuer, audience, and time window, returning bounded claims or a bounded
## reason. Fail-closed. The secret (verification) key is server-only per
## CLAUDE.md and MUST NEVER appear in shared/ or client/. In the target
## architecture the game server holds this to trust the login authority's
## assertions without sharing a database.

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

var _secret: PackedByteArray = PackedByteArray()
var _expected_issuer: String = ""
var _expected_audience: String = ""


func _init(secret_key_hex: String, expected_issuer: String, expected_audience: String) -> void:
	_secret = secret_key_hex.hex_decode()
	_expected_issuer = expected_issuer
	_expected_audience = expected_audience


## Validates `token` against the current time `now_unix` (caller-supplied clock).
## Returns { "outcome": OUTCOME_OK, "claims": Dictionary } on success, or
## { "outcome": REASON_* } (no claims) fail-closed. The signature is checked
## first with constant_time_compare so a forged/tampered token never reaches
## claim interpretation.
func validate(token: String, now_unix: int) -> Dictionary:
	var parts: Dictionary = SessionAssertionScript.split_token(token)
	if parts["outcome"] != SessionAssertionScript.OUTCOME_OK:
		return {"outcome": SessionAssertionScript.REASON_MALFORMED}

	var payload_b64: String = parts["payload_b64"]
	var crypto := Crypto.new()
	var expected_sig: PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA256, _secret, payload_b64.to_utf8_buffer())
	var provided_sig: PackedByteArray = Marshalls.base64_to_raw(parts["sig_b64"])
	if provided_sig.size() != expected_sig.size() or not crypto.constant_time_compare(provided_sig, expected_sig):
		return {"outcome": SessionAssertionScript.REASON_BAD_SIGNATURE}

	var parsed: Dictionary = SessionAssertionScript.parse_payload(Marshalls.base64_to_utf8(payload_b64))
	if parsed["outcome"] != SessionAssertionScript.OUTCOME_OK:
		return {"outcome": parsed["outcome"]}

	var claims: Dictionary = parsed["claims"]
	if String(claims[SessionAssertionScript.KEY_ISSUER]) != _expected_issuer:
		return {"outcome": SessionAssertionScript.REASON_WRONG_ISSUER}
	if String(claims[SessionAssertionScript.KEY_AUDIENCE]) != _expected_audience:
		return {"outcome": SessionAssertionScript.REASON_WRONG_AUDIENCE}
	if now_unix < int(claims[SessionAssertionScript.KEY_ISSUED_AT]):
		return {"outcome": SessionAssertionScript.REASON_NOT_YET_VALID}
	if now_unix >= int(claims[SessionAssertionScript.KEY_EXPIRES_AT]):
		return {"outcome": SessionAssertionScript.REASON_EXPIRED}

	return {"outcome": SessionAssertionScript.OUTCOME_OK, "claims": claims}
