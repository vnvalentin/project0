extends GutTest
## Slice 059: unit tests for the pure SessionAssertion contract
## (shared/session_assertion.gd) — canonical payload build/parse with bounds,
## and token encode/split. No Crypto, no secrets (those are the issuer/validator
## seams tested in tests/unit/test_assertion_issuer_validator.gd).

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")


func _valid_claims() -> Dictionary:
	return {
		SessionAssertionScript.KEY_VERSION: SessionAssertionScript.SCHEMA_VERSION,
		SessionAssertionScript.KEY_SESSION_ID: "sid-1",
		SessionAssertionScript.KEY_ACCOUNT_ID: "acc-1",
		SessionAssertionScript.KEY_CHARACTER_ID: "char-1",
		SessionAssertionScript.KEY_ISSUED_AT: 1000,
		SessionAssertionScript.KEY_EXPIRES_AT: 1060,
		SessionAssertionScript.KEY_ISSUER: "project0-login",
		SessionAssertionScript.KEY_AUDIENCE: "project0-game",
	}


func test_build_then_parse_round_trips_all_claims() -> void:
	var payload: String = SessionAssertionScript.build_payload(_valid_claims())
	var result: Dictionary = SessionAssertionScript.parse_payload(payload)
	assert_eq(result["outcome"], SessionAssertionScript.OUTCOME_OK, "a well-formed payload parses")
	var claims: Dictionary = result["claims"]
	assert_eq(claims[SessionAssertionScript.KEY_ACCOUNT_ID], "acc-1")
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_ID], "char-1")
	assert_eq(claims[SessionAssertionScript.KEY_ISSUED_AT], 1000)
	assert_eq(claims[SessionAssertionScript.KEY_EXPIRES_AT], 1060)


func test_build_is_deterministic() -> void:
	assert_eq(SessionAssertionScript.build_payload(_valid_claims()), SessionAssertionScript.build_payload(_valid_claims()), "canonical build is stable so issuer/validator sign identical bytes")


func test_parse_rejects_non_json() -> void:
	assert_eq(SessionAssertionScript.parse_payload("not json")["outcome"], SessionAssertionScript.REASON_MALFORMED)


func test_parse_rejects_missing_key() -> void:
	# build_payload always emits all keys, so feed parse a JSON that genuinely
	# omits one to prove the missing-key rejection.
	var claims: Dictionary = _valid_claims()
	claims.erase(SessionAssertionScript.KEY_ACCOUNT_ID)
	assert_eq(SessionAssertionScript.parse_payload(JSON.stringify(claims))["outcome"], SessionAssertionScript.REASON_MALFORMED)


func test_parse_rejects_bad_version() -> void:
	var claims: Dictionary = _valid_claims()
	claims[SessionAssertionScript.KEY_VERSION] = 999
	assert_eq(SessionAssertionScript.parse_payload(SessionAssertionScript.build_payload(claims))["outcome"], SessionAssertionScript.REASON_UNSUPPORTED_VERSION)


func test_parse_rejects_empty_account() -> void:
	var claims: Dictionary = _valid_claims()
	claims[SessionAssertionScript.KEY_ACCOUNT_ID] = ""
	assert_eq(SessionAssertionScript.parse_payload(SessionAssertionScript.build_payload(claims))["outcome"], SessionAssertionScript.REASON_INVALID_CLAIMS)


func test_parse_allows_empty_character_id() -> void:
	var claims: Dictionary = _valid_claims()
	claims[SessionAssertionScript.KEY_CHARACTER_ID] = ""
	var result: Dictionary = SessionAssertionScript.parse_payload(SessionAssertionScript.build_payload(claims))
	assert_eq(result["outcome"], SessionAssertionScript.OUTCOME_OK, "an account-only assertion (empty cid) is valid")
	assert_eq(result["claims"][SessionAssertionScript.KEY_CHARACTER_ID], "")


func test_parse_rejects_expiry_not_after_issued_at() -> void:
	var claims: Dictionary = _valid_claims()
	claims[SessionAssertionScript.KEY_EXPIRES_AT] = 1000
	assert_eq(SessionAssertionScript.parse_payload(SessionAssertionScript.build_payload(claims))["outcome"], SessionAssertionScript.REASON_INVALID_CLAIMS)


func test_parse_rejects_oversized_field() -> void:
	var claims: Dictionary = _valid_claims()
	claims[SessionAssertionScript.KEY_ACCOUNT_ID] = "a".repeat(SessionAssertionScript.MAX_FIELD_LEN + 1)
	assert_eq(SessionAssertionScript.parse_payload(SessionAssertionScript.build_payload(claims))["outcome"], SessionAssertionScript.REASON_INVALID_CLAIMS)


func test_encode_then_split_round_trips() -> void:
	var token: String = SessionAssertionScript.encode_token("PAYLOAD", "SIGNATURE")
	var parts: Dictionary = SessionAssertionScript.split_token(token)
	assert_eq(parts["outcome"], SessionAssertionScript.OUTCOME_OK)
	assert_eq(parts["payload_b64"], "PAYLOAD")
	assert_eq(parts["sig_b64"], "SIGNATURE")


func test_split_rejects_malformed_token() -> void:
	assert_eq(SessionAssertionScript.split_token("no-dot-here")["outcome"], SessionAssertionScript.REASON_MALFORMED)
	assert_eq(SessionAssertionScript.split_token("a.b.c")["outcome"], SessionAssertionScript.REASON_MALFORMED)
