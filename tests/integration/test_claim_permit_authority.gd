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


func test_membership_receipt_does_not_restore_old_membership_on_replay() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(authority.apply_permit("owner-one", {
		"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "party", "id": "party-one", "role": ""}, "permission_bits": 1,
	}).outcome, "ok")
	var membership: Array = [{"kind": "party", "id": "party-one", "role": ""}]
	var original: Dictionary = authority.update_memberships("member-one", membership, 0, "joined-once")
	assert_eq(original.outcome, "ok")
	assert_eq(authority.update_memberships("member-one", [], 1, "left-once").outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var replay: Dictionary = authority.update_memberships("member-one", membership, 0, "joined-once")
	assert_eq(replay.outcome, "duplicate_rejected")
	assert_eq(replay.get("original_result"), original)
	assert_eq(authority.begin_interaction("member-one", "plot-one", 1).outcome, "permission_denied", "old events cannot restore revoked membership")
	assert_eq(authority.update_memberships("member-one", [], 0, "joined-once").outcome, "operation_conflict")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})


func test_permission_audit_retains_canonical_intent_and_rejects_corrupt_receipt() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var intent: Dictionary = {
		"schema_version": 1, "operation_id": "permit-audit", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1,
	}
	assert_eq(authority.apply_permit("owner-one", intent).outcome, "ok")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")
	authority = authority_script.new(_store)
	var audit: Dictionary = _store.query_with_bindings("SELECT actor_scope, request_json, request_fingerprint, result_revision, target_id FROM permission_operation_receipts WHERE operation_id = ?;", ["permit-audit"])
	assert_eq(audit.outcome, "ok", "audit records retain the actual accepted intent, not only an opaque digest")
	if audit.outcome != "ok":
		return
	assert_eq(audit.rows.size(), 1)
	assert_eq(audit.rows[0].actor_scope, JSON.stringify(["character", "owner-one"]))
	assert_eq(audit.rows[0].request_json, JSON.stringify(["permit", intent]))
	assert_eq(audit.rows[0].request_fingerprint, String(audit.rows[0].request_json).sha256_text())
	assert_eq(audit.rows[0].result_revision, 2)
	assert_eq(audit.rows[0].target_id, "plot-one")
	assert_eq(_store.query_with_bindings("UPDATE permission_operation_receipts SET request_json = ? WHERE operation_id = ?;", ["[]", "permit-audit"]).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.apply_permit("owner-one", intent).outcome, "invalid_persisted_state")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})


