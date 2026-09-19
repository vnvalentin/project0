extends GutTest
## Slice 159 (telemetry map #282, decision #283): the shared telemetry
## envelope contract (`shared/telemetry_event.gd`). Covers structural
## validity, size bounds, privacy denylisting, and the unknown-schema_version
## non-rejection rule. See docs/slices/159-telemetry-envelope-validation.md.

const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")


func _valid_event(payload: Dictionary = {}) -> Dictionary:
	return TelemetryEventScript.build(
		"connection.peer_connected", 1, 1758000000, 42, 7, payload, "acct-1", "char-1", "sess-1"
	)


func test_build_shapes_all_envelope_fields() -> void:
	var event: Dictionary = _valid_event({"foo": "bar"})
	assert_eq(event["event_type"], "connection.peer_connected")
	assert_eq(event["schema_version"], 1)
	assert_eq(event["emitted_at_unix"], 1758000000)
	assert_eq(event["server_tick"], 42)
	assert_eq(event["peer_id"], 7)
	assert_eq(event["account_id"], "acct-1")
	assert_eq(event["character_id"], "char-1")
	assert_eq(event["session_id"], "sess-1")
	assert_eq(event["payload"], {"foo": "bar"})


func test_build_defaults_correlation_ids_to_empty_string() -> void:
	var event: Dictionary = TelemetryEventScript.build("connection.peer_connected", 1, 1758000000, 42, 7, {})
	assert_eq(event["account_id"], "", "pre-auth events have no account yet")
	assert_eq(event["character_id"], "")
	assert_eq(event["session_id"], "")


func test_valid_event_is_accepted() -> void:
	var result: Dictionary = TelemetryEventScript.validate(_valid_event())
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_ACCEPTED)


func test_missing_event_type_is_malformed() -> void:
	var event: Dictionary = _valid_event()
	event.erase("event_type")
	var result: Dictionary = TelemetryEventScript.validate(event)
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_MALFORMED)


func test_non_int_server_tick_is_malformed() -> void:
	var event: Dictionary = _valid_event()
	event["server_tick"] = "42"
	var result: Dictionary = TelemetryEventScript.validate(event)
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_MALFORMED)


func test_non_dictionary_payload_is_malformed() -> void:
	var event: Dictionary = _valid_event()
	event["payload"] = "not a dict"
	var result: Dictionary = TelemetryEventScript.validate(event)
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_MALFORMED)


func test_unknown_schema_version_is_not_rejected() -> void:
	# schema_version is per-event_type and unbounded going forward; validate()
	# only checks it is an int, never whether it is "known".
	var event: Dictionary = _valid_event()
	event["schema_version"] = 999
	var result: Dictionary = TelemetryEventScript.validate(event)
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_ACCEPTED, "an unrecognized version is stored raw, not rejected")


func test_denylisted_payload_key_is_rejected() -> void:
	for bad_key: String in ["password", "auth_token", "client_secret", "ip_address"]:
		var result: Dictionary = TelemetryEventScript.validate(_valid_event({bad_key: "value"}))
		assert_eq(
			result["outcome"], TelemetryEventScript.OUTCOME_REJECTED_PRIVACY, "key '%s' must be denylisted" % bad_key
		)


func test_free_text_length_payload_value_is_rejected() -> void:
	var long_text: String = "x".repeat(TelemetryEventScript.MAX_STRING_VALUE_LENGTH)
	var result: Dictionary = TelemetryEventScript.validate(_valid_event({"note": long_text}))
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_REJECTED_PRIVACY)


func test_short_string_payload_value_is_accepted() -> void:
	var result: Dictionary = TelemetryEventScript.validate(_valid_event({"outcome": "ACCEPTED"}))
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_ACCEPTED)


func test_oversized_payload_is_rejected_for_size() -> void:
	var big_payload: Dictionary = {}
	# Many short (non-denylisted, non-free-text) keys push serialized size over
	# the cap without tripping the free-text-length privacy check.
	for i: int in range(200):
		big_payload["field_%d" % i] = "v%d" % i
	var result: Dictionary = TelemetryEventScript.validate(_valid_event(big_payload))
	assert_eq(result["outcome"], TelemetryEventScript.OUTCOME_REJECTED_SIZE)
