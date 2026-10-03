extends GutTest

const LedgerScript = preload("res://server/item_ledger_repository.gd")
const StoreScript = preload("res://server/sqlite_store.gd")
const CreationFixture = preload("res://tests/fixtures/item_creation_profile.gd")
const ProfileScript = preload("res://server/item_creation_profile.gd")

var _relative_path: String = ""
var _store: SqliteStore = null


func before_each() -> void:
	_relative_path = "test_item_ledger_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, StoreScript.OUTCOME_OK)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			assert_eq(DirAccess.remove_absolute(path), OK)


func test_sqlite_preserves_integer_types_above_json_precision_across_reopen() -> void:
	assert_eq(_store.query("CREATE TABLE integer_probe (id INTEGER PRIMARY KEY, value INTEGER NOT NULL);").outcome, StoreScript.OUTCOME_OK)
	var values: Array[int] = [0, 9007199254740993, 9223372036854775807]
	for index: int in values.size():
		assert_eq(_store.query_with_bindings("INSERT INTO integer_probe (id, value) VALUES (?, ?);", [index, values[index]]).outcome, StoreScript.OUTCOME_OK)
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, StoreScript.OUTCOME_OK)
	var result: Dictionary = _store.query("SELECT value FROM integer_probe ORDER BY id;")
	assert_eq(result.outcome, StoreScript.OUTCOME_OK)
	assert_eq(result.rows.size(), values.size())
	for index: int in values.size():
		assert_true(result.rows[index].value is int, "INTEGER row preserves its type")
		assert_eq(result.rows[index].value, values[index], "no float rounding or int64 truncation")


func test_definition_registration_preserves_pinned_metadata_and_numeric_types() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	var original: Dictionary = _definition_wire()
	original.maximum_stack = 9007199254740993
	original.base_effect = 10
	var created: Dictionary = ledger.register_definition(original)
	assert_eq(created.outcome, "ok")
	assert_not_null(created.definition)
	if created.definition == null:
		return
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, StoreScript.OUTCOME_OK)
	ledger = LedgerScript.new(_store)
	var loaded: Dictionary = ledger.get_definition("definition:sword", "edition:one")
	assert_eq(loaded.outcome, "ok")
	assert_not_null(loaded.definition)
	if loaded.definition != null:
		var wire: Dictionary = loaded.definition.to_wire_dict()
		assert_eq(wire, original)
		assert_true(wire.maximum_stack is int)
		assert_true(wire.base_effect is int)
	var fractional: Dictionary = _definition_wire()
	fractional.definition_id = "definition:other-sword"
	fractional.base_effect = 10.25
	assert_eq(ledger.register_definition(fractional).outcome, "ok")
	var other: Dictionary = ledger.get_definition(fractional.definition_id, fractional.definition_revision)
	assert_not_null(other.definition)
	if other.definition != null:
		assert_eq(other.definition.to_wire_dict(), fractional)
		assert_true(other.definition.to_wire_dict().base_effect is float)


func test_definition_revision_is_immutable_and_exact_re_registration_is_idempotent() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	var original: Dictionary = _definition_wire()
	assert_eq(ledger.register_definition(original).outcome, "ok")
	assert_eq(ledger.register_definition(original).outcome, "ok")
	var changed: Dictionary = original.duplicate(true)
	changed.maximum_stack = 3
	assert_eq(ledger.register_definition(changed).outcome, "definition_conflict")
	var invalid: Dictionary = original.duplicate(true)
	invalid.unknown = true
	assert_eq(ledger.register_definition(invalid).outcome, "invalid_definition")
	assert_eq(ledger.get_definition(original.definition_id, original.definition_revision).definition.to_wire_dict(), original)


func test_creation_atomically_persists_identity_receipt_and_exclusive_revisions() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var created: Dictionary = ledger.create_instance("character:one", "operation:create", original, 0, 0)
	assert_eq(created.outcome, "ok")
	assert_not_null(created.receipt)
	if created.receipt == null:
		return
	assert_eq(created.receipt.instance_revision, 0)
	assert_eq(created.receipt.owner_revision, 1)
	assert_eq(created.receipt.location_revision, 1)
	var counts: Dictionary = _store.dml_statement_counters()
	assert_eq(counts.observation_status, "OBSERVED")
	assert_eq(counts.totals.committed.insert, 4)
	assert_eq(counts.by_table.canon_item_instances.committed.insert, 1)
	_record_observation("creation")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	var loaded: Dictionary = ledger.get_instance(original.instance_id)
	assert_eq(loaded.outcome, "ok")
	assert_not_null(loaded.instance)
	if loaded.instance != null:
		assert_eq(loaded.instance.to_wire_dict(), original)
	assert_eq(ledger.get_owner_revision(original.owner).revision, 1)
	assert_eq(ledger.get_location_revision(original.owner, original.location).revision, 1)
	var listed: Dictionary = ledger.list_owner(original.owner)
	assert_eq(listed.outcome, "ok")
	assert_eq(listed.instances.size(), 1)