func test_provisioning_has_an_immutable_receipt_before_current_claim_checks() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	var original: Dictionary = authority.register_claim("plot-one", "owner-one", "provision-one")
	assert_eq(original.outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var replay: Dictionary = authority.register_claim("plot-one", "owner-one", "provision-one")
	assert_eq(replay.outcome, "duplicate_rejected")
	assert_eq(replay.get("original_result"), original)
	assert_eq(authority.register_claim("plot-two", "owner-one", "provision-one").outcome, "operation_conflict")
	assert_eq(authority.register_claim("plot-one", "owner-two", "provision-other").outcome, "claim_conflict")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	var audit: Dictionary = _store.query_with_bindings("SELECT actor_scope, request_json FROM permission_operation_receipts WHERE operation_id = ?;", ["provision-one"])
	assert_eq(audit.rows.size(), 1)
	if audit.rows.size() != 1:
		return
	assert_eq(audit.rows[0].actor_scope, JSON.stringify(["provision"]))
	assert_eq(audit.rows[0].request_json, JSON.stringify(["register_claim", "plot-one", "owner-one", "provision-one"]))


func test_primary_owner_transfer_invalidates_old_handles_and_survives_reopen() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	var provision: Dictionary = authority.register_claim("plot-one", "owner-one", "provision-one")
	assert_eq(provision.outcome, "ok")
	assert_eq(authority.apply_permit("owner-one", {
		"schema_version": 1, "operation_id": "steward", "plot_id": "plot-one", "expected_revision": 1,
		"action": "grant", "subject": {"kind": "character", "id": "steward-one", "role": ""}, "permission_bits": 63,
	}).outcome, "ok")
	assert_eq(authority.apply_permit("owner-one", {
		"schema_version": 1, "operation_id": "visitor", "plot_id": "plot-one", "expected_revision": 2,
		"action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1,
	}).outcome, "ok")
	var started: Dictionary = authority.begin_interaction("owner-one", "plot-one", 1)
	var intent: Dictionary = {"schema_version": 1, "operation_id": "transfer-one", "plot_id": "plot-one", "expected_revision": 3, "new_owner_character_id": "owner-two"}
	assert_true(authority.has_method("transfer_claim"), "primary-owner transfer is an atomic public command")
	if not authority.has_method("transfer_claim"):
		return
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.transfer_claim("steward-one", intent).outcome, "permission_denied", "even all explicit bits cannot transfer another primary owner's plot")
	assert_eq(authority.transfer_claim("visitor-one", intent).outcome, "permission_denied")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	var original: Dictionary = authority.transfer_claim("owner-one", intent)
	assert_eq(original.outcome, "ok")
	assert_eq(_store.dml_statement_counters().totals.committed, {"insert": 1, "replace": 0, "update": 1, "delete": 0})
	assert_eq(authority.commit_interaction("owner-one", started.interaction_id, func() -> bool: return true).outcome, "stale_authority")
	assert_eq(authority.begin_interaction("owner-one", "plot-one", 1).outcome, "permission_denied")
	assert_eq(authority.begin_interaction("owner-two", "plot-one", 63).outcome, "ok")
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "ok", "explicit grants survive until explicitly revoked")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")
	authority = authority_script.new(_store)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.get_claim("plot-one").claim.owner_character_id, "owner-two")
	var replay: Dictionary = authority.transfer_claim("owner-one", intent)
	assert_eq(replay.outcome, "duplicate_rejected")
	assert_eq(replay.get("original_result"), original)
	var initial: Dictionary = authority.register_claim("plot-one", "owner-one", "provision-one")
	assert_eq(initial.outcome, "duplicate_rejected")
	assert_eq(initial.get("original_result"), provision)
	var changed: Dictionary = intent.duplicate(true)
	changed.new_owner_character_id = "owner-three"
	assert_eq(authority.transfer_claim("owner-one", changed).outcome, "operation_conflict")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})


func test_corrupt_receipt_result_cannot_replace_the_original_accepted_result() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	var commands: Array = [
		["register_claim", ["plot-one", "owner-one", "provision-one"]],
		["update_memberships", ["member-one", [], 0, "membership-one"]],
		["apply_permit", ["owner-one", {"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1, "action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1}]],
		["transfer_claim", ["owner-one", {"schema_version": 1, "operation_id": "transfer-one", "plot_id": "plot-one", "expected_revision": 2, "new_owner_character_id": "owner-two"}]],
	]
	var originals: Array[Dictionary] = []
	for command: Array in commands:
		var result: Dictionary = authority.callv(command[0], command[1])
		assert_eq(result.outcome, "ok")
		originals.append(result)
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")
	authority = authority_script.new(_store)
	for index: int in range(commands.size()):
		var original: Dictionary = originals[index]
		assert_eq(_store.query_with_bindings("UPDATE permission_operation_receipts SET target_id = ? WHERE operation_id = ?;", ["different-valid-target", original.operation_id]).outcome, "ok")
		assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
		var changed_target: Dictionary = authority.callv(commands[index][0], commands[index][1])
		assert_eq(changed_target.outcome, "invalid_persisted_state", commands[index][0] + " must bind the retained target to original intent")
		assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
		assert_eq(_store.query_with_bindings("UPDATE permission_operation_receipts SET target_id = ?, result_revision = ? WHERE operation_id = ?;", [original.target_id, original.revision + 1, original.operation_id]).outcome, "ok")
		assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
		var changed_revision: Dictionary = authority.callv(commands[index][0], commands[index][1])
		assert_eq(changed_revision.outcome, "invalid_persisted_state", commands[index][0] + " must bind the retained revision to original expectations")
		assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
		assert_eq(_store.query_with_bindings("UPDATE permission_operation_receipts SET result_revision = ? WHERE operation_id = ?;", [original.revision, original.operation_id]).outcome, "ok")


