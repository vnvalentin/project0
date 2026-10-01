extends "res://scripts/exp1232_gate_fixture.gd"
## Experiment #1234 server fixture. Records a boot identity, journey evidence and
## Canon reload events stamped with Canon write and content-generation counters,
## and the approved snapshot (raw base JSON, ordered mutations, reconstructed
## structure entities incl. server collider state) after the unlock commit and at
## every reload. An orderly shutdown is requested through a file and runs the
## engine's normal quit path.

const Exp1234Lookup: Script = preload("res://shared/sector_geometry_lookup.gd")

var _exp1234_shutdown_requested: bool = false


func _initialize() -> void:
	super()
	_exp_observation["boot"] = {"pid": OS.get_process_id(), "boot_id": Crypto.new().generate_random_bytes(8).hex_encode()}
	_exp_observation["journey_evidence"] = []
	_exp_observation["reload_events"] = []
	process_frame.connect(_exp1234_poll_shutdown)


func _start_server() -> void:
	await super()
	_exp_observation["boot"]["after_start"] = _exp1234_counters()
	_exp_observation["boot"]["restored_journeys"] = _journey_repository.load_all().get("records", []).size() if _journey_repository != null else -1
	_exp_write()


func _on_journey_evidence(kind: String, payload: Dictionary) -> void:
	super(kind, payload)
	var entry: Dictionary = payload.duplicate(true)
	entry["kind"] = kind
	entry["counters"] = _exp1234_counters()
	_exp_observation["journey_evidence"].append(entry)
	_exp_write()


func _record_canon_reload(peer_id: int, sector_id: String, presented: Dictionary) -> void:
	var before: int = _canon_reload_events.size()
	super(peer_id, sector_id, presented)
	if _canon_reload_events.size() == before:
		return
	var event: Dictionary = _canon_reload_events.back().duplicate(true)
	event["counters"] = _exp1234_counters()
	event["snapshot"] = _exp1234_snapshot()
	_exp_observation["reload_events"].append(event)
	_exp_write()


func _resolve_environmental_interaction(sender_peer_id: int, intent: Dictionary) -> Dictionary:
	var resolution: Dictionary = super(sender_peer_id, intent)
	if resolution.get("reason") == "ok" and not _exp_observation.has("expected_snapshot"):
		_exp_observation["expected_snapshot"] = _exp1234_snapshot()
		_exp_write()
	return resolution


func _exp1234_counters() -> Dictionary:
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	return {"canon_writes": store.canon_write_counters() if store != null else null, "generation_count": content_generation_count()}


func _exp1234_snapshot() -> Dictionary:
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	var raw: Dictionary = store.query_with_bindings("SELECT blueprint_json FROM canon_sectors WHERE sector_id = ?;", [EXP1231_HUB])
	var base_json: Variant = String(raw["rows"][0]["blueprint_json"]) if raw["outcome"] == "ok" and not raw["rows"].is_empty() else null
	var mutations: Array = _canon_mutation_repository.list_mutations(EXP1231_HUB).get("mutations", [])
	var entities: Dictionary = {}
	if base_json is String:
		var effective: Dictionary = Exp1231Resolver.resolve_effective_blueprint(JSON.parse_string(base_json), mutations)
		for structure: Dictionary in effective.get("structures", []):
			var structure_id: String = String(structure["structure_id"])
			var footprint: Vector2i = Exp1234Lookup.structure_footprint(String(structure.get("kind", "")))
			var blocked: int = 0
			for dx: int in range(-footprint.x, footprint.x + 1):
				for dy: int in range(-footprint.y, footprint.y + 1):
					if _town_collision != null and _town_collision.is_blocked(Vector2i(int(structure["x"]) + dx, int(structure["y"]) + dy)):
						blocked += 1
			entities[Exp1231Guid.derive(EXP1231_HUB, Exp1231Guid.ENTITY_CLASS_STRUCTURE, structure_id)] = {
				"structure_id": structure_id, "kind": String(structure.get("kind", "")),
				"x": int(structure["x"]), "y": int(structure["y"]), "facing_degrees": float(structure.get("facing_degrees", 0.0)),
				"footprint": [footprint.x, footprint.y], "collider_blocked_cells": blocked,
				"unlocked": bool(structure.get("unlocked", false)),
			}
	return {"base_json": base_json, "mutations": mutations, "entities": entities}


func _exp1234_poll_shutdown() -> void:
	var path: String = OS.get_environment("EXP1234_SHUTDOWN")
	if _exp1234_shutdown_requested or path.is_empty() or not FileAccess.file_exists(path):
		return
	_exp1234_shutdown_requested = true
	_exp_observation["orderly_shutdown"] = {"requested": true, "counters": _exp1234_counters()}
	_exp_write()
	quit(0)
