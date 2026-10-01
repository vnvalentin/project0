extends SceneTree
## Experiment 1360: drives the production SectorBlueprintService (3.0 s cutoff,
## zero retries, schema gate) and the production placement gate against the
## configured Ollama endpoint. Modes: `prompt <out>` writes the exact prompt;
## `sample <out> <count>` runs `count` sequential requests and writes results.

const ServerMainScript: Script = preload("res://server/server_main.gd")
const ServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const PlacementScript: Script = preload("res://shared/sector_detail_placement.gd")
const DetailScript: Script = preload("res://server/sector_detail_generation.gd")
const HubScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const SECTOR_ID: String = "sector-0--2"
const INGRESS: Vector3 = Vector3(4.4, 1.0, -440.1)


func _initialize() -> void:
	call_deferred("_run")


## Mirrors server_main._request_sector_from_boundary's prompt construction.
static func production_prompt(placement: Dictionary) -> String:
	var prompt: String = ServerMainScript._sector_generation_prompt(SECTOR_ID)
	prompt += "\nServer-owned placement: %s. Return local geometry only; do not override this placement. Connect the entry tile to traversable terrain extending at least two yards. Required local ingress: %s." % [JSON.stringify(placement), str(INGRESS - PlacementScript.grid_offset(SECTOR_ID) - Vector3(placement["detail_origin"]["x"], 0, placement["detail_origin"]["y"]))]
	return prompt


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var placement: Dictionary = PlacementScript.select(SECTOR_ID, INGRESS)
	var prompt: String = production_prompt(placement)
	if arguments.size() == 2 and arguments[0] == "prompt":
		_write(arguments[1], {"prompt": prompt, "sector_id": SECTOR_ID})
		quit(0)
		return
	if arguments.size() != 3 or arguments[0] != "sample":
		quit(2)
		return
	var service: Node = ServiceScript.new()
	root.add_child(service)
	await process_frame
	var town: Dictionary = HubScript.blueprint()
	var context: Dictionary = {"sector_id": SECTOR_ID, "placement": placement, "ingress": INGRESS}
	var samples: Array = []
	for index: int in int(arguments[2]):
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = await service.request_sector_blueprint(prompt, SECTOR_ID)
		var service_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		result["selected_profile"] = "WILDERNESS"
		var prepared: Dictionary = DetailScript.prepare(result, context, town)
		samples.append({
			"index": index,
			"request_outcome": String(result.get("request_outcome", "")),
			"validation_outcome": String(result.get("validation_outcome", "")),
			"source": String(result.get("source", "")),
			"detail": String(result.get("detail", "")).left(160),
			"timing": result.get("timing", {}),
			"service_wall_ms": service_ms,
			"placement_validation_outcome": String(prepared.get("placement_validation_outcome", "")),
			"final_source": String(prepared.get("source", "")),
		})
	_write(arguments[1], {"model": service._llm_client.model_name, "host": service._llm_client.ollama_host,
		"budget_ms": float(service._llm_client.request_timeout_sec) * 1000.0, "samples": samples})
	quit(0)


func _write(path: String, payload: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