func test_creation_properties_commit_with_instance_and_recover_exactly() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	var profile_wire: Dictionary = CreationFixture.authored()
	var inputs: Dictionary = {
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	}
	var validated_profile: Dictionary = ProfileScript.from_wire_dict(profile_wire)
	assert_eq(validated_profile.outcome, "ok")
	if validated_profile.profile == null:
		return
	var derived: Dictionary = validated_profile.profile.derive(inputs)
	assert_eq(derived.outcome, "ok")
	if derived.outcome != "ok":
		return
	assert_eq(derived.properties.values, {"purity": 81, "quality": 65, "durability": 206})

	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	if not ledger.has_method("create_instance_with_properties"):
		assert_true(false, "public atomic creation-with-properties command is missing")
		return
	var created: Dictionary = ledger.call(
		"create_instance_with_properties", "character:one", "operation:create",
		original, 0, 0, profile_wire, inputs
	)
	assert_eq(created.outcome, "ok")
	assert_not_null(created.get("receipt"))
	if created.outcome != "ok" or created.get("receipt") == null:
		return
	assert_eq(created.receipt.instance_revision, 0)
	assert_eq(created.receipt.owner_revision, 1)
	assert_eq(created.receipt.location_revision, 1)

	var writes: Dictionary = _store.dml_statement_counters()
	assert_eq(writes.observation_status, "OBSERVED")
	assert_eq(writes.by_table.canon_item_instances.committed.insert, 1)

	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	var loaded_instance: Dictionary = ledger.get_instance(original.instance_id)
	assert_eq(loaded_instance.outcome, "ok")
	assert_not_null(loaded_instance.instance)
	if loaded_instance.instance == null:
		return
	assert_eq(loaded_instance.instance.to_wire_dict(), original)
	assert_true(ledger.has_method("get_creation_properties"), "public companion reader is missing")
	if not ledger.has_method("get_creation_properties"):
		return
	var loaded_properties: Dictionary = ledger.call("get_creation_properties", original.instance_id)
	assert_eq(loaded_properties.outcome, "ok")
	assert_eq(loaded_properties.properties, derived.properties)
	assert_true(loaded_properties.properties.inputs.material_purity is int)
	assert_true(loaded_properties.properties.values.durability is int)
	assert_eq(ledger.get_owner_revision(original.owner).revision, 1)
	assert_eq(ledger.get_location_revision(original.owner, original.location).revision, 1)
	var retired: Dictionary = ledger.retire_instance("character:one", "operation:retire", original, 1, 1, "consumed", 50)
	assert_eq(retired.outcome, "ok")
	assert_eq(ledger.get_creation_properties(original.instance_id).properties, derived.properties)


