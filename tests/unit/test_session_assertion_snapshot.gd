extends GutTest
## Slice 074: public-seam test for the signed Character snapshot carried in a
## selected-Character assertion. Proves the login authority's issuer signs a
## bounded display_name + cosmetic that the game server's validator returns in
## the claims, that account-only assertions carry an empty snapshot, that
## oversized/tampered snapshots fail closed, and that older snapshot-less payloads
## still parse (backward compatibility). See
## docs/slices/074-assertion-character-snapshot.md.

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ISSUER: String = "project0-login"
const AUDIENCE: String = "project0-game"


func _issuer() -> RefCounted:
	return AssertionIssuerScript.new(SECRET, ISSUER, AUDIENCE)


func _validator() -> RefCounted:
	return AssertionValidatorScript.new(SECRET, ISSUER, AUDIENCE)


func test_character_snapshot_round_trips_through_validation() -> void:
	# Cosmetic travels as JSON in the signed payload, so numeric values return as
	# floats; string values round-trip exactly, which is what this asserts.
	var cosmetic: Dictionary = {"body": "tall", "tint": "amber"}
	var token: String = _issuer().issue("sess-1", "acc-1", "char-1", 1000, 300, "Alice the Bold", cosmetic)
	var result: Dictionary = _validator().validate(token, 1001)
	assert_eq(result["outcome"], SessionAssertionScript.OUTCOME_OK, "a snapshot-bearing token validates")
	var claims: Dictionary = result["claims"]
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_NAME], "Alice the Bold", "the signed display_name round-trips")
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_COSMETIC], cosmetic, "the signed cosmetic round-trips")


func test_account_only_assertion_has_empty_snapshot() -> void:
	var token: String = _issuer().issue("sess-1", "acc-1", "", 1000, 300)
	var claims: Dictionary = _validator().validate(token, 1001)["claims"]
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_NAME], "", "an account-only assertion carries no name")
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_COSMETIC], {}, "an account-only assertion carries an empty cosmetic")


func test_oversized_name_is_rejected() -> void:
	var long_name: String = "a".repeat(SessionAssertionScript.MAX_FIELD_LEN + 1)
	var token: String = _issuer().issue("sess-1", "acc-1", "char-1", 1000, 300, long_name, {})
	assert_eq(_validator().validate(token, 1001)["outcome"], SessionAssertionScript.REASON_INVALID_CLAIMS, "an oversized name fails closed")


func test_oversized_cosmetic_is_rejected() -> void:
	var big_cosmetic: Dictionary = {"blob": "x".repeat(SessionAssertionScript.MAX_COSMETIC_JSON_LEN + 1)}
	var token: String = _issuer().issue("sess-1", "acc-1", "char-1", 1000, 300, "Hero", big_cosmetic)
	assert_eq(_validator().validate(token, 1001)["outcome"], SessionAssertionScript.REASON_INVALID_CLAIMS, "an oversized cosmetic fails closed")


func test_tampered_snapshot_fails_signature() -> void:
	var token: String = _issuer().issue("sess-1", "acc-1", "char-1", 1000, 300, "Hero", {"tint": 1})
	var parts: Dictionary = SessionAssertionScript.split_token(token)
	# Re-sign nothing: swap in a forged payload with a changed name but keep the
	# original signature — the HMAC over the new payload no longer matches.
	var forged_payload: String = Marshalls.utf8_to_base64(SessionAssertionScript.build_payload({
		SessionAssertionScript.KEY_VERSION: SessionAssertionScript.SCHEMA_VERSION,
		SessionAssertionScript.KEY_SESSION_ID: "sess-1",
		SessionAssertionScript.KEY_ACCOUNT_ID: "acc-1",
		SessionAssertionScript.KEY_CHARACTER_ID: "char-1",
		SessionAssertionScript.KEY_ISSUED_AT: 1000,
		SessionAssertionScript.KEY_EXPIRES_AT: 1300,
		SessionAssertionScript.KEY_ISSUER: ISSUER,
		SessionAssertionScript.KEY_AUDIENCE: AUDIENCE,
		SessionAssertionScript.KEY_CHARACTER_NAME: "Impostor",
		SessionAssertionScript.KEY_CHARACTER_COSMETIC: {"tint": 1},
	}))
	var forged: String = SessionAssertionScript.encode_token(forged_payload, parts["sig_b64"])
	assert_eq(_validator().validate(forged, 1001)["outcome"], SessionAssertionScript.REASON_BAD_SIGNATURE, "a tampered snapshot fails the signature check")


func test_older_snapshotless_payload_parses_with_defaults() -> void:
	# A payload that predates the snapshot (only the eight identity claims).
	var legacy: Dictionary = {
		SessionAssertionScript.KEY_VERSION: SessionAssertionScript.SCHEMA_VERSION,
		SessionAssertionScript.KEY_SESSION_ID: "sess-1",
		SessionAssertionScript.KEY_ACCOUNT_ID: "acc-1",
		SessionAssertionScript.KEY_CHARACTER_ID: "char-1",
		SessionAssertionScript.KEY_ISSUED_AT: 1000,
		SessionAssertionScript.KEY_EXPIRES_AT: 1300,
		SessionAssertionScript.KEY_ISSUER: ISSUER,
		SessionAssertionScript.KEY_AUDIENCE: AUDIENCE,
	}
	var parsed: Dictionary = SessionAssertionScript.parse_payload(JSON.stringify(legacy))
	assert_eq(parsed["outcome"], SessionAssertionScript.OUTCOME_OK, "an older snapshot-less payload still parses")
	assert_eq(parsed["claims"][SessionAssertionScript.KEY_CHARACTER_NAME], "", "the missing name defaults to empty")
	assert_eq(parsed["claims"][SessionAssertionScript.KEY_CHARACTER_COSMETIC], {}, "the missing cosmetic defaults to empty")
