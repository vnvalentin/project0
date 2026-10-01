extends GutTest
## M0.4 public-seam contract tests: a client submits a physical interaction
## intent, never a reasoning-stat solution claim or an outcome.

const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const EnvironmentalServiceScript: Script = preload("res://server/environmental_interaction_service.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

const ACTOR: String = "character-1"

var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null
var _service: EnvironmentalInteractionService = null


func before_each() -> void:
	_relative_path = "test_mind_tool_interaction_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_LOCKED_GATE))
	_service = EnvironmentalServiceScript.new(
		_canon,
		_mutations,
		func() -> int: return 700,
		func(_from: Vector3, _to: Vector3) -> bool: return true
	)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _target_guid() -> String:
	return CanonEntityGuidScript.derive("sector-0-0", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "gate-1")


func _intent(verb: String = InteractionScript.VERB_LOCK_PICK, client_seq: int = 1) -> Dictionary:
	return InteractionScript.build_intent("sector-0-0", _target_guid(), verb, 0, Vector3.FORWARD, client_seq)


func test_lock_pick_intent_contains_solution_and_physical_context_only() -> void:
	var intent: Dictionary = InteractionScript.build_intent(
		"sector-0-0",
		"structure-gate-1",
		InteractionScript.VERB_LOCK_PICK,
		0,
		Vector3(0.0, 0.0, -1.0),
		1
	)
	var parsed: Dictionary = InteractionScript.parse_intent(intent)
	assert_eq(parsed["outcome"], InteractionScript.OUTCOME_OK)
	assert_eq(parsed["intent"]["verb"], InteractionScript.VERB_LOCK_PICK)
	assert_false(parsed["intent"].has("reasoning_stat"), "the solution intent has no reasoning gate")
	assert_false(parsed["intent"].has("success"), "the client cannot submit an outcome")


func test_interrupt_intent_is_an_accepted_physical_verb() -> void:
	var intent: Dictionary = InteractionScript.build_intent(
		"sector-0-0",
		"structure-gate-1",
		InteractionScript.VERB_INTERRUPT,
		0,
		Vector3.FORWARD,
		1
	)
	assert_eq(InteractionScript.parse_intent(intent)["outcome"], InteractionScript.OUTCOME_OK)


func test_reasoning_stat_and_outcome_fields_are_rejected() -> void:
	var forged: Dictionary = InteractionScript.build_intent(
		"sector-0-0",
		"structure-gate-1",
		InteractionScript.VERB_LOCK_PICK,
		0,
		Vector3.FORWARD,
		1
	)
	forged["reasoning_stat"] = 999
	assert_eq(InteractionScript.parse_intent(forged)["outcome"], InteractionScript.OUTCOME_INVALID)

	var outcome_forgery: Dictionary = forged.duplicate()
	outcome_forgery.erase("reasoning_stat")
	outcome_forgery["success"] = true
	assert_eq(InteractionScript.parse_intent(outcome_forgery)["outcome"], InteractionScript.OUTCOME_INVALID)


func test_low_reasoning_profile_unlocks_gate_when_physical_checks_pass() -> void:
	var result: Dictionary = _service.resolve_intent(ACTOR, Vector3(0.0, 0.0, 1.0), {"friction_profile": "fragile_agility", "kinetic_control": 16.0}, _intent())
	assert_eq(result["status"], EnvironmentalServiceScript.STATUS_ACCEPTED)
	assert_eq(result["execution_profile"], "agile")
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1)


func test_reach_and_line_of_sight_are_server_owned_rejections() -> void:
	var too_far: Dictionary = _service.resolve_intent(ACTOR, Vector3(0.0, 0.0, 3.0), {}, _intent())
	assert_eq(too_far["reason"], EnvironmentalServiceScript.REASON_OUT_OF_REACH)
	var blocked: Dictionary = _service.resolve_intent(ACTOR, Vector3(0.0, 0.0, 1.0), {}, _intent(InteractionScript.VERB_INTERRUPT, 2), func(_from: Vector3, _to: Vector3) -> bool: return false)
	assert_eq(blocked["reason"], EnvironmentalServiceScript.REASON_NO_LINE_OF_SIGHT)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 0)


func test_physical_profiles_change_execution_without_changing_solution_permission() -> void:
	var agile: Dictionary = _service.execution_profile({"friction_profile": "fragile_agility", "kinetic_control": 16.0})
	var heavy: Dictionary = _service.execution_profile({"friction_profile": "massive_bulk", "kinetic_control": 4.0})
	assert_eq(agile["permission"], heavy["permission"], "physical profiles do not gate the solution")
	assert_ne(agile["execution_ticks"], heavy["execution_ticks"], "physical profiles change execution timing")


func test_reach_is_inclusive_two_yards_on_the_ground_plane() -> void:
	var at_limit: Dictionary = _service.resolve_intent(ACTOR, Vector3(0.0, 1.0, 2.0), {}, _intent())
	assert_eq(at_limit["status"], EnvironmentalServiceScript.STATUS_ACCEPTED, "2.0 yd on the ground from a y=1 Character origin is in reach")


func test_reach_just_beyond_two_yards_is_rejected_without_a_write() -> void:
	var beyond: Dictionary = _service.resolve_intent(ACTOR, Vector3(0.0, 1.0, 2.01), {}, _intent())
	assert_eq(beyond["reason"], EnvironmentalServiceScript.REASON_OUT_OF_REACH)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 0)


func test_unsupported_verb_cannot_mutate_gate() -> void:
	var result: Dictionary = _service.resolve_intent(ACTOR, Vector3(0.0, 0.0, 1.0), {}, _intent("solve_riddle"))
	assert_eq(result["reason"], EnvironmentalServiceScript.REASON_INVALID_INTENT)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 0)