func test_creation_property_replay_conflicts_and_rejections_issue_no_writes() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	var profile_wire: Dictionary = CreationFixture.authored()
	var inputs: Dictionary = {
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	}
	var created: Dictionary = ledger.call("create_instance_with_properties", "character:one", "operation:create", original, 0, 0, profile_wire, inputs)
	assert_eq(created.outcome, "ok")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")

	var replay_wire: Dictionary = original.duplicate(true)
	replay_wire.acquisition.server_tick = 1234
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:create", replay_wire, 0, 0, profile_wire, inputs), created)
	var changed_inputs: Dictionary = inputs.duplicate(true)
	changed_inputs.material_purity = 82
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:create", original, 0, 0, profile_wire, changed_inputs).outcome, "operation_conflict")
	var changed_profile: Dictionary = profile_wire.duplicate(true)
	changed_profile.outputs.durability.offset += 1
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:create", original, 0, 0, changed_profile, inputs).outcome, "profile_conflict")
	var unsupported_profile: Dictionary = profile_wire.duplicate(true)
	unsupported_profile.arithmetic_version = 2
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:unsupported", original, 0, 0, unsupported_profile, inputs).outcome, "invalid_creation_profile")
	var invalid_inputs: Dictionary = inputs.duplicate(true)
	invalid_inputs.material_purity = 81.0
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:invalid-input", original, 0, 0, profile_wire, invalid_inputs).outcome, "invalid_creation_inputs")
	var stale: Dictionary = original.duplicate(true)
	stale.instance_id = "instance:stale"
	stale.acquisition.operation_id = "operation:stale"
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:stale", stale, 0, 0, profile_wire, inputs).outcome, "stale_revision")
	var duplicate: Dictionary = original.duplicate(true)
	duplicate.acquisition.operation_id = "operation:duplicate"
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:duplicate", duplicate, 1, 1, profile_wire, inputs).outcome, "identity_exists")
	var illegal: Dictionary = original.duplicate(true)
	illegal.instance_id = "instance:illegal"
	illegal.acquisition.operation_id = "operation:illegal"
	illegal.owner.id = " "
	assert_eq(ledger.call("create_instance_with_properties", "character:one", "operation:illegal", illegal, 1, 1, profile_wire, inputs).outcome, "invalid_instance")
	_assert_no_writes("creation-properties-rejections-zero")


