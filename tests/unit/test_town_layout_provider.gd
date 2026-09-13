extends GutTest
## Public-seam unit tests for Slice 026's town-layout guarantee
## (server/town_layout_provider.gd): the LLM proposes, the server validates and
## guarantees the required structures, else falls back to the hub fixture. Pure
## and stateless. See docs/slices/026-llm-town-generation.md.

const TownLayoutProviderScript: Script = preload("res://server/town_layout_provider.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


func _fixture() -> Dictionary:
	return StartingTownHubFixtureScript.blueprint()


func test_shipped_fixture_meets_the_required_structures() -> void:
	# The fallback must always be usable: the shipped hub satisfies the guarantee.
	var result: Dictionary = TownLayoutProviderScript.meets_required_structures(_fixture())
	assert_true(result["ok"], "the hub fixture meets the required-structure guarantee (%s)" % result["detail"])


func test_too_few_houses_fails_the_guarantee() -> void:
	var blueprint: Dictionary = _fixture()
	var structures: Array = blueprint["structures"]
	for i in range(structures.size()):
		if structures[i]["kind"] == "house":
			structures.remove_at(i)
			break
	var result: Dictionary = TownLayoutProviderScript.meets_required_structures(blueprint)
	assert_false(result["ok"], "9 houses fails the >= 10 requirement")


func test_missing_singleton_fails_the_guarantee() -> void:
	var blueprint: Dictionary = _fixture()
	var structures: Array = blueprint["structures"]
	for i in range(structures.size()):
		if structures[i]["kind"] == "smithy":
			structures.remove_at(i)
			break
	var result: Dictionary = TownLayoutProviderScript.meets_required_structures(blueprint)
	assert_false(result["ok"], "a town with no smithy fails the guarantee")


func test_resolve_accepts_a_valid_complete_llm_candidate() -> void:
	var candidate: Dictionary = _fixture()
	candidate["sector_id"] = "llm_town"
	var result: Dictionary = TownLayoutProviderScript.resolve(candidate, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_LLM, "a valid complete candidate is used")
	assert_eq(result["outcome"], TownLayoutProviderScript.OUTCOME_ACCEPTED, "accepted outcome")
	assert_eq(result["blueprint"]["sector_id"], "llm_town", "the resolved blueprint is the LLM candidate, not the fallback")


func test_resolve_falls_back_on_schema_invalid_candidate() -> void:
	var result: Dictionary = TownLayoutProviderScript.resolve({"garbage": true}, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "a schema-invalid candidate falls back")
	assert_eq(result["blueprint"]["sector_id"], "starting_town_hub", "the fallback blueprint is the fixture")


func test_resolve_falls_back_on_incomplete_candidate() -> void:
	var candidate: Dictionary = _fixture()
	candidate["sector_id"] = "llm_town"
	var structures: Array = candidate["structures"]
	var removed: int = 0
	for i in range(structures.size() - 1, -1, -1):
		if structures[i]["kind"] == "house" and removed < 2:
			structures.remove_at(i)
			removed += 1
	var result: Dictionary = TownLayoutProviderScript.resolve(candidate, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "a valid but incomplete candidate falls back")
	assert_eq(result["outcome"], TownLayoutProviderScript.OUTCOME_MISSING_REQUIRED_STRUCTURES, "the reason is missing required structures")
	assert_eq(result["blueprint"]["sector_id"], "starting_town_hub", "the fallback blueprint is the fixture")


func test_fallback_blueprint_is_always_usable() -> void:
	# Even on fallback the returned town must validate and meet the guarantee.
	var result: Dictionary = TownLayoutProviderScript.resolve({"nope": 1}, _fixture())
	var validation: Dictionary = SectorBlueprintSchemaScript.validate(result["blueprint"])
	assert_eq(validation["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "the fallback town validates")
	assert_true(TownLayoutProviderScript.meets_required_structures(result["blueprint"])["ok"], "the fallback town meets the guarantee")


func test_default_town_prompt_documents_the_contract() -> void:
	var prompt: String = TownLayoutProviderScript.default_town_prompt()
	assert_true(prompt.contains("schema_version"), "the prompt names schema_version")
	for kind: String in ["house", "smithy", "armor_shop", "inn"]:
		assert_true(prompt.contains(kind), "the prompt names the required kind '%s'" % kind)
