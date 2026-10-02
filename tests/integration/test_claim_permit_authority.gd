extends GutTest

const StoreScript: Script = preload("res://server/sqlite_store.gd")
const AUTHORITY_PATH: String = "res://server/claim_permit_authority.gd"
var _store: SqliteStore
var _database: String


func before_each() -> void:
	_database = "test_claim_permit_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")


func after_each() -> void:
	if _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://" + _database + suffix)
		if FileAccess.file_exists(path):
			assert_eq(DirAccess.remove_absolute(path), OK)


func test_primary_owner_can_start_but_an_unpermitted_visitor_cannot() -> void:
	assert_true(ResourceLoader.exists(AUTHORITY_PATH), "the permission authority public seam exists")
	if not ResourceLoader.exists(AUTHORITY_PATH):
		return
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var allowed: Dictionary = authority.begin_interaction("owner-one", "plot-one", 1)
	assert_eq(allowed.outcome, "ok")
	assert_true(allowed.has("interaction_id"))
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "permission_denied")


func test_party_membership_requires_an_explicit_matching_permit() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_true(authority.has_method("update_memberships"), "trusted membership ingestion exists")
	assert_true(authority.has_method("apply_permit"), "explicit permit commands exist")
	if not authority.has_method("update_memberships") or not authority.has_method("apply_permit"):
		return
	assert_eq(authority.update_memberships("member-one", [{"kind": "party", "id": "party-one", "role": ""}], 0, "membership-one").outcome, "ok")
	assert_eq(authority.begin_interaction("member-one", "plot-one", 1).outcome, "permission_denied", "membership alone grants nothing")
	var grant: Dictionary = {
		"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "party", "id": "party-one", "role": ""}, "permission_bits": 1,
	}
	assert_eq(authority.apply_permit("owner-one", grant).outcome, "ok")
	assert_eq(authority.begin_interaction("member-one", "plot-one", 1).outcome, "ok")
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "permission_denied")
	assert_eq(authority.begin_interaction("member-one", "plot-one", 2).outcome, "permission_denied", "a permit grants only its explicit bits")


func test_membership_change_after_start_rejects_before_any_action_write() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(authority.update_memberships("member-one", [{"kind": "party", "id": "party-one", "role": ""}], 0, "membership-one").outcome, "ok")
	assert_eq(authority.apply_permit("owner-one", {
		"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "party", "id": "party-one", "role": ""}, "permission_bits": 1,
	}).outcome, "ok")
	var started: Dictionary = authority.begin_interaction("member-one", "plot-one", 1)
	assert_eq(started.outcome, "ok")
	assert_eq(_store.query("CREATE TABLE action_probe (id INTEGER PRIMARY KEY);").outcome, "ok")
	assert_eq(authority.update_memberships("member-one", [], 1, "membership-left").outcome, "ok")
	assert_true(authority.has_method("commit_interaction"), "final authority transaction seam exists")
	if not authority.has_method("commit_interaction"):
		return
	var calls: Array[int] = [0]
	var result: Dictionary = authority.commit_interaction("member-one", started.interaction_id, func() -> bool:
		calls[0] += 1
		return _store.query("INSERT INTO action_probe (id) VALUES (1);").outcome == "ok"
	)
	assert_eq(result.outcome, "stale_authority")
	assert_eq(calls[0], 0, "revocation is checked before calling any action writer")
	assert_eq(_store.query("SELECT id FROM action_probe;").rows.size(), 0)


func test_owner_final_gate_commits_once_and_rejects_another_actor() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(_store.query("CREATE TABLE action_probe (id INTEGER PRIMARY KEY);").outcome, "ok")
	var started: Dictionary = authority.begin_interaction("owner-one", "plot-one", 2)
	var writer: Callable = func() -> bool:
		return _store.query("INSERT INTO action_probe (id) VALUES (1);").outcome == "ok"
	assert_eq(authority.commit_interaction("visitor-one", started.interaction_id, writer).outcome, "interaction_actor_mismatch")
	assert_eq(_store.query("SELECT id FROM action_probe;").rows.size(), 0)
	assert_eq(authority.commit_interaction("owner-one", started.interaction_id, writer).outcome, "ok")
	assert_eq(authority.commit_interaction("owner-one", started.interaction_id, writer).outcome, "interaction_not_found")
	assert_eq(_store.query("SELECT id FROM action_probe;").rows, [{"id": 1}])