func test_creation_property_failure_before_companion_rolls_back_instance_profile_and_revisions() -> void:
	_install_creation_properties_constraint()
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	var profile_wire: Dictionary = CreationFixture.authored()
	var inputs: Dictionary = {"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40}
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var failed: Dictionary = ledger.call("create_instance_with_properties", "character:one", "operation:create", original, 0, 0, profile_wire, inputs)
	assert_eq(failed.outcome, "transaction_failed")
	var writes: Dictionary = _store.dml_statement_counters()
	assert_eq(writes.totals.attempted.insert, 5)
	assert_eq(writes.totals.failed.insert, 1)
	assert_eq(writes.totals.rolled_back.insert, 4)
	assert_eq(writes.totals.committed.insert, 0)
	assert_eq(writes.by_table.canon_item_creation_properties.failed.insert, 1)
	_record_observation("creation-properties-companion-rollback")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	assert_eq(ledger.get_instance(original.instance_id).outcome, "not_found")
	assert_eq(ledger.get_creation_properties(original.instance_id).outcome, "not_found")
	assert_eq(ledger.get_owner_revision(original.owner).revision, 0)
	assert_eq(ledger.get_location_revision(original.owner, original.location).revision, 0)
	assert_eq(_store.query("SELECT COUNT(*) AS count FROM canon_item_creation_profiles;").rows[0].count, 0)
	assert_eq(_store.query("SELECT COUNT(*) AS count FROM canon_item_operations;").rows[0].count, 0)


func test_creation_property_failure_at_receipt_rolls_back_companion_and_all_state() -> void:
	_install_receipt_constraint()
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	original.acquisition.operation_id = "operation:fault"
	var profile_wire: Dictionary = CreationFixture.authored()
	var inputs: Dictionary = {"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40}
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var failed: Dictionary = ledger.call("create_instance_with_properties", "character:one", "operation:fault", original, 0, 0, profile_wire, inputs)
	assert_eq(failed.outcome, "transaction_failed")
	var writes: Dictionary = _store.dml_statement_counters()
	assert_eq(writes.totals.attempted.insert, 6)
	assert_eq(writes.totals.failed.insert, 1)
	assert_eq(writes.totals.rolled_back.insert, 5)
	assert_eq(writes.totals.committed.insert, 0)
	assert_eq(writes.by_table.canon_item_creation_properties.rolled_back.insert, 1)
	assert_eq(writes.by_table.canon_item_operations.failed.insert, 1)
	_record_observation("creation-properties-receipt-rollback")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	assert_eq(ledger.get_instance(original.instance_id).outcome, "not_found")
	assert_eq(ledger.get_creation_properties(original.instance_id).outcome, "not_found")
	assert_eq(ledger.get_owner_revision(original.owner).revision, 0)
	assert_eq(ledger.get_location_revision(original.owner, original.location).revision, 0)
	assert_eq(_store.query("SELECT COUNT(*) AS count FROM canon_item_creation_profiles;").rows[0].count, 0)
	assert_eq(_store.query("SELECT COUNT(*) AS count FROM canon_item_operations;").rows[0].count, 0)


func test_retirement_is_atomic_irreversible_and_preserves_original_success_receipts() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	var created: Dictionary = ledger.create_instance("character:one", "operation:create", original, 0, 0)
	assert_eq(created.outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var retired: Dictionary = ledger.retire_instance("character:one", "operation:retire", original, 1, 1, "consumed", 9223372036854775807)
	assert_eq(retired.outcome, "ok")
	assert_not_null(retired.receipt)
	if retired.receipt == null:
		return
	var counters: Dictionary = _store.dml_statement_counters()
	assert_eq(counters.observation_status, "OBSERVED")
	assert_eq(counters.totals.committed.update, 3)
	assert_eq(counters.totals.committed.insert, 1)
	_record_observation("retirement")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	var persisted: Dictionary = ledger.get_instance(original.instance_id)
	assert_eq(persisted.outcome, "ok")
	assert_not_null(persisted.instance)
	if persisted.instance == null:
		return
	var expected: Dictionary = original.duplicate(true)
	expected.owner = null
	expected.location = null
	expected.instance_revision = 1
	expected.terminal = {"reason": "consumed", "operation_id": "operation:retire", "server_tick": 9223372036854775807}
	assert_eq(persisted.instance.to_wire_dict(), expected)
	assert_eq(ledger.list_owner(original.owner).instances.size(), 0)
	assert_eq(ledger.get_owner_revision(original.owner).revision, 2)
	assert_eq(ledger.get_location_revision(original.owner, original.location).revision, 2)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var retry: Dictionary = original.duplicate(true)
	retry.acquisition.server_tick = 12345
	assert_eq(ledger.create_instance("character:one", "operation:create", retry, 0, 0), created)
	assert_eq(ledger.retire_instance("character:one", "operation:retire", retry, 1, 1, "consumed", 10), retired)
	assert_eq(ledger.retire_instance("character:one", "operation:retire-other", original, 2, 2, "destroyed", 10).outcome, "stale_instance")
	retry.acquisition.operation_id = "operation:revive"
	assert_eq(ledger.create_instance("character:one", "operation:revive", retry, 2, 2).outcome, "identity_exists")
	_assert_no_writes("retirement-retry-zero")


func _assert_no_writes(scenario: String) -> void:
	var counts: Dictionary = _store.dml_statement_counters()
	assert_eq(counts.observation_status, "OBSERVED")
	if counts.observation_status != "OBSERVED":
		return
	for window: String in ["attempted", "committed", "rolled_back", "failed"]:
		for operation: String in ["insert", "replace", "update", "delete"]:
			assert_eq(counts.totals[window][operation], 0, "%s/%s" % [window, operation])

	_record_observation(scenario)

func test_malformed_unpinned_carried_and_terminal_creation_reject_without_writes() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	for change: Dictionary in [{"quantity": 0}, {"quantity": 1.0}, {"quantity": 3}, {"schema_version": 2}, {"unknown": true}, {"owner": {"kind": "character", "id": " "}}, {"location": {"kind": "equipped", "slot": "left_hand"}}]:
		var bad: Dictionary = _instance_wire()
		bad.merge(change, true)
		assert_eq(ledger.create_instance("character:one", "operation:create", bad, 0, 0).outcome, "invalid_instance", str(change))
	var unpinned: Dictionary = _instance_wire()
	unpinned.definition_revision = "edition:missing"
	assert_eq(ledger.create_instance("character:one", "operation:create", unpinned, 0, 0).outcome, "unpinned_definition")
	var carried: Dictionary = _instance_wire()
	carried.location = {"kind": "carried", "container_instance_id": "instance:bag", "index": 0}
	assert_eq(ledger.create_instance("character:one", "operation:create", carried, 0, 0).outcome, "capacity_not_configured")
	var terminal: Dictionary = _instance_wire()
	terminal.owner = null
	terminal.location = null
	terminal.terminal = {"reason": "destroyed", "operation_id": "operation:previous", "server_tick": 10}
	assert_eq(ledger.create_instance("character:one", "operation:create", terminal, 0, 0).outcome, "invalid_creation")
	var noninitial: Dictionary = _instance_wire()
	noninitial.instance_revision = 1
	assert_eq(ledger.create_instance("character:one", "operation:create", noninitial, 0, 0).outcome, "invalid_creation")
	assert_eq(ledger.create_instance("character:one", "operation:create", _instance_wire(), 0.0, 0).outcome, "invalid_command")
	assert_eq(ledger.create_instance(" ", "operation:create", _instance_wire(), 0, 0).outcome, "invalid_command")
	_assert_no_writes("malformed-zero")


func test_replay_binds_all_logical_intent_and_rejections_leave_record_unchanged() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	var first: Dictionary = ledger.create_instance("character:one", "operation:create", original, 0, 0)
	assert_eq(first.outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var reordered: Dictionary = {}
	var keys: Array = original.keys()
	keys.reverse()
	for key: String in keys:
		reordered[key] = original[key]
	reordered.acquisition = original.acquisition.duplicate(true)
	reordered.acquisition.server_tick = 500
	assert_eq(ledger.create_instance("character:one", "operation:create", reordered, 0, 0), first)
	for change: Dictionary in [{"quantity": 2}, {"instance_id": "instance:other"}, {"owner": {"kind": "character", "id": "character:other"}}, {"acquisition": {"source_id": "source:other", "operation_id": "operation:create", "server_tick": 1}}]:
		var altered: Dictionary = original.duplicate(true)
		altered.merge(change, true)
		assert_eq(ledger.create_instance("character:one", "operation:create", altered, 0, 0).outcome, "operation_conflict")
	assert_eq(ledger.create_instance("character:one", "operation:create", original, 1, 1).outcome, "operation_conflict")
	assert_eq(ledger.retire_instance("character:one", "operation:create", original, 1, 1, "destroyed", 10).outcome, "operation_conflict")
	var other: Dictionary = original.duplicate(true)
	other.instance_id = "instance:second"
	other.acquisition.operation_id = "operation:second"
	assert_eq(ledger.create_instance("character:one", "operation:second", other, 0, 0).outcome, "stale_revision")
	assert_eq(ledger.create_instance("character:one", "operation:second", other, 1, 1).outcome, "location_occupied")
	assert_eq(ledger.create_instance("character:other", "operation:create", original, 1, 1).outcome, "identity_exists")
	var stale: Dictionary = original.duplicate(true)
	stale.quantity = 2
	assert_eq(ledger.retire_instance("character:one", "operation:retire", stale, 1, 1, "consumed", 10).outcome, "stale_instance")
	assert_eq(ledger.get_instance(original.instance_id).instance.to_wire_dict(), original)
	_assert_no_writes("replay-zero")


func test_actor_scoped_keys_and_exact_loot_position_indices_survive_reopen() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	assert_eq(ledger.create_instance("character:one", "operation:create", _instance_wire(), 0, 0).outcome, "ok")
	var loot: Dictionary = _instance_wire()
	loot.instance_id = "instance:loot"
	loot.owner = {"kind": "world_container", "id": "source:chest"}
	loot.location = {"kind": "loot_position", "source_id": "source:chest", "index": 9007199254740993}
	var created: Dictionary = ledger.create_instance("character:other", "operation:create", loot, 0, 0)
	assert_eq(created.outcome, "ok", "same operation key has independent authenticated actor scope")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	var loaded: Dictionary = ledger.get_instance(loot.instance_id)
	assert_eq(loaded.instance.to_wire_dict(), loot)
	assert_true(loaded.instance.to_wire_dict().location.index is int)
	assert_eq(ledger.list_owner(loot.owner).instances.size(), 1)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.create_instance("character:other", "operation:create", loot, 0, 0), created)
	_assert_no_writes("loot-retry-zero")


func test_real_receipt_failure_rolls_back_creation_and_all_revisions() -> void:
	_install_receipt_constraint()
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var failed: Dictionary = _instance_wire()
	failed.acquisition.operation_id = "operation:fault"
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.create_instance("character:one", "operation:fault", failed, 0, 0).outcome, "transaction_failed")
	var counts: Dictionary = _store.dml_statement_counters()
	assert_eq(counts.observation_status, "OBSERVED")
	assert_eq(counts.totals.attempted.insert, 4)
	assert_eq(counts.totals.failed.insert, 1)
	assert_eq(counts.totals.rolled_back.insert, 3)
	assert_eq(counts.totals.committed.insert, 0)
	assert_eq(counts.by_table.canon_item_operations.failed.insert, 1)
	_record_observation("create-rollback")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	assert_eq(ledger.get_instance(failed.instance_id).outcome, "not_found")
	assert_eq(ledger.get_owner_revision(failed.owner).revision, 0)
	assert_eq(ledger.get_location_revision(failed.owner, failed.location).revision, 0)
	assert_eq(_store.query("SELECT operation_id FROM canon_item_operations;").rows.size(), 0)
	assert_eq(ledger.create_instance("character:one", "operation:create", _instance_wire(), 0, 0).outcome, "ok", "healthy later command succeeds after rollback")


func test_real_receipt_failure_preserves_active_identity_during_retirement() -> void:
	_install_receipt_constraint()
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	assert_eq(ledger.create_instance("character:one", "operation:create", original, 0, 0).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.retire_instance("character:one", "operation:fault", original, 1, 1, "destroyed", 200).outcome, "transaction_failed")
	var counts: Dictionary = _store.dml_statement_counters()
	assert_eq(counts.observation_status, "OBSERVED")
	assert_eq(counts.totals.attempted.update, 3)
	assert_eq(counts.totals.rolled_back.update, 3)
	assert_eq(counts.totals.failed.insert, 1)
	assert_eq(counts.totals.committed.update, 0)
	_record_observation("retire-rollback")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	assert_eq(ledger.get_instance(original.instance_id).instance.to_wire_dict(), original)
	assert_eq(ledger.get_owner_revision(original.owner).revision, 1)
	assert_eq(ledger.get_location_revision(original.owner, original.location).revision, 1)
	assert_eq(_store.query("SELECT operation_id FROM canon_item_operations;").rows.size(), 1)
	assert_eq(ledger.retire_instance("character:one", "operation:retire", original, 1, 1, "destroyed", 200).outcome, "ok")


func _install_receipt_constraint() -> void:
	# Owned real SQLite CHECK fails only the final receipt INSERT; no trigger or hidden writer.
	assert_eq(_store.query("""CREATE TABLE canon_item_operations (
		actor_character_id TEXT NOT NULL, operation_id TEXT NOT NULL CHECK (operation_id <> 'operation:fault'),
		operation_kind TEXT NOT NULL, fingerprint TEXT NOT NULL, instance_id TEXT NOT NULL,
		instance_revision INTEGER NOT NULL, owner_revision INTEGER NOT NULL, location_revision INTEGER NOT NULL,
		PRIMARY KEY (actor_character_id, operation_id)
	);""").outcome, "ok")


func _install_creation_properties_constraint() -> void:
	assert_eq(_store.query("""CREATE TABLE canon_item_creation_properties (
		instance_id TEXT PRIMARY KEY NOT NULL CHECK (instance_id <> 'instance:sword'),
		schema_version INTEGER NOT NULL, profile_id TEXT NOT NULL, profile_revision TEXT NOT NULL,
		profile_sha256 TEXT NOT NULL, blueprint_id TEXT NOT NULL, blueprint_revision TEXT NOT NULL,
		tuning_version TEXT NOT NULL, arithmetic_version INTEGER NOT NULL,
		material_purity INTEGER NOT NULL, catalyst_quality INTEGER NOT NULL, workstation_parameter INTEGER NOT NULL,
		purity INTEGER NOT NULL, quality INTEGER NOT NULL, durability INTEGER NOT NULL,
		purity_unit TEXT NOT NULL, quality_unit TEXT NOT NULL, durability_unit TEXT NOT NULL,
		FOREIGN KEY (instance_id) REFERENCES canon_item_instances(instance_id),
		FOREIGN KEY (profile_id, profile_revision) REFERENCES canon_item_creation_profiles(profile_id, profile_revision)
	);""").outcome, "ok")


func test_definition_revision_rejects_effect_numeric_type_changes_without_writes() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	var original: Dictionary = _definition_wire()
	original.base_effect = 10
	assert_eq(ledger.register_definition(original).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var altered: Dictionary = original.duplicate(true)
	altered.base_effect = 10.0
	assert_eq(ledger.register_definition(altered).outcome, "definition_conflict")
	assert_true(ledger.get_definition(original.definition_id, original.definition_revision).definition.to_wire_dict().base_effect is int)
	_assert_no_writes("definition-type-zero")


func test_read_failures_are_explicit_errors_instead_of_revision_zero() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	assert_eq(_store.query("DROP TABLE canon_item_owners;").outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	var state: Dictionary = ledger.get_owner_revision(_instance_wire().owner)
	assert_eq(state.outcome, "query_failed")
	assert_eq(state.revision, -1)
	assert_eq(ledger.create_instance("character:one", "operation:create", _instance_wire(), 0, 0).outcome, "query_failed")
	_assert_no_writes("read-failure-zero")


func test_fractional_authoritative_storage_is_preserved_and_rejected_after_reopen() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	assert_eq(ledger.create_instance("character:one", "operation:create", original, 0, 0).outcome, "ok")
	# Owned corruption fixture only: disable CHECK while introducing a fractional quantity.
	assert_eq(_store.query("PRAGMA ignore_check_constraints = ON;").outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_instances SET quantity = ? WHERE instance_id = ?;", [1.5, original.instance_id]).outcome, "ok")
	assert_eq(_store.query("PRAGMA ignore_check_constraints = OFF;").outcome, "ok")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, "ok")
	ledger = LedgerScript.new(_store)
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.get_instance(original.instance_id).outcome, "corrupt_record")
	assert_eq(ledger.list_owner(original.owner).outcome, "corrupt_record")
	assert_eq(ledger.retire_instance("character:one", "operation:retire", original, 1, 1, "destroyed", 100).outcome, "corrupt_record")
	_assert_no_writes("corrupt-quantity-zero")
	var stored: Dictionary = _store.query_with_bindings("SELECT quantity FROM canon_item_instances WHERE instance_id = ?;", [original.instance_id])
	assert_eq(stored.rows[0].quantity, 1.5, "recovery never repairs or truncates authoritative values")


func test_revisions_above_json_precision_advance_exactly_and_overflow_rejects() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	assert_eq(ledger.create_instance("character:one", "operation:create", original, 0, 0).outcome, "ok")
	var high: int = 9007199254740993
	assert_eq(_store.query_with_bindings("UPDATE canon_item_owners SET revision = ?;", [high]).outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_locations SET revision = ?;", [high]).outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_instances SET instance_revision = ?;", [high]).outcome, "ok")
	var expected: Dictionary = ledger.get_instance(original.instance_id).instance.to_wire_dict()
	assert_eq(expected.instance_revision, high)
	var retired: Dictionary = ledger.retire_instance("character:one", "operation:retire", expected, high, high, "merged", 100)
	assert_eq(retired.outcome, "ok")
	assert_eq(retired.receipt.instance_revision, high + 1)
	assert_eq(retired.receipt.owner_revision, high + 1)
	assert_eq(retired.receipt.location_revision, high + 1)
	assert_true(retired.receipt.instance_revision is int)
	var next: Dictionary = original.duplicate(true)
	next.instance_id = "instance:next"
	next.acquisition.operation_id = "operation:next"
	assert_eq(ledger.create_instance("character:one", "operation:next", next, high + 1, high + 1).outcome, "ok", "new GUID can reuse a retired address")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_owners SET revision = ?;", [9223372036854775807]).outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_locations SET revision = ?;", [9223372036854775807]).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.retire_instance("character:one", "operation:overflow", next, 9223372036854775807, 9223372036854775807, "destroyed", 100).outcome, "revision_overflow")
	_assert_no_writes("revision-overflow-1")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_owners SET revision = ?;", [high + 2]).outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_locations SET revision = ?;", [high + 2]).outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_instances SET instance_revision = ? WHERE instance_id = ?;", [9223372036854775807, next.instance_id]).outcome, "ok")
	next.instance_revision = 9223372036854775807
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.retire_instance("character:one", "operation:overflow-instance", next, high + 2, high + 2, "destroyed", 100).outcome, "revision_overflow")
	_assert_no_writes("revision-overflow-2")


