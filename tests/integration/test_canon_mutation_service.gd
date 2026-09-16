extends GutTest
## Slice 096 (P-013): the server-authoritative mutation resolution service.
## An untrusted client intent becomes a server-owned CanonMutationEvent — the
## service stamps actor/event_id/tick and applies it through the Slice 050
## repository over a real SQLite-backed canonical sector (Slice 045/095).

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const CanonMutationServiceScript: Script = preload("res://server/canon_mutation_service.gd")
const CanonMutationIntentScript: Script = preload("res://shared/canon_mutation_intent.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

const ACTOR: String = "character-1"

var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null
var _service: CanonMutationService = null


func before_each() -> void:
	_relative_path = "test_canon_mutation_service_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE))
	# A fixed clock keeps event ticks deterministic across the test.
	_service = CanonMutationServiceScript.new(_mutations, func() -> int: return 4242)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _target_guid() -> String:
	return CanonEntityGuidScript.derive("sector-0-0", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "village_hall")


func _intent(overrides: Dictionary = {}) -> Dictionary:
	var intent: Dictionary = CanonMutationIntentScript.build("sector-0-0", _target_guid(), "defeat_leader", 0, 1, {"leader": "baron"})
	for key: String in overrides:
		intent[key] = overrides[key]
	return intent


func test_valid_intent_is_accepted_and_bumps_revision() -> void:
	var result: Dictionary = _service.resolve_intent(ACTOR, _intent())
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	assert_eq(result["applied_revision"], 1)
	assert_eq(result["client_seq"], 1)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1)


func test_server_stamps_actor_and_ignores_client_supplied_identity() -> void:
	# The stored mutation records the server-authenticated actor, not the client.
	assert_eq(_service.resolve_intent(ACTOR, _intent())["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	var history: Array = _mutations.list_mutations("sector-0-0")["mutations"]
	assert_eq(history.size(), 1)
	assert_eq(history[0]["actor_player_id"], ACTOR)
	assert_eq(history[0]["server_tick"], 4242, "the server clock, not the client, sets the tick")


func test_sequential_intents_apply_at_advancing_revisions() -> void:
	assert_eq(_service.resolve_intent(ACTOR, _intent())["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	var second: Dictionary = _intent({"client_seq": 2, "expected_revision": 1})
	var result: Dictionary = _service.resolve_intent(ACTOR, second)
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	assert_eq(result["applied_revision"], 2)


func test_replayed_intent_is_idempotent() -> void:
	assert_eq(_service.resolve_intent(ACTOR, _intent())["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	var replay: Dictionary = _service.resolve_intent(ACTOR, _intent())
	assert_eq(replay["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	assert_eq(replay["applied_revision"], 1, "a replayed intent resolves to the original revision")
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1, "a replay does not advance the revision")


func test_same_sequence_different_content_is_rejected_as_conflict() -> void:
	assert_eq(_service.resolve_intent(ACTOR, _intent())["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	var forged: Dictionary = _intent({"payload": {"leader": "impostor"}})
	var result: Dictionary = _service.resolve_intent(ACTOR, forged)
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_REJECTED)
	assert_eq(result["reason"], CanonMutationRepositoryScript.OUTCOME_CONFLICT)


func test_unknown_target_is_rejected() -> void:
	var result: Dictionary = _service.resolve_intent(ACTOR, _intent({"target_guid": "structure-nope"}))
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_REJECTED)
	assert_eq(result["reason"], CanonMutationRepositoryScript.OUTCOME_TARGET_NOT_FOUND)


func test_non_canon_sector_is_rejected() -> void:
	var result: Dictionary = _service.resolve_intent(ACTOR, _intent({"sector_id": "sector-9-9"}))
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_REJECTED)
	assert_eq(result["reason"], CanonMutationRepositoryScript.OUTCOME_SECTOR_NOT_CANON)


func test_stale_revision_is_rejected() -> void:
	assert_eq(_service.resolve_intent(ACTOR, _intent())["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	var stale: Dictionary = _intent({"client_seq": 2, "expected_revision": 0})
	var result: Dictionary = _service.resolve_intent(ACTOR, stale)
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_REJECTED)
	assert_eq(result["reason"], CanonMutationRepositoryScript.OUTCOME_REVISION_MISMATCH)


func test_forged_intent_with_server_field_is_rejected() -> void:
	var forged: Dictionary = _intent()
	forged["actor_player_id"] = "somebody-else"
	var result: Dictionary = _service.resolve_intent(ACTOR, forged)
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_REJECTED)
	assert_eq(result["reason"], CanonMutationServiceScript.REASON_INVALID_INTENT)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 0, "a forged intent is not stored")


func test_empty_actor_is_rejected() -> void:
	var result: Dictionary = _service.resolve_intent("", _intent())
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_REJECTED)
	assert_eq(result["reason"], CanonMutationServiceScript.REASON_INVALID_ACTOR)


func test_two_actors_same_sequence_get_distinct_events() -> void:
	assert_eq(_service.resolve_intent("character-1", _intent())["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	# A second actor's client_seq 1 must not collide with the first actor's event.
	var other: Dictionary = _intent({"expected_revision": 1})
	var result: Dictionary = _service.resolve_intent("character-2", other)
	assert_eq(result["status"], CanonMutationServiceScript.STATUS_ACCEPTED)
	assert_eq(result["applied_revision"], 2)
