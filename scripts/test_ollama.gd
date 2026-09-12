extends SceneTree
## Headless smoke test for the local Ollama connection.
## Run with: godot --headless -s scripts/test_ollama.gd

const LocalLLMClientScript: GDScript = preload("res://shared/local_llm_client.gd")

const TEST_PROMPT: String = """
You are generating a mock 3/4-view (isometric) Zelda-style dungeon layout for a game prototype.
Respond with ONLY a single JSON object (no prose, no markdown fences) shaped like this:
{
  "start_room": {"x": 0, "y": 0},
  "tiles": [
    {"x": 0, "y": 0, "type": "floor"},
    {"x": 1, "y": 0, "type": "wall"}
  ],
  "quest_item": {"name": "small_key", "x": 3, "y": 2}
}
Keep the tile array small (under 20 entries). Output must be strictly valid JSON.
"""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_ollama()


func _test_ollama() -> void:
	var client: Node = LocalLLMClientScript.new()
	root.add_child(client)

	print("[test_ollama] Sending dungeon-layout prompt to Ollama...")
	var result: Dictionary = await client.generate_json(TEST_PROMPT)

	if result["success"]:
		print("[test_ollama] Success. Parsed JSON blueprint:")
		print(JSON.stringify(result["data"], "\t"))
	else:
		push_error("[test_ollama] Failed: %s" % result["error"])
		print("[test_ollama] Raw response: %s" % result["raw"])

	client.queue_free()
	quit()
