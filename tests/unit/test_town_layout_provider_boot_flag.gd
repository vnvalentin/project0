extends GutTest
## Public-seam unit tests for Slice 052's default-off LLM-at-boot flag and the
## boot-level town resolution helper on server/town_layout_provider.gd. Proves
## the flag is ON only for the literal "1" (matching the repo's existing
## PROJECT0_E2E_DISABLE_TOWN_COLLISION == "1" convention) and that
## resolve_boot_town() never touches the injected client when the flag is off.
## See docs/slices/052-f026-llm-town-at-boot.md.

const TownLayoutProviderScript: Script = preload("res://server/town_layout_provider.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")

const ENV_FLAG: String = "PROJECT0_LLM_TOWN_AT_BOOT"


## Stand-in async LLM client mirroring
## tests/integration/test_town_layout_provider_request.gd's _FakeLLMClient, plus
## a call counter so a test can assert the client was never invoked.
class _FakeLLMClient extends Node:
	var canned: Dictionary = {}
	var call_count: int = 0
	func generate_json(_prompt: String) -> Dictionary:
		call_count += 1
		await get_tree().process_frame
		return canned


func after_each() -> void:
	OS.set_environment(ENV_FLAG, "")


func _fixture() -> Dictionary:
	return StartingTownHubFixtureScript.blueprint()


func _make_client(canned: Dictionary) -> Node:
	var client: _FakeLLMClient = _FakeLLMClient.new()
	client.canned = canned
	add_child_autofree(client)
	return client


func test_llm_at_boot_enabled_is_false_when_unset() -> void:
	OS.set_environment(ENV_FLAG, "")
	assert_false(TownLayoutProviderScript.llm_at_boot_enabled(), "unset env var means the flag is off")


func test_llm_at_boot_enabled_is_false_for_other_values() -> void:
	for value in ["true", "0", "yes", "TRUE", "on"]:
		OS.set_environment(ENV_FLAG, value)
		assert_false(TownLayoutProviderScript.llm_at_boot_enabled(), "value '%s' must not enable the flag" % value)


func test_llm_at_boot_enabled_is_true_only_for_literal_one() -> void:
	OS.set_environment(ENV_FLAG, "1")
	assert_true(TownLayoutProviderScript.llm_at_boot_enabled(), "the literal '1' enables the flag")


func test_resolve_boot_town_off_returns_fixture_without_calling_client() -> void:
	var client: _FakeLLMClient = _make_client({"success": true, "data": _fixture(), "raw": "", "error": ""})
	var result: Dictionary = await TownLayoutProviderScript.resolve_boot_town(false, client, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "flag off always resolves to the fallback source")
	assert_eq(result["blueprint"]["sector_id"], "starting_town_hub", "flag off uses the fixture blueprint")
	assert_eq(client.call_count, 0, "flag off never calls the injected LLM client")


func test_resolve_boot_town_on_with_valid_candidate_uses_llm() -> void:
	var candidate: Dictionary = _fixture()
	candidate["sector_id"] = "llm_boot_town"
	var client: _FakeLLMClient = _make_client({"success": true, "data": candidate, "raw": "", "error": ""})

	var result: Dictionary = await TownLayoutProviderScript.resolve_boot_town(true, client, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_LLM, "a valid candidate is used when the flag is on")
	assert_eq(result["blueprint"]["sector_id"], "llm_boot_town", "the resolved town is the LLM candidate")
	assert_eq(client.call_count, 1, "flag on calls the injected LLM client exactly once")


func test_resolve_boot_town_on_with_failing_client_falls_back() -> void:
	var client: _FakeLLMClient = _make_client({"success": false, "data": null, "raw": "", "error": "connection refused"})

	var result: Dictionary = await TownLayoutProviderScript.resolve_boot_town(true, client, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "a failing client falls back")
	assert_eq(result["blueprint"]["sector_id"], "starting_town_hub", "the fallback town is the fixture")
