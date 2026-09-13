extends SceneTree
## Manual diagnostic probe for the local Ollama connection. Requires a live
## Ollama server with a loaded model and real GPU inference, so it can never
## be a deterministic, hermetic CI test (see DT-006) — it is not registered
## with scripts/run_gut_validation.sh and must be run by hand.
## Run with: godot --headless -s scripts/probe_ollama.gd

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
	await _probe_ollama()


func _probe_ollama() -> void:
	var client: Node = LocalLLMClientScript.new()
	root.add_child(client)

	print("[probe_ollama] Sending dungeon-layout prompt to Ollama...")
	var result: Dictionary = await client.generate_json(TEST_PROMPT)

	if result["success"]:
		print("[probe_ollama] Success. Parsed JSON blueprint:")
		print(JSON.stringify(result["data"], "\t"))
	else:
		push_error("[probe_ollama] Failed: %s" % result["error"])
		print("[probe_ollama] Raw response: %s" % result["raw"])

	client.queue_free()
	quit()