func test_final_receipt_constraint_rolls_back_grant_and_claim_revision() -> void:
	assert_eq(_store.query("CREATE TABLE permission_operation_receipts (actor_scope TEXT NOT NULL, operation_id TEXT NOT NULL CHECK(operation_id <> 'reject-final-audit'), request_fingerprint TEXT NOT NULL, request_json TEXT NOT NULL, result_revision INTEGER NOT NULL, target_id TEXT NOT NULL, PRIMARY KEY(actor_scope, operation_id));").outcome, "ok")
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var intent: Dictionary = {"schema_version": 1, "operation_id": "reject-final-audit", "plot_id": "plot-one", "expected_revision": 1, "action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1}
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.apply_permit("owner-one", intent).outcome, "transaction_failed")
	var observation: Dictionary = _store.dml_statement_counters()
	assert_eq(observation.observation_status, "OBSERVED")
	assert_eq(observation.totals.attempted, {"insert": 2, "replace": 0, "update": 1, "delete": 0})
	assert_eq(observation.totals.committed, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	assert_eq(observation.totals.rolled_back, {"insert": 1, "replace": 0, "update": 1, "delete": 0})
	assert_eq(observation.totals.failed, {"insert": 1, "replace": 0, "update": 0, "delete": 0})
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")
	authority = authority_script.new(_store)
	assert_eq(authority.get_claim("plot-one").claim.claim_revision, 1)
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "permission_denied")
	assert_eq(_store.query("SELECT operation_id FROM permission_operation_receipts;").rows, [{"operation_id": "provision-one"}])
	intent.operation_id = "healthy-after-rollback"
	assert_eq(authority.apply_permit("owner-one", intent).outcome, "ok")
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "ok")


func test_faction_access_requires_both_explicit_named_role_and_current_membership() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(authority.update_memberships("crafter-one", [{"kind": "faction_role", "id": "faction-one", "role": "artisan"}], 0, "join-artisans").outcome, "ok")
	assert_eq(authority.update_memberships("guard-one", [{"kind": "faction_role", "id": "faction-one", "role": "guard"}], 0, "join-guards").outcome, "ok")
	assert_eq(authority.begin_interaction("crafter-one", "plot-one", 9).outcome, "permission_denied")
	assert_eq(authority.apply_permit("owner-one", {"schema_version": 1, "operation_id": "grant-artisans", "plot_id": "plot-one", "expected_revision": 1, "action": "grant", "subject": {"kind": "faction_role", "id": "faction-one", "role": "artisan"}, "permission_bits": 9}).outcome, "ok")
	assert_eq(authority.begin_interaction("guard-one", "plot-one", 9).outcome, "permission_denied")
	var started: Dictionary = authority.begin_interaction("crafter-one", "plot-one", 9)
	assert_eq(started.outcome, "ok")
	assert_eq(authority.update_memberships("crafter-one", [{"kind": "faction_role", "id": "faction-one", "role": "guard"}], 1, "change-role").outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.commit_interaction("crafter-one", started.interaction_id, func() -> bool: return true).outcome, "stale_authority")
	assert_eq(authority.begin_interaction("crafter-one", "plot-one", 9).outcome, "permission_denied")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})


