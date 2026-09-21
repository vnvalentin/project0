extends GutTest

const ValidatorScript: Script = preload("res://server/world_directive_validator.gd")

func _valid_proposal() -> Dictionary:
	return {
		"schema_version": 1,
		"directive_id": "directive-forest-1",
		"directive_revision": 1,
		"builder_version": "builder-v1",
		"tuning_version": "tuning-v1",
		"resource_set_version": "resources-v1",
		"biome": "forest",
		"theme": "frontier",
		"palette_tags": ["verdant"],
		"atmosphere_tags": ["mist"],
		"density_band": 2,
		"threat_band": 1,
		"poi_requirements": [{"poi_id": "peak-1", "predicate": "HIGHEST_PEAK"}],
		"narrative": "A moss-covered road follows the ridge.",
		"context_refs": ["campaign-1"],
	}

func _fallback() -> Dictionary:
	return {"schema_version": 1, "directive_id": "fixture-forest", "biome": "forest", "theme": "frontier"}

func test_accepts_and_normalizes_bounded_semantic_proposal() -> void:
	var result: Dictionary = ValidatorScript.validate(_valid_proposal(), _fallback())
	assert_eq(result["outcome"], ValidatorScript.OUTCOME_ACCEPTED)
	assert_eq(result["directive"]["builder_version"], "builder-v1")
	assert_eq(result["directive"]["poi_requirements"][0]["predicate"], "HIGHEST_PEAK")

func test_rejects_unknown_vocabulary_without_partial_directive() -> void:
	var proposal: Dictionary = _valid_proposal()
	proposal["biome"] = "volcanic"
	var result: Dictionary = ValidatorScript.validate(proposal, _fallback())
	assert_eq(result["outcome"], ValidatorScript.OUTCOME_FALLBACK)
	assert_eq(result["reason"], "unsupported_vocabulary")
	assert_eq(result["directive"]["directive_id"], "fixture-forest")

func test_rejects_out_of_range_band_and_invalid_poi() -> void:
	var proposal: Dictionary = _valid_proposal()
	proposal["threat_band"] = 4
	var result: Dictionary = ValidatorScript.validate(proposal, _fallback())
	assert_eq(result["reason"], "invalid_threat_band")
	proposal = _valid_proposal()
	proposal["poi_requirements"] = [{"poi_id": "peak-1", "predicate": "RANDOM_COORDINATE"}]
	result = ValidatorScript.validate(proposal, _fallback())
	assert_eq(result["reason"], "invalid_poi_requirements")

func test_rejects_wrong_schema_and_non_object_as_fallback() -> void:
	var proposal: Dictionary = _valid_proposal()
	proposal["schema_version"] = 2
	var result: Dictionary = ValidatorScript.validate(proposal, _fallback())
	assert_eq(result["reason"], "unsupported_schema_version")
	result = ValidatorScript.validate("raw model output", _fallback())
	assert_eq(result["reason"], "proposal_not_object")