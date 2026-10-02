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
	return _store.query("""
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


func register_definition(wire: Variant) -> Dictionary:
	if _store == null or not _store.is_open():
		return _definition_result("not_open", "store is not open")
	var validation: Dictionary = DefinitionScript.from_wire_dict(wire)
	if validation.definition == null:
		return _definition_result("invalid_definition", validation.detail)
	var data: Dictionary = validation.definition.to_wire_dict()
	var existing: Dictionary = get_definition(data.definition_id, data.definition_revision)
	if existing.outcome == "ok":
		if existing.definition.to_wire_dict() == data:
			return existing
		return _definition_result("definition_conflict", "definition revision already exists")
	if existing.outcome != "not_found":
		return existing
	var transaction: Dictionary = _store.transaction(func() -> bool:
		return _store.query_with_bindings(
			"INSERT INTO canon_item_definitions (definition_id, definition_revision, schema_version, item_class, slot, category, maximum_stack, binding_policy, base_effect, base_effect_integer) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			[data.definition_id, data.definition_revision, data.schema_version, data.item_class, data.slot,
			 data.category, data.maximum_stack, data.binding_policy, data.base_effect, 1 if data.base_effect is int else 0]
		).outcome == "ok"
	)
	if transaction.outcome != "ok":
		return _definition_result("transaction_failed", transaction.detail)
	return _definition_result("ok", "", validation.definition)


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