func test_final_action_query_failure_rolls_back_and_cancel_releases_handle() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(_store.query("CREATE TABLE action_probe (id INTEGER PRIMARY KEY);").outcome, "ok")
	var started: Dictionary = authority.begin_interaction("owner-one", "plot-one", 2)
	var result: Dictionary = authority.commit_interaction("owner-one", started.interaction_id, func() -> bool:
		_store.query("INSERT INTO action_probe (id) VALUES (1);")
		_store.query("INSERT INTO action_probe (id) VALUES (1);")
		return true
	)
	assert_eq(result.outcome, "transaction_failed")
	assert_eq(_store.query("SELECT id FROM action_probe;").rows.size(), 0)
	var cancelled: Dictionary = authority.begin_interaction("owner-one", "plot-one", 2)
	assert_eq(authority.cancel_interaction("owner-one", cancelled.interaction_id).outcome, "ok")
	assert_eq(authority.commit_interaction("owner-one", cancelled.interaction_id, func() -> bool: return true).outcome, "interaction_not_found")


func test_specific_commit_authorizer_requires_its_managed_transaction() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var started: Dictionary = authority.begin_interaction("owner-one", "plot-one", 1)
	assert_true(authority.has_method("authorize_commit"), "closed item batches can use the specific final authorizer")
	if not authority.has_method("authorize_commit"):
		return
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.authorize_commit("owner-one", started.interaction_id).outcome, "transaction_required")
	var check: Dictionary = {"outcome": "not_called"}
	var transaction: Dictionary = _store.transaction(func() -> bool:
		check.outcome = authority.authorize_commit("owner-one", started.interaction_id).outcome
		return check.outcome == "ok"
	)
	assert_eq(check.outcome, "ok")
	assert_eq(transaction.outcome, "ok")
	var observation: Dictionary = _store.dml_statement_counters()
	assert_eq(observation.observation_status, "OBSERVED")
	assert_eq(observation.totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0}, "the authorizer only reads authority")


func test_revoked_character_permit_rejects_final_commit_with_zero_write_attempts() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(authority.apply_permit("owner-one", {
		"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1,
	}).outcome, "ok")
	var started: Dictionary = authority.begin_interaction("visitor-one", "plot-one", 1)
	assert_eq(started.outcome, "ok")
	assert_eq(_store.query("CREATE TABLE action_probe (id INTEGER PRIMARY KEY);").outcome, "ok")
	assert_eq(authority.apply_permit("owner-one", {
		"schema_version": 1, "operation_id": "revoke-one", "plot_id": "plot-one", "expected_revision": 2,
		"action": "revoke", "subject": {"kind": "character", "id": "visitor-one", "role": ""},
	}).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var calls: Array[int] = [0]
	var result: Dictionary = authority.commit_interaction("visitor-one", started.interaction_id, func() -> bool:
		calls[0] += 1
		return _store.query("INSERT INTO action_probe (id) VALUES (1);").outcome == "ok"
	)
	assert_eq(result.outcome, "stale_authority")
	assert_eq(calls[0], 0)
	var observation: Dictionary = _store.dml_statement_counters()
	assert_eq(observation.observation_status, "OBSERVED")
	assert_eq(observation.totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	assert_eq(_store.query("SELECT id FROM action_probe;").rows.size(), 0)


func test_permit_receipt_replays_after_later_revision_and_restart_without_writes() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var intent: Dictionary = {
		"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1,
	}
	var original: Dictionary = authority.apply_permit("owner-one", intent)
	assert_eq(original.outcome, "ok")
	var later: Dictionary = intent.duplicate(true)
	later.operation_id = "permit-two"
	later.expected_revision = 2
	later.subject.id = "visitor-two"
	assert_eq(authority.apply_permit("owner-one", later).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var replay: Dictionary = authority.apply_permit("owner-one", intent)
	assert_eq(replay.outcome, "duplicate_rejected")
	assert_eq(replay.get("original_result"), original)
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")
	authority = authority_script.new(_store)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var recovered: Dictionary = authority.apply_permit("owner-one", intent)
	assert_eq(recovered.outcome, "duplicate_rejected")
	assert_eq(recovered.get("original_result"), original)
	var changed: Dictionary = intent.duplicate(true)
	changed.permission_bits = 2
	assert_eq(authority.apply_permit("owner-one", changed).outcome, "operation_conflict")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
