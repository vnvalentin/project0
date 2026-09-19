extends GutTest
## Slice 059: unit tests for the server-only assertion issuer + validator
## (server/assertion_issuer.gd, server/assertion_validator.gd). Proves the
## issue->validate round trip and every rejection path (tampered payload/sig,
## wrong key, wrong issuer/audience, expired, not-yet-valid, unsupported
## version, malformed). Pure — Crypto works without a scene tree; the clock is
## caller-supplied so time checks are deterministic.

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")

const SECRET: String = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
const OTHER_SECRET: String = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
const ISSUER: String = "project0-login"
const AUDIENCE: String = "project0-game"

var _issuer: RefCounted = null
var _validator: RefCounted = null


func before_each() -> void:
	_issuer = AssertionIssuerScript.new(SECRET, ISSUER, AUDIENCE)
	_validator = AssertionValidatorScript.new(SECRET, ISSUER, AUDIENCE)


func test_round_trip_account_only() -> void:
	var token: String = _issuer.issue("sid-1", "acc-1", "", 1000, 60)
	var result: Dictionary = _validator.validate(token, 1001)
	assert_eq(result["outcome"], SessionAssertionScript.OUTCOME_OK, "a fresh account-only assertion validates")
	assert_eq(result["claims"][SessionAssertionScript.KEY_ACCOUNT_ID], "acc-1")
	assert_eq(result["claims"][SessionAssertionScript.KEY_CHARACTER_ID], "", "account-only assertion carries no character")


func test_round_trip_selected_character() -> void:
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	var result: Dictionary = _validator.validate(token, 1030)
	assert_eq(result["outcome"], SessionAssertionScript.OUTCOME_OK)
	assert_eq(result["claims"][SessionAssertionScript.KEY_CHARACTER_ID], "char-9", "selected-Character assertion carries the character")


func test_tampered_payload_is_rejected() -> void:
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	var parts: Dictionary = SessionAssertionScript.split_token(token)
	var tampered: String = SessionAssertionScript.encode_token(_flip_first_char(parts["payload_b64"]), parts["sig_b64"])
	assert_eq(_validator.validate(tampered, 1001)["outcome"], SessionAssertionScript.REASON_BAD_SIGNATURE, "a mutated payload fails the signature check before any claim is trusted")


func test_tampered_signature_is_rejected() -> void:
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	var parts: Dictionary = SessionAssertionScript.split_token(token)
	var tampered: String = SessionAssertionScript.encode_token(parts["payload_b64"], _flip_first_char(parts["sig_b64"]))
	assert_eq(_validator.validate(tampered, 1001)["outcome"], SessionAssertionScript.REASON_BAD_SIGNATURE)


func test_wrong_signing_key_is_rejected() -> void:
	var foreign_issuer: RefCounted = AssertionIssuerScript.new(OTHER_SECRET, ISSUER, AUDIENCE)
	var token: String = foreign_issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	assert_eq(_validator.validate(token, 1001)["outcome"], SessionAssertionScript.REASON_BAD_SIGNATURE, "an assertion signed with a different key is rejected")


func test_wrong_issuer_is_rejected() -> void:
	var validator: RefCounted = AssertionValidatorScript.new(SECRET, "someone-else", AUDIENCE)
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	assert_eq(validator.validate(token, 1001)["outcome"], SessionAssertionScript.REASON_WRONG_ISSUER)


func test_wrong_audience_is_rejected() -> void:
	var validator: RefCounted = AssertionValidatorScript.new(SECRET, ISSUER, "some-other-service")
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	assert_eq(validator.validate(token, 1001)["outcome"], SessionAssertionScript.REASON_WRONG_AUDIENCE)


func test_expired_is_rejected() -> void:
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	assert_eq(_validator.validate(token, 1060)["outcome"], SessionAssertionScript.REASON_EXPIRED, "validation at exactly exp is expired (exclusive upper bound)")
	assert_eq(_validator.validate(token, 5000)["outcome"], SessionAssertionScript.REASON_EXPIRED)


func test_not_yet_valid_is_rejected() -> void:
	var token: String = _issuer.issue("sid-1", "acc-1", "char-9", 1000, 60)
	assert_eq(_validator.validate(token, 999)["outcome"], SessionAssertionScript.REASON_NOT_YET_VALID)


func test_malformed_token_is_rejected() -> void:
	assert_eq(_validator.validate("garbage-no-dot", 1000)["outcome"], SessionAssertionScript.REASON_MALFORMED)


func test_unsupported_version_propagates() -> void:
	# Craft a correctly-signed token whose payload carries an unsupported
	# version, proving the validator surfaces parse's version rejection AFTER a
	# valid signature check.
	var claims: Dictionary = {
		SessionAssertionScript.KEY_VERSION: 999,
		SessionAssertionScript.KEY_SESSION_ID: "sid-1",
		SessionAssertionScript.KEY_ACCOUNT_ID: "acc-1",
		SessionAssertionScript.KEY_CHARACTER_ID: "",
		SessionAssertionScript.KEY_ISSUED_AT: 1000,
		SessionAssertionScript.KEY_EXPIRES_AT: 1060,
		SessionAssertionScript.KEY_ISSUER: ISSUER,
		SessionAssertionScript.KEY_AUDIENCE: AUDIENCE,
	}
	var payload_b64: String = Marshalls.utf8_to_base64(SessionAssertionScript.build_payload(claims))
	var crypto := Crypto.new()
	var sig: PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA256, SECRET.hex_decode(), payload_b64.to_utf8_buffer())
	var token: String = SessionAssertionScript.encode_token(payload_b64, Marshalls.raw_to_base64(sig))
	assert_eq(_validator.validate(token, 1001)["outcome"], SessionAssertionScript.REASON_UNSUPPORTED_VERSION)


func _flip_first_char(text: String) -> String:
	if text.is_empty():
		return "A"
	var replacement: String = "A" if text[0] != "A" else "B"
	return replacement + text.substr(1)
