extends GutTest
## Slice 096 (P-013): the pure client->server Canon mutation intent contract.
## The intent carries only what a client may express; any server-owned outcome
## field is rejected fail-closed.

const CanonMutationIntentScript: Script = preload("res://shared/canon_mutation_intent.gd")


func _valid() -> Dictionary:
	return CanonMutationIntentScript.build("sector-0-0", "structure-abc", "defeat_leader", 0, 1, {"leader": "baron"})


func test_build_produces_a_parseable_intent() -> void:
	var parsed: Dictionary = CanonMutationIntentScript.parse(_valid())
	assert_eq(parsed["outcome"], CanonMutationIntentScript.OUTCOME_OK)
	var intent: Dictionary = parsed["intent"]
	assert_eq(intent["sector_id"], "sector-0-0")
	assert_eq(intent["target_guid"], "structure-abc")
	assert_eq(intent["mutation_kind"], "defeat_leader")
	assert_eq(intent["expected_revision"], 0)
	assert_eq(intent["client_seq"], 1)
	assert_eq(intent["payload"], {"leader": "baron"})


func test_parse_rejects_non_dictionary() -> void:
	assert_eq(CanonMutationIntentScript.parse("nope")["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)
	assert_eq(CanonMutationIntentScript.parse(null)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)


func test_parse_rejects_wrong_schema_version() -> void:
	var bad: Dictionary = _valid()
	bad["schema_version"] = 99
	assert_eq(CanonMutationIntentScript.parse(bad)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)


func test_parse_rejects_missing_or_empty_ids() -> void:
	for field: String in ["sector_id", "target_guid"]:
		var empty: Dictionary = _valid()
		empty[field] = ""
		assert_eq(CanonMutationIntentScript.parse(empty)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID, "%s empty" % field)
		var missing: Dictionary = _valid()
		missing.erase(field)
		assert_eq(CanonMutationIntentScript.parse(missing)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID, "%s missing" % field)


func test_parse_rejects_unsupported_kind() -> void:
	var bad: Dictionary = _valid()
	bad["mutation_kind"] = "not_a_kind"
	assert_eq(CanonMutationIntentScript.parse(bad)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)


func test_parse_rejects_negative_sequence_and_revision() -> void:
	var bad_seq: Dictionary = _valid()
	bad_seq["client_seq"] = -1
	assert_eq(CanonMutationIntentScript.parse(bad_seq)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)
	var bad_rev: Dictionary = _valid()
	bad_rev["expected_revision"] = -1
	assert_eq(CanonMutationIntentScript.parse(bad_rev)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)


func test_parse_rejects_non_dictionary_payload() -> void:
	var bad: Dictionary = _valid()
	bad["payload"] = "not-a-dict"
	assert_eq(CanonMutationIntentScript.parse(bad)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)


func test_parse_rejects_oversized_payload() -> void:
	var huge: Dictionary = {}
	for i in 500:
		huge["k%d" % i] = "0123456789abcdef"
	var bad: Dictionary = _valid()
	bad["payload"] = huge
	assert_eq(CanonMutationIntentScript.parse(bad)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID)


func test_parse_rejects_server_owned_fields() -> void:
	# A client MUST NOT dictate the outcome or identity of a mutation.
	for forged: String in ["event_id", "actor_player_id", "server_tick", "applied_revision"]:
		var bad: Dictionary = _valid()
		bad[forged] = "x" if forged in ["event_id", "actor_player_id"] else 1
		assert_eq(CanonMutationIntentScript.parse(bad)["outcome"], CanonMutationIntentScript.OUTCOME_INVALID, "%s must be server-owned" % forged)