func test_explicit_steward_cannot_delegate_or_remove_rights_it_does_not_hold() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var grant: Dictionary = {"schema_version": 1, "operation_id": "grant-steward", "plot_id": "plot-one", "expected_revision": 1, "action": "grant", "subject": {"kind": "character", "id": "steward-one", "role": ""}, "permission_bits": 33}
	assert_eq(authority.apply_permit("owner-one", grant).outcome, "ok")
	grant.operation_id = "grant-builder"
	grant.expected_revision = 2
	grant.subject.id = "builder-one"
	grant.permission_bits = 4
	assert_eq(authority.apply_permit("owner-one", grant).outcome, "ok")
	grant.operation_id = "steal-build"
	grant.expected_revision = 3
	grant.subject.id = "steward-one"
	grant.permission_bits = 37
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.apply_permit("steward-one", grant).outcome, "permission_denied")
	assert_eq(authority.apply_permit("steward-one", {"schema_version": 1, "operation_id": "remove-builder", "plot_id": "plot-one", "expected_revision": 3, "action": "revoke", "subject": {"kind": "character", "id": "builder-one", "role": ""}}).outcome, "permission_denied")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	grant.operation_id = "delegate-entry"
	grant.subject.id = "visitor-one"
	grant.permission_bits = 1
	assert_eq(authority.apply_permit("steward-one", grant).outcome, "ok")
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "ok")
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 4).outcome, "permission_denied")


func test_closed_permission_inputs_reject_unknown_bits_fields_types_and_control_ids() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var valid: Dictionary = {"schema_version": 1, "operation_id": "permit-one", "plot_id": "plot-one", "expected_revision": 1, "action": "grant", "subject": {"kind": "character", "id": "visitor-one", "role": ""}, "permission_bits": 1}
	var cases: Array[Dictionary] = []
	for bits: Variant in [0, -1, 64, 1.0]:
		var bad_bits: Dictionary = valid.duplicate(true)
		bad_bits.permission_bits = bits
		cases.append(bad_bits)
	var unknown: Dictionary = valid.duplicate(true)
	unknown.client_owner = true
	cases.append(unknown)
	var wrong_kind_type: Dictionary = valid.duplicate(true)
	wrong_kind_type.subject.kind = &"character"
	cases.append(wrong_kind_type)
	var control_id: Dictionary = valid.duplicate(true)
	control_id.operation_id = "permit\nforged"
	cases.append(control_id)
	var fraction_revision: Dictionary = valid.duplicate(true)
	fraction_revision.expected_revision = 1.0
	cases.append(fraction_revision)
	var unknown_version: Dictionary = valid.duplicate(true)
	unknown_version.schema_version = 1.0
	cases.append(unknown_version)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	for intent: Dictionary in cases:
		assert_eq(authority.apply_permit("owner-one", intent).outcome, "invalid_request")
	assert_eq(authority.register_claim("plot\nforged", "owner-one", "bad-plot").outcome, "invalid_request")
	assert_eq(authority.update_memberships("member-one", [{"kind": "party", "id": "first", "role": ""}, {"kind": "party", "id": "second", "role": ""}], 0, "two-parties").outcome, "invalid_request")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})


func test_corrupt_claim_and_membership_state_rejects_without_repair_writes() -> void:
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	assert_eq(authority.update_memberships("member-one", [], 0, "member-one").outcome, "ok")
	assert_eq(_store.query("UPDATE plot_claims SET claim_revision = 1073741825;").outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.get_claim("plot-one").outcome, "invalid_persisted_state")
	assert_eq(authority.begin_interaction("owner-one", "plot-one", 1).outcome, "invalid_persisted_state")
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	assert_eq(_store.query("UPDATE plot_claims SET claim_revision = 1;").outcome, "ok")
	assert_eq(_store.query("INSERT INTO permission_memberships (character_id, subject_kind, subject_id, subject_role) VALUES ('member-one', 'party', 'first', '');").outcome, "ok")
	assert_eq(_store.query("INSERT INTO permission_memberships (character_id, subject_kind, subject_id, subject_role) VALUES ('member-one', 'party', 'second', '');").outcome, "ok")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")
	authority = authority_script.new(_store)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(authority.begin_interaction("member-one", "plot-one", 1).outcome, "invalid_persisted_state")
	assert_eq(authority.update_memberships("member-one", [], 1, "do-not-repair").outcome, "invalid_persisted_state")
	assert_eq(_store.query("SELECT subject_id FROM permission_memberships ORDER BY subject_id;").rows, [{"subject_id": "first"}, {"subject_id": "second"}])
	assert_eq(_store.dml_statement_counters().totals.attempted, {"insert": 0, "replace": 0, "update": 0, "delete": 0})
