extends RefCounted
class_name ItemLedgerRepository
## #1341 / ADR 0015: closed item ledger over the server-owned world Canon store.
## Requires validated server commands; never authenticates an actor or proves
## recipient/permission/acquisition facts. No production startup wiring here.

const DefinitionScript = preload("res://shared/item_definition.gd")
const InstanceScript = preload("res://shared/item_instance.gd")
const MetadataScript = preload("res://shared/item_contract.gd")

var _store: SqliteStore


func _init(store: SqliteStore) -> void:
	_store = store


func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return _result("not_open", "store is not open")
	var definitions: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS canon_item_definitions (
			definition_id TEXT NOT NULL,
			definition_revision TEXT NOT NULL,
			schema_version INTEGER NOT NULL,
			item_class TEXT NOT NULL,
			slot TEXT NOT NULL,
			category TEXT NOT NULL,
			maximum_stack INTEGER NOT NULL CHECK (typeof(maximum_stack) = 'integer' AND maximum_stack > 0),
			binding_policy TEXT NOT NULL,
			base_effect REAL NOT NULL,
			base_effect_integer INTEGER NOT NULL CHECK (base_effect_integer IN (0, 1)),
			PRIMARY KEY (definition_id, definition_revision)
		);
	""")

	if definitions.outcome != "ok":
		return definitions
	var statements: Array[String] = [
		"""CREATE TABLE IF NOT EXISTS canon_item_instances (
			instance_id TEXT PRIMARY KEY NOT NULL, schema_version INTEGER NOT NULL,
			definition_id TEXT NOT NULL, definition_revision TEXT NOT NULL,
			quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
			owner_kind TEXT, owner_id TEXT, location_kind TEXT, slot TEXT, source_id TEXT, location_index INTEGER,
			bound_character_id TEXT NOT NULL, acquisition_source_id TEXT NOT NULL,
			acquisition_operation_id TEXT NOT NULL, acquisition_tick INTEGER NOT NULL CHECK (typeof(acquisition_tick) = 'integer' AND acquisition_tick >= 0),
			instance_revision INTEGER NOT NULL CHECK (typeof(instance_revision) = 'integer' AND instance_revision >= 0),
			terminal_reason TEXT, terminal_tick INTEGER, terminal_operation_id TEXT,
			FOREIGN KEY (definition_id, definition_revision) REFERENCES canon_item_definitions(definition_id, definition_revision),
			CHECK ((terminal_reason IS NULL AND owner_kind IS NOT NULL AND owner_id IS NOT NULL AND location_kind IS NOT NULL)
			OR (terminal_reason IS NOT NULL AND owner_kind IS NULL AND owner_id IS NULL AND location_kind IS NULL AND slot IS NULL AND source_id IS NULL AND location_index IS NULL))
		);""",
		"CREATE UNIQUE INDEX IF NOT EXISTS canon_item_equipped_address ON canon_item_instances (owner_kind, owner_id, slot) WHERE terminal_reason IS NULL AND location_kind = 'equipped';",
		"CREATE UNIQUE INDEX IF NOT EXISTS canon_item_loot_address ON canon_item_instances (owner_kind, owner_id, source_id, location_index) WHERE terminal_reason IS NULL AND location_kind = 'loot_position';",
		"""CREATE TABLE IF NOT EXISTS canon_item_owners (
			owner_kind TEXT NOT NULL, owner_id TEXT NOT NULL,
			revision INTEGER NOT NULL CHECK (typeof(revision) = 'integer' AND revision >= 0),
			PRIMARY KEY (owner_kind, owner_id)
		);""",
		"""CREATE TABLE IF NOT EXISTS canon_item_locations (
			owner_kind TEXT NOT NULL, owner_id TEXT NOT NULL, location_kind TEXT NOT NULL,
			slot TEXT NOT NULL, source_id TEXT NOT NULL, location_index INTEGER NOT NULL,
			revision INTEGER NOT NULL CHECK (typeof(revision) = 'integer' AND revision >= 0),
			PRIMARY KEY (owner_kind, owner_id, location_kind, slot, source_id, location_index)
		);""",
		"""CREATE TABLE IF NOT EXISTS canon_item_operations (
			actor_character_id TEXT NOT NULL, operation_id TEXT NOT NULL, operation_kind TEXT NOT NULL,
			fingerprint TEXT NOT NULL, instance_id TEXT NOT NULL, instance_revision INTEGER NOT NULL,
			owner_revision INTEGER NOT NULL, location_revision INTEGER NOT NULL,
			PRIMARY KEY (actor_character_id, operation_id)
		);""",
	]
	for statement: String in statements:
		var result: Dictionary = _store.query(statement)
		if result.outcome != "ok":
			return result
	return _result("ok", "")


func register_definition(wire: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _definition_result("not_open", "store is not open")
	var validation: Dictionary = DefinitionScript.from_wire_dict(wire)
	if validation.definition == null:
		return _definition_result("invalid_definition", validation.detail)
	var data: Dictionary = validation.definition.to_wire_dict()
	var work: Dictionary = _definition_result("transaction_failed", "transaction did not complete")
	var transaction: Dictionary = _store.transaction(func() -> bool:
		var existing: Dictionary = get_definition(data.definition_id, data.definition_revision)
		if existing.outcome == "ok":
			work.merge(existing if existing.definition.to_wire_dict() == data else _definition_result("definition_conflict", "definition revision already exists"), true)
			return work.outcome == "ok"
		if existing.outcome != "not_found":
			work.merge(existing, true)
			return false
		var inserted: Dictionary = _store.query_with_bindings(
			"INSERT INTO canon_item_definitions (definition_id, definition_revision, schema_version, item_class, slot, category, maximum_stack, binding_policy, base_effect, base_effect_integer) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			[data.definition_id, data.definition_revision, data.schema_version, data.item_class, data.slot,
			 data.category, data.maximum_stack, data.binding_policy, data.base_effect, 1 if data.base_effect is int else 0]
		)
		if inserted.outcome != "ok":
			return false
		work.merge(_definition_result("ok", "", validation.definition), true)
		return true
	)
	if transaction.outcome != "ok" and work.outcome == "ok":
		return _definition_result("transaction_failed", transaction.detail)
	return work


func get_definition(definition_id: String, definition_revision: String) -> Dictionary:
	if _store == null or not _store.is_open():
		return _definition_result("not_open", "store is not open")
	var selected: Dictionary = _store.query_with_bindings(
		"SELECT definition_id, definition_revision, schema_version, item_class, slot, category, maximum_stack, binding_policy, base_effect, base_effect_integer FROM canon_item_definitions WHERE definition_id = ? AND definition_revision = ?;",
		[definition_id, definition_revision]
	)
	if selected.outcome != "ok":
		return _definition_result("query_failed", selected.detail)
	if selected.rows.is_empty():
		return _definition_result("not_found", "definition revision not found")
	return _definition_from_row(selected.rows[0])


## Owns one transaction. Do not nest this wrapper inside another operation.
func create_instance(actor: String, operation_id: String, wire: Variant, owner_revision: Variant, location_revision: Variant) -> Dictionary:
	if not _open():
		return _command_result("not_open", "store is not open")
	if not _identifier(actor) or not _identifier(operation_id) or not _revision(owner_revision) or not _revision(location_revision):
		return _command_result("invalid_command", "actor, operation and expected revisions are required")
	var work: Dictionary = _command_result("transaction_failed", "transaction did not complete")
	var transaction: Dictionary = _store.transaction(func() -> bool:
		var validated: Dictionary = _validate_snapshot(wire)
		if validated.outcome != "ok":
			work.merge(_command_result(validated.outcome, validated.detail), true)
			return false
		var data: Dictionary = validated.instance.to_wire_dict()
		if data.terminal != null or data.instance_revision != 0 or data.acquisition.operation_id != operation_id:
			work.merge(_command_result("invalid_creation", "creation requires active revision zero and matching acquisition operation"), true)
			return false
		if data.location.kind == "carried":
			work.merge(_command_result("capacity_not_configured", "carried capacity requires an authored profile"), true)
			return false
		var fingerprint: String = _fingerprint("create", actor, operation_id, data, validated.definition, owner_revision, location_revision, "")
		var replay: Dictionary = _find_receipt(actor, operation_id, fingerprint)
		if replay.outcome != "not_found":
			work.merge(replay, true)
			return replay.outcome == "ok"
		var identity: Dictionary = get_instance(data.instance_id)
		if identity.outcome != "not_found":
			work.merge(_command_result("identity_exists", "GUID is already recorded") if identity.outcome == "ok" else _command_result(identity.outcome, identity.detail), true)
			return false
		var expectations: Dictionary = _check_revisions(data.owner, data.location, owner_revision, location_revision)
		if expectations.outcome != "ok":
			work.merge(expectations, true)
			return false
		var address: Dictionary = _occupied(data.owner, data.location)
		if address.outcome != "ok":
			work.merge(_command_result(address.outcome, address.detail), true)
			return false
		if address.occupied:
			work.merge(_command_result("location_occupied", "active item already occupies this address"), true)
			return false
		if not _insert_instance(data) or not _advance_revisions(data.owner, data.location, owner_revision, location_revision):
			return false
		var receipt: Dictionary = _new_receipt("create", actor, operation_id, data.instance_id, 0, owner_revision + 1, location_revision + 1)
		if not _insert_receipt(receipt, fingerprint):
			return false
		work.merge(_command_result("ok", "", receipt), true)
		return true
	)
	if transaction.outcome != "ok" and work.outcome == "ok":
		return _command_result("transaction_failed", transaction.detail)
	return work


## Expected active snapshot is caller intent, revalidated before any DML.
func retire_instance(actor: String, operation_id: String, wire: Variant, owner_revision: Variant, location_revision: Variant, reason: String, server_tick: Variant) -> Dictionary:
	if not _open():
		return _command_result("not_open", "store is not open")
	if not _identifier(actor) or not _identifier(operation_id) or not _revision(owner_revision) or not _revision(location_revision) or not _revision(server_tick) or reason not in InstanceScript.TERMINAL_REASONS:
		return _command_result("invalid_command", "actor, operation, revisions and terminal metadata are required")
	var work: Dictionary = _command_result("transaction_failed", "transaction did not complete")
	var transaction: Dictionary = _store.transaction(func() -> bool:
		var validated: Dictionary = _validate_snapshot(wire)
		if validated.outcome != "ok":
			work.merge(_command_result(validated.outcome, validated.detail), true)
			return false
		var data: Dictionary = validated.instance.to_wire_dict()
		if data.terminal != null:
			work.merge(_command_result("invalid_retirement", "expected snapshot must be active"), true)
			return false
		if data.location.kind == "carried":
			work.merge(_command_result("capacity_not_configured", "carried capacity requires an authored profile"), true)
			return false
		var fingerprint: String = _fingerprint("retire", actor, operation_id, data, validated.definition, owner_revision, location_revision, reason)
		var replay: Dictionary = _find_receipt(actor, operation_id, fingerprint)
		if replay.outcome != "not_found":
			work.merge(replay, true)
			return replay.outcome == "ok"
		var current: Dictionary = get_instance(data.instance_id)
		if current.outcome != "ok":
			work.merge(_command_result(current.outcome, current.detail), true)
			return false
		if var_to_bytes(_canonical(current.instance.to_wire_dict())) != var_to_bytes(_canonical(data)):
			work.merge(_command_result("stale_instance", "expected active snapshot changed"), true)
			return false
		var expectations: Dictionary = _check_revisions(data.owner, data.location, owner_revision, location_revision)
		if expectations.outcome != "ok":
			work.merge(expectations, true)
			return false
		if data.instance_revision == 9223372036854775807:
			work.merge(_command_result("revision_overflow", "instance revision cannot advance"), true)
			return false
		if not _retire_record(data, reason, operation_id, server_tick) or not _advance_revisions(data.owner, data.location, owner_revision, location_revision):
			return false
		var receipt: Dictionary = _new_receipt("retire", actor, operation_id, data.instance_id, data.instance_revision + 1, owner_revision + 1, location_revision + 1)
		if not _insert_receipt(receipt, fingerprint):
			return false
		work.merge(_command_result("ok", "", receipt), true)
		return true
	)
	if transaction.outcome != "ok" and work.outcome == "ok":
		return _command_result("transaction_failed", transaction.detail)
	return work


func _retire_record(data: Dictionary, reason: String, operation_id: String, server_tick: int) -> bool:
	return _store.query_with_bindings("UPDATE canon_item_instances SET owner_kind = NULL, owner_id = NULL, location_kind = NULL, slot = NULL, source_id = NULL, location_index = NULL, instance_revision = ?, terminal_reason = ?, terminal_tick = ?, terminal_operation_id = ? WHERE instance_id = ? AND instance_revision = ?;", [data.instance_revision + 1, reason, server_tick, operation_id, data.instance_id, data.instance_revision]).outcome == "ok"


func get_instance(instance_id: String) -> Dictionary:
	if not _open():
		return _instance_result("not_open", "store is not open")
	var selected: Dictionary = _store.query_with_bindings("SELECT * FROM canon_item_instances WHERE instance_id = ?;", [instance_id])
	if selected.outcome != "ok":
		return _instance_result("query_failed", selected.detail)
	if selected.rows.is_empty():
		return _instance_result("not_found", "instance not found")
	return _instance_from_row(selected.rows[0])


func list_owner(owner: Variant) -> Dictionary:
	if not _open():
		return {"outcome": "not_open", "detail": "store is not open", "instances": []}
	if not _owner(owner):
		return {"outcome": "invalid_owner", "detail": "closed owner is required", "instances": []}
	var selected: Dictionary = _store.query_with_bindings("SELECT * FROM canon_item_instances WHERE owner_kind = ? AND owner_id = ? AND terminal_reason IS NULL ORDER BY instance_id;", [owner.kind, owner.id])
	if selected.outcome != "ok":
		return {"outcome": "query_failed", "detail": selected.detail, "instances": []}
	var instances: Array[ItemInstance] = []
	for row: Dictionary in selected.rows:
		var loaded: Dictionary = _instance_from_row(row)
		if loaded.outcome != "ok":
			return {"outcome": loaded.outcome, "detail": loaded.detail, "instances": []}
		instances.append(loaded.instance)
	return {"outcome": "ok", "detail": "", "instances": instances}


func get_owner_revision(owner: Variant) -> Dictionary:
	if not _open():
		return _revision_result("not_open", "store is not open")
	if not _owner(owner):
		return _revision_result("invalid_owner", "closed owner is required")
	return _read_revision("SELECT revision FROM canon_item_owners WHERE owner_kind = ? AND owner_id = ?;", [owner.kind, owner.id])


func get_location_revision(owner: Variant, location: Variant) -> Dictionary:
	if not _open():
		return _revision_result("not_open", "store is not open")
	if not _address(owner, location):
		return _revision_result("invalid_location", "supported closed address is required")
	return _read_revision("SELECT revision FROM canon_item_locations WHERE owner_kind = ? AND owner_id = ? AND location_kind = ? AND slot = ? AND source_id = ? AND location_index = ?;", _address_bindings(owner, location))


func _validate_snapshot(wire: Variant) -> Dictionary:
	if not (wire is Dictionary) or not (wire.get("definition_id") is String) or not (wire.get("definition_revision") is String):
		return {"outcome": "invalid_instance", "detail": "pinned instance fields are required", "instance": null}
	var definition: Dictionary = get_definition(wire.definition_id, wire.definition_revision)
	if definition.outcome != "ok":
		return {"outcome": "unpinned_definition" if definition.outcome == "not_found" else definition.outcome, "detail": definition.detail, "instance": null}
	var validated: Dictionary = InstanceScript.from_wire_dict(wire, definition.definition)
	if validated.instance == null:
		return {"outcome": "invalid_instance", "detail": validated.detail, "instance": null}
	validated["definition"] = definition.definition
	return validated


func _instance_from_row(row: Dictionary) -> Dictionary:
	var owner: Variant = null
	var location: Variant = null
	var terminal: Variant = null
	if row.terminal_reason == null:
		owner = {"kind": row.owner_kind, "id": row.owner_id}
		if row.location_kind == "equipped":
			location = {"kind": row.location_kind, "slot": row.slot}
		elif row.location_kind == "loot_position":
			location = {"kind": row.location_kind, "source_id": row.source_id, "index": row.location_index}
		else:
			return _instance_result("corrupt_record", "unsupported persisted address")
	else:
		if row.owner_kind != null or row.owner_id != null or row.location_kind != null or row.slot != null or row.source_id != null or row.location_index != null:
			return _instance_result("corrupt_record", "terminal record retains live address")
		terminal = {"reason": row.terminal_reason, "server_tick": row.terminal_tick, "operation_id": row.terminal_operation_id}
	var wire: Dictionary = {
		"schema_version": row.schema_version, "instance_id": row.instance_id, "definition_id": row.definition_id,
		"definition_revision": row.definition_revision, "quantity": row.quantity, "owner": owner, "location": location,
		"bound_character_id": row.bound_character_id,
		"acquisition": {"source_id": row.acquisition_source_id, "operation_id": row.acquisition_operation_id, "server_tick": row.acquisition_tick},
		"instance_revision": row.instance_revision, "terminal": terminal,
	}
	var validated: Dictionary = _validate_snapshot(wire)
	if validated.outcome != "ok":
		return _instance_result("corrupt_record" if validated.outcome in ["invalid_instance", "unpinned_definition"] else validated.outcome, validated.detail)
	return _instance_result("ok", "", validated.instance)


func _insert_instance(data: Dictionary) -> bool:
	var equipped: bool = data.location.kind == "equipped"
	return _store.query_with_bindings("INSERT INTO canon_item_instances (instance_id, schema_version, definition_id, definition_revision, quantity, owner_kind, owner_id, location_kind, slot, source_id, location_index, bound_character_id, acquisition_source_id, acquisition_operation_id, acquisition_tick, instance_revision) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", [data.instance_id, data.schema_version, data.definition_id, data.definition_revision, data.quantity, data.owner.kind, data.owner.id, data.location.kind, data.location.slot if equipped else null, null if equipped else data.location.source_id, null if equipped else data.location.index, data.bound_character_id, data.acquisition.source_id, data.acquisition.operation_id, data.acquisition.server_tick, data.instance_revision]).outcome == "ok"


func _check_revisions(owner: Dictionary, location: Dictionary, expected_owner: int, expected_location: int) -> Dictionary:
	var owner_state: Dictionary = get_owner_revision(owner)
	var location_state: Dictionary = get_location_revision(owner, location)
	if owner_state.outcome != "ok":
		return _command_result(owner_state.outcome, owner_state.detail)
	if location_state.outcome != "ok":
		return _command_result(location_state.outcome, location_state.detail)
	if owner_state.revision != expected_owner or location_state.revision != expected_location:
		return _command_result("stale_revision", "owner or location revision changed")
	if expected_owner == 9223372036854775807 or expected_location == 9223372036854775807:
		return _command_result("revision_overflow", "revision cannot advance")
	return _command_result("ok", "")


func _advance_revisions(owner: Dictionary, location: Dictionary, expected_owner: int, expected_location: int) -> bool:
	var owner_sql: String = "INSERT INTO canon_item_owners (owner_kind, owner_id, revision) VALUES (?, ?, ?);" if expected_owner == 0 else "UPDATE canon_item_owners SET revision = ? WHERE owner_kind = ? AND owner_id = ?;"
	var owner_bindings: Array = [owner.kind, owner.id, expected_owner + 1] if expected_owner == 0 else [expected_owner + 1, owner.kind, owner.id]
	if _store.query_with_bindings(owner_sql, owner_bindings).outcome != "ok":
		return false
	var address: Array = _address_bindings(owner, location)
	var location_sql: String = "INSERT INTO canon_item_locations (owner_kind, owner_id, location_kind, slot, source_id, location_index, revision) VALUES (?, ?, ?, ?, ?, ?, ?);" if expected_location == 0 else "UPDATE canon_item_locations SET revision = ? WHERE owner_kind = ? AND owner_id = ? AND location_kind = ? AND slot = ? AND source_id = ? AND location_index = ?;"
	var location_bindings: Array = address + [expected_location + 1] if expected_location == 0 else [expected_location + 1] + address
	return _store.query_with_bindings(location_sql, location_bindings).outcome == "ok"


func _occupied(owner: Dictionary, location: Dictionary) -> Dictionary:
	var sql: String = "SELECT instance_id FROM canon_item_instances WHERE owner_kind = ? AND owner_id = ? AND location_kind = ? AND slot = ? AND terminal_reason IS NULL;" if location.kind == "equipped" else "SELECT instance_id FROM canon_item_instances WHERE owner_kind = ? AND owner_id = ? AND location_kind = ? AND source_id = ? AND location_index = ? AND terminal_reason IS NULL;"
	var bindings: Array = [owner.kind, owner.id, location.kind, location.slot] if location.kind == "equipped" else [owner.kind, owner.id, location.kind, location.source_id, location.index]
	var selected: Dictionary = _store.query_with_bindings(sql, bindings)
	return {"outcome": selected.outcome, "detail": selected.detail, "occupied": selected.outcome == "ok" and not selected.rows.is_empty()}


func _read_revision(sql: String, bindings: Array) -> Dictionary:
	var selected: Dictionary = _store.query_with_bindings(sql, bindings)
	if selected.outcome != "ok":
		return _revision_result("query_failed", selected.detail)
	if selected.rows.is_empty():
		return _revision_result("ok", "", 0)
	if not _revision(selected.rows[0].revision):
		return _revision_result("corrupt_record", "revision must remain an exact nonnegative integer")
	return _revision_result("ok", "", selected.rows[0].revision)


func _find_receipt(actor: String, operation_id: String, fingerprint: String) -> Dictionary:
	var selected: Dictionary = _store.query_with_bindings("SELECT * FROM canon_item_operations WHERE actor_character_id = ? AND operation_id = ?;", [actor, operation_id])
	if selected.outcome != "ok":
		return _command_result("query_failed", selected.detail)
	if selected.rows.is_empty():
		return _command_result("not_found", "receipt not found")
	var row: Dictionary = selected.rows[0]
	if row.fingerprint != fingerprint:
		return _command_result("operation_conflict", "operation key already committed with different intent")
	if not _revision(row.instance_revision) or not _revision(row.owner_revision) or not _revision(row.location_revision) or row.operation_kind not in ["create", "retire"] or not _identifier(row.instance_id):
		return _command_result("corrupt_record", "receipt fields are invalid")
	return _command_result("ok", "", _new_receipt(row.operation_kind, row.actor_character_id, row.operation_id, row.instance_id, row.instance_revision, row.owner_revision, row.location_revision))


func _insert_receipt(receipt: Dictionary, fingerprint: String) -> bool:
	return _store.query_with_bindings("INSERT INTO canon_item_operations (actor_character_id, operation_id, operation_kind, fingerprint, instance_id, instance_revision, owner_revision, location_revision) VALUES (?, ?, ?, ?, ?, ?, ?, ?);", [receipt.actor_character_id, receipt.operation_id, receipt.operation_kind, fingerprint, receipt.instance_id, receipt.instance_revision, receipt.owner_revision, receipt.location_revision]).outcome == "ok"


func _fingerprint(kind: String, actor: String, operation_id: String, data: Dictionary, definition: ItemDefinition, owner_revision: int, location_revision: int, reason: String) -> String:
	var logical: Dictionary = data.duplicate(true)
	logical.acquisition.erase("server_tick")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(_canonical([kind, actor, operation_id, logical, definition.to_wire_dict(), owner_revision, location_revision, reason])))
	return context.finish().hex_encode()


func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var sorted: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: String in keys:
			sorted[key] = _canonical(value[key])
		return sorted
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_canonical(entry))
		return result
	return value


func _open() -> bool:
	return _store != null and _store.is_open()


static func _identifier(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _revision(value: Variant) -> bool:
	return value is int and value >= 0


static func _owner(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and value.get("kind") in ["character", "world_container"] and _identifier(value.get("id"))


static func _address(owner: Variant, location: Variant) -> bool:
	if not _owner(owner) or not (location is Dictionary):
		return false
	if location.get("kind") == "equipped":
		return owner.kind == "character" and location.size() == 2 and location.get("slot") in MetadataScript.SLOTS
	if location.get("kind") == "loot_position":
		return owner.kind == "world_container" and location.size() == 3 and location.get("source_id") == owner.id and _revision(location.get("index"))
	return false


static func _address_bindings(owner: Dictionary, location: Dictionary) -> Array:
	return [owner.kind, owner.id, location.kind, location.get("slot", ""), location.get("source_id", ""), location.get("index", -1)]


static func _new_receipt(kind: String, actor: String, operation_id: String, instance_id: String, instance_revision: int, owner_revision: int, location_revision: int) -> Dictionary:
	return {"operation_kind": kind, "actor_character_id": actor, "operation_id": operation_id, "instance_id": instance_id, "instance_revision": instance_revision, "owner_revision": owner_revision, "location_revision": location_revision}


static func _command_result(outcome: String, detail: String, receipt: Variant = null) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "receipt": receipt}


static func _instance_result(outcome: String, detail: String, instance: ItemInstance = null) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "instance": instance}


static func _revision_result(outcome: String, detail: String, revision: int = -1) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "revision": revision}


func _definition_from_row(row: Dictionary) -> Dictionary:
	if not (row.base_effect_integer is int) or row.base_effect_integer not in [0, 1]:
		return _definition_result("corrupt_record", "effect numeric type is invalid")
	if not (row.base_effect is int or row.base_effect is float):
		return _definition_result("corrupt_record", "effect is not numeric")
	var effect: float = float(row.base_effect)
	if not is_finite(effect) or effect < 0.0 or effect > MetadataScript.MAX_BASE_EFFECT:
		return _definition_result("corrupt_record", "effect is out of bounds")
	if row.base_effect_integer == 1 and effect != floorf(effect):
		return _definition_result("corrupt_record", "integer effect lost precision")
	var wire: Dictionary = {
		"schema_version": row.schema_version, "definition_id": row.definition_id,
		"definition_revision": row.definition_revision, "item_class": row.item_class,
		"slot": row.slot, "category": row.category, "maximum_stack": row.maximum_stack,
		"binding_policy": row.binding_policy, "base_effect": int(effect) if row.base_effect_integer == 1 else effect,
	}
	var validation: Dictionary = DefinitionScript.from_wire_dict(wire)
	if validation.definition == null:
		return _definition_result("corrupt_record", validation.detail)
	return _definition_result("ok", "", validation.definition)


static func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}


static func _definition_result(outcome: String, detail: String, definition: ItemDefinition = null) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "definition": definition}
