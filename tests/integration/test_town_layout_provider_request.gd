extends GutTest
## Public-seam integration test for Slice 026's async request path
## (TownLayoutProvider.request_town): with an injected fake LLM client, a valid
## candidate is used and any failure or invalid output falls back to the hub
## fixture — no live Ollama. See docs/slices/026-llm-town-generation.md.

const TownLayoutProviderScript: Script = preload("res://server/town_layout_provider.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")


## Stand-in for shared/local_llm_client.gd: a Node exposing the same
## `generate_json(prompt) -> Dictionary` coroutine so request_town can be
## exercised without a live Ollama. Awaits one frame to stay a real coroutine.
class _FakeLLMClient extends Node:
	var canned: Dictionary = {}
	func generate_json(_prompt: String) -> Dictionary:
		await get_tree().process_frame
		return canned


func _fixture() -> Dictionary:
	return StartingTownHubFixtureScript.blueprint()


func _make_client(canned: Dictionary) -> Node:
	var client: _FakeLLMClient = _FakeLLMClient.new()
	client.canned = canned
	add_child_autofree(client)
	return client


func test_request_town_uses_a_valid_llm_candidate() -> void:
	var candidate: Dictionary = _fixture()
	candidate["sector_id"] = "llm_town"
	var client: Node = _make_client({"success": true, "data": candidate, "raw": "", "error": ""})
	var provider: RefCounted = TownLayoutProviderScript.new()

	var result: Dictionary = await provider.request_town(client, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_LLM, "a valid LLM candidate is used")
	assert_eq(result["blueprint"]["sector_id"], "llm_town", "the resolved town is the LLM candidate")


func test_request_town_falls_back_on_transport_failure() -> void:
	var client: Node = _make_client({"success": false, "data": null, "raw": "", "error": "connection refused"})
	var provider: RefCounted = TownLayoutProviderScript.new()

	var result: Dictionary = await provider.request_town(client, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "a transport failure falls back")
	assert_eq(result["outcome"], TownLayoutProviderScript.OUTCOME_TRANSPORT_ERROR, "the outcome is a transport error")
	assert_eq(result["blueprint"]["sector_id"], "starting_town_hub", "the fallback town is the fixture")


func test_request_town_falls_back_on_invalid_llm_output() -> void:
	var client: Node = _make_client({"success": true, "data": {"not": "a blueprint"}, "raw": "", "error": ""})
	var provider: RefCounted = TownLayoutProviderScript.new()

	var result: Dictionary = await provider.request_town(client, _fixture())
	assert_eq(result["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "invalid LLM output falls back")
	assert_eq(result["blueprint"]["sector_id"], "starting_town_hub", "the fallback town is the fixture")


func test_request_town_emits_town_resolved_once() -> void:
	var client: Node = _make_client({"success": false, "data": null, "raw": "", "error": "down"})
	var provider: RefCounted = TownLayoutProviderScript.new()
	var captured: Array = []
	provider.town_resolved.connect(func(result: Dictionary) -> void: captured.append(result))

	await provider.request_town(client, _fixture())
	assert_eq(captured.size(), 1, "town_resolved fires exactly once")
	assert_eq(captured[0]["source"], TownLayoutProviderScript.SOURCE_FALLBACK, "the signal carries the resolution")