func test_inconsistent_live_storage_discriminants_fail_closed_without_repairs() -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	assert_eq(ledger.create_instance("character:one", "operation:create", original, 0, 0).outcome, "ok")
	assert_eq(_store.query_with_bindings("UPDATE canon_item_instances SET terminal_tick = ? WHERE instance_id = ?;", [100, original.instance_id]).outcome, "ok")
	assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
	assert_eq(ledger.get_instance(original.instance_id).outcome, "corrupt_record")
	assert_eq(ledger.list_owner(original.owner).outcome, "corrupt_record")
	_assert_no_writes("corrupt-discriminant-zero")


func _record_observation(scenario: String) -> void:
	# Only approved task metadata is retained; never SQL, bindings or DB contents.
	var directory: String = OS.get_environment("PROJECT0_LEDGER_EVIDENCE_DIR")
	if directory.is_empty():
		return
	var prefix: String = ProjectSettings.globalize_path("res://build/validation/1341-ledger/")
	assert_true(directory.begins_with(prefix) and not directory.split("/").has(".."), "owned evidence destination")
	if not directory.begins_with(prefix) or directory.split("/").has(".."):
		return
	var file: FileAccess = FileAccess.open(directory.path_join(scenario + ".json"), FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify({"schema_version": 1, "issue": 1341, "scenario": scenario, "observation": _store.dml_statement_counters()}, "\t") + "\n")
		file.close()


