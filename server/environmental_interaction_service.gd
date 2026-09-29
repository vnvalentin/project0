extends RefCounted
class_name EnvironmentalInteractionService
## M0.4 server-only resolver for the locked structural gate fixture. The client
## supplies a solution verb; this service owns target lookup, reach, line of
## sight, physical execution profile, and the atomic Canon mutation.

const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")

const MAX_REACH: float = 2.0
const MUTATION_SCHEMA_VERSION: int = 1
const MUTATION_KIND_UNLOCK_GATE: String = "unlock_gate"

const STATUS_ACCEPTED: String = "accepted"
const STATUS_REJECTED: String = "rejected"
const REASON_INVALID_ACTOR: String = "invalid_actor"
const REASON_INVALID_INTENT: String = "invalid_intent"
const REASON_SECTOR_NOT_CANON: String = "sector_not_canon"
const REASON_TARGET_NOT_FOUND: String = "target_not_found"
const REASON_TARGET_NOT_LOCKED_GATE: String = "target_not_locked_gate"
const REASON_OUT_OF_REACH: String = "out_of_reach"
const REASON_NO_LINE_OF_SIGHT: String = "no_line_of_sight"
const REASON_LINE_OF_SIGHT_UNAVAILABLE: String = "line_of_sight_unavailable"
const REASON_ALREADY_UNLOCKED: String = "already_unlocked"

var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null
var _clock: Callable = Callable()
var _line_of_sight: Callable = Callable()


## line_of_sight receives actor and target world positions and must return bool.
## A missing query fails closed; production wiring must supply a server physics
## query rather than allowing a client-provided visibility claim.
func _init(canon: CanonRepository, mutations: CanonMutationRepository, clock: Callable, line_of_sight: Callable = Callable()) -> void:
	_canon = canon
	_mutations = mutations
	_clock = clock
	_line_of_sight = line_of_sight


func resolve_intent(
	actor_player_id: String,
	actor_position: Vector3,
	physical_outputs: Dictionary,
	raw_intent: Variant,
	line_of_sight_override: Callable = Callable()
) -> Dictionary:
	var client_seq: int = int(raw_intent.get("client_seq", -1)) if raw_intent is Dictionary else -1
	if actor_player_id.is_empty() or not actor_position.is_finite():
		return _rejected(REASON_INVALID_ACTOR, client_seq)
	var parsed: Dictionary = InteractionScript.parse_intent(raw_intent)
	if parsed["outcome"] != InteractionScript.OUTCOME_OK:
		return _rejected(REASON_INVALID_INTENT, client_seq)
	var intent: Dictionary = parsed["intent"]
	var target: Dictionary = _find_target(intent["sector_id"], intent["target_guid"])
	if target.is_empty():
		return _rejected(REASON_TARGET_NOT_FOUND, client_seq)
	if target["kind"] != "locked_gate":
		return _rejected(REASON_TARGET_NOT_LOCKED_GATE, client_seq)
	if _is_unlocked(intent["sector_id"], intent["target_guid"]):
		return _rejected(REASON_ALREADY_UNLOCKED, client_seq)
	var target_position: Vector3 = target["position"]
	if actor_position.distance_to(target_position) > MAX_REACH:
		return _rejected(REASON_OUT_OF_REACH, client_seq)
	var visibility_query: Callable = line_of_sight_override if line_of_sight_override.is_valid() else _line_of_sight
	if not visibility_query.is_valid():
		return _rejected(REASON_LINE_OF_SIGHT_UNAVAILABLE, client_seq)
	if not bool(visibility_query.call(actor_position, target_position)):
		return _rejected(REASON_NO_LINE_OF_SIGHT, client_seq)

	var execution: Dictionary = execution_profile(physical_outputs)
	var event_id: String = _event_id(actor_player_id, client_seq)
	var event: Dictionary = {
		"schema_version": MUTATION_SCHEMA_VERSION,
		"event_id": event_id,
		"sector_id": intent["sector_id"],
		"target_guid": intent["target_guid"],
		"mutation_kind": MUTATION_KIND_UNLOCK_GATE,
		"actor_player_id": actor_player_id,
		"server_tick": int(_clock.call()),
		"expected_revision": intent["expected_revision"],
		"payload": {
			"unlocked": true,
			"verb": intent["verb"],
			"execution_profile": execution["profile"],
			"execution_ticks": execution["execution_ticks"],
		},
	}
	var mutation: Dictionary = _mutations.apply_mutation(event)
	if mutation["outcome"] != CanonMutationRepositoryScript.OUTCOME_OK and mutation["outcome"] != CanonMutationRepositoryScript.OUTCOME_IDEMPOTENT:
		return _rejected(String(mutation["outcome"]), client_seq)
	return {
		"status": STATUS_ACCEPTED,
		"reason": mutation["outcome"],
		"client_seq": client_seq,
		"event_id": event_id,
		"execution_profile": execution["profile"],
		"execution_ticks": execution["execution_ticks"],
		"applied_revision": int(mutation.get("applied_revision", -1)),
	}


## Converts existing server-derived physical outputs into execution timing only.
## Permission is deliberately invariant across profiles.
func execution_profile(physical_outputs: Dictionary) -> Dictionary:
	var profile: String = String(physical_outputs.get("friction_profile", "standard"))
	if profile == "fragile_agility":
		return {"permission": true, "profile": "agile", "execution_ticks": 30}
	if profile == "massive_bulk":
		return {"permission": true, "profile": "heavy", "execution_ticks": 45}
	return {"permission": true, "profile": "standard", "execution_ticks": 40}


func _find_target(sector_id: String, target_guid: String) -> Dictionary:
	if _canon == null:
		return {}
	var sector_result: Dictionary = _canon.get_canonical_sector(sector_id)
	if sector_result["outcome"] != CanonRepositoryScript.OUTCOME_OK:
		return {}
	var blueprint: Dictionary = sector_result["sector"]["blueprint"]
	for entry: Variant in blueprint.get("structures", []):
		if not (entry is Dictionary):
			continue
		var structure: Dictionary = entry
		var structure_id: String = String(structure.get("structure_id", ""))
		if CanonEntityGuidScript.derive(sector_id, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, structure_id) == target_guid:
			return {
				"kind": String(structure.get("kind", "")),
				"position": Vector3(float(structure.get("x", 0.0)), 0.0, float(structure.get("y", 0.0))),
			}
	return {}


func _is_unlocked(sector_id: String, target_guid: String) -> bool:
	if _mutations == null:
		return false
	var history: Dictionary = _mutations.list_mutations(sector_id)
	if history["outcome"] != CanonMutationRepositoryScript.OUTCOME_OK:
		return false
	for mutation: Dictionary in history["mutations"]:
		if mutation["target_guid"] == target_guid and mutation["mutation_kind"] == MUTATION_KIND_UNLOCK_GATE and bool(mutation["payload"].get("unlocked", false)):
			return true
	return false


func _event_id(actor_player_id: String, client_seq: int) -> String:
	return "gate-%s" % ("%s\u0001%d" % [actor_player_id, client_seq]).sha256_text().substr(0, 32)


func _rejected(reason: String, client_seq: int) -> Dictionary:
	return {"status": STATUS_REJECTED, "reason": reason, "client_seq": client_seq, "applied_revision": -1}