func test_create_retry_rejects_corrupted_typed_receipt_results_after_reopen() -> void:
	_assert_receipt_integrity("create")


func test_retire_retry_rejects_corrupted_typed_receipt_results_after_reopen() -> void:
	_assert_receipt_integrity("retire")


func _assert_receipt_integrity(kind: String) -> void:
	var ledger: ItemLedgerRepository = LedgerScript.new(_store)
	assert_eq(ledger.ensure_schema().outcome, "ok")
	assert_eq(ledger.register_definition(_definition_wire()).outcome, "ok")
	var original: Dictionary = _instance_wire()
	var created: Dictionary = ledger.create_instance("character:one", "operation:create", original, 0, 0)
	assert_eq(created.outcome, "ok")
	var committed: Dictionary = created
	if kind == "retire":
		committed = ledger.retire_instance("character:one", "operation:retire", original, 1, 1, "destroyed", 100)
		assert_eq(committed.outcome, "ok")
	var retained: Dictionary = ledger.get_instance(original.instance_id).instance.to_wire_dict()
	for change: Dictionary in [{"operation_kind": "retire" if kind == "create" else "create"}, {"instance_id": "instance:forged"}, {"instance_revision": 7}, {"owner_revision": 7}, {"location_revision": 7}]:
		var altered: Dictionary = committed.receipt.duplicate(true)
		altered.merge(change, true)
		# Owned fault changes valid typed result fields without changing request fingerprint.
		assert_eq(_store.query_with_bindings("UPDATE canon_item_operations SET operation_kind = ?, instance_id = ?, instance_revision = ?, owner_revision = ?, location_revision = ? WHERE actor_character_id = ? AND operation_id = ?;", [altered.operation_kind, altered.instance_id, altered.instance_revision, altered.owner_revision, altered.location_revision, altered.actor_character_id, altered.operation_id]).outcome, "ok")
		_store.close()
		_store = StoreScript.new()
		assert_eq(_store.open(_relative_path).outcome, "ok")
		ledger = LedgerScript.new(_store)
		assert_eq(_store.start_dml_observation().observation_status, "OBSERVED")
		var retried: Dictionary = ledger.create_instance("character:one", "operation:create", original, 0, 0) if kind == "create" else ledger.retire_instance("character:one", "operation:retire", original, 1, 1, "destroyed", 200)
		assert_eq(retried.outcome, "corrupt_record", str(change))
		assert_null(retried.receipt)
		assert_eq(ledger.get_instance(original.instance_id).instance.to_wire_dict(), retained)
		_assert_no_writes(kind + "-receipt-" + change.keys()[0] + "-zero")
		var row: Dictionary = _store.query_with_bindings("SELECT operation_kind, instance_id, instance_revision, owner_revision, location_revision FROM canon_item_operations WHERE actor_character_id = ? AND operation_id = ?;", [altered.actor_character_id, altered.operation_id]).rows[0]
		for field: String in row:
			assert_eq(row[field], altered[field], "corruption is preserved, never automatically repaired")


func _instance_wire() -> Dictionary:
	return {
		"schema_version": 1, "instance_id": "instance:sword", "definition_id": "definition:sword",
		"definition_revision": "edition:one", "quantity": 1,
		"owner": {"kind": "character", "id": "character:one"},
		"location": {"kind": "equipped", "slot": "right_hand"}, "bound_character_id": "",
		"acquisition": {"source_id": "source:smith", "operation_id": "operation:create", "server_tick": 9007199254740993},
		"instance_revision": 0, "terminal": null,
	}


func _definition_wire() -> Dictionary:
	return {
		"schema_version": 1, "definition_id": "definition:sword", "definition_revision": "edition:one",
		"item_class": "sword", "slot": "right_hand", "category": "mundane", "maximum_stack": 2,
		"binding_policy": "none", "base_effect": 10.0,
	}
