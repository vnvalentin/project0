extends RefCounted
class_name InteriorAnchorRepository
## #849 server-owned immutable anchor registration; does not grant entry access.

const Contract: Script = preload("res://shared/interior_anchor_contract.gd")
const Guid: Script = preload("res://shared/canon_entity_guid.gd")
const Resolver: Script = preload("res://shared/canon_sector_resolver.gd")
const Canon: Script = preload("res://server/canon_repository.gd")
const Mutations: Script = preload("res://server/canon_mutation_repository.gd")
const Integrity: Script = preload("res://server/canon_sector_integrity.gd")

var _store: SqliteStore
var _canon: CanonRepository
var _mutations: CanonMutationRepository


func _init(store: SqliteStore) -> void:
	_store = store
	_canon = Canon.new(store)
	_mutations = Mutations.new(store, _canon)


func ensure_schema() -> Dictionary:
	if not _ready():
		return _result("not_open", "Anchor persistence dependencies are not open.")
	return _store.transaction(func() -> bool:
		var anchors: Dictionary = _store.query("""
			CREATE TABLE IF NOT EXISTS interior_anchors (
				interior_id TEXT PRIMARY KEY,
				exterior_sector_id TEXT NOT NULL,
				exterior_entity_guid TEXT NOT NULL,
				plot_id TEXT NOT NULL,
				entry_json TEXT NOT NULL,
				schema_version INTEGER NOT NULL CHECK (schema_version = 1),
				revision INTEGER NOT NULL CHECK (revision = 1),
				exterior_revision INTEGER NOT NULL CHECK (exterior_revision >= 0),
				UNIQUE(exterior_sector_id, exterior_entity_guid)
			);
		""")
		if anchors["outcome"] != "ok":
			return false
		var cells: Dictionary = _store.query("""
			CREATE TABLE IF NOT EXISTS interior_cells (
				interior_id TEXT NOT NULL REFERENCES interior_anchors(interior_id),
				cell_x INTEGER NOT NULL,
				cell_y INTEGER NOT NULL,
				cell_z INTEGER NOT NULL,
				bounds_min_json TEXT NOT NULL,
				bounds_max_json TEXT NOT NULL,
				streaming_reference TEXT NOT NULL,
				revision INTEGER NOT NULL CHECK (revision = 1),
				PRIMARY KEY(interior_id, cell_x, cell_y, cell_z)
			);
		""")
		return cells["outcome"] == "ok"
	)


func register_anchor(server_descriptor: Variant) -> Dictionary:
	if not _ready():
		return _result("not_open", "Anchor persistence dependencies are not open.")
	var parsed: Dictionary = Contract.parse_server_descriptor(server_descriptor)
	if parsed["outcome"] != "ok":
		return parsed
	var anchor: InteriorAnchorContract.AnchorValue = parsed["anchor"]
	var state: Dictionary = {}
	var committed: Dictionary = _store.transaction(func() -> bool:
		var exterior: Dictionary = _exterior_context(anchor.exterior_sector_id, anchor.exterior_entity_guid)
		if exterior["outcome"] != "ok":
			state["result"] = exterior
			return false
		var retained: Dictionary = _lookup("a.exterior_sector_id = ? AND a.exterior_entity_guid = ?", [anchor.exterior_sector_id, anchor.exterior_entity_guid])
		if retained["outcome"] != "not_found":
			if retained["outcome"] != "ok":
				state["result"] = retained
				return false
			var previous: InteriorAnchorContract.AnchorValue = retained["anchor"]
			var identical: bool = previous.to_descriptor() == anchor.to_descriptor()
			state["result"] = {"outcome": "idempotent" if identical else "conflict", "detail": "Exterior reference is already bound.", "anchor": previous}
			return false
		anchor.exterior_revision = exterior["revision"]
		var descriptor: Dictionary = anchor.to_descriptor()
		var inserted: Dictionary = _store.query_with_bindings(
			"INSERT INTO interior_anchors (interior_id, exterior_sector_id, exterior_entity_guid, plot_id, entry_json, schema_version, revision, exterior_revision) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
			[anchor.interior_id, anchor.exterior_sector_id, anchor.exterior_entity_guid, anchor.plot_id, JSON.stringify(descriptor["entry_position"]), 1, 1, anchor.exterior_revision]
		)
		if inserted["outcome"] != "ok":
			return false
		var cell: Dictionary = _store.query_with_bindings(
			"INSERT INTO interior_cells (interior_id, cell_x, cell_y, cell_z, bounds_min_json, bounds_max_json, streaming_reference, revision) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
			[anchor.interior_id, anchor.cell_coordinate.x, anchor.cell_coordinate.y, anchor.cell_coordinate.z, JSON.stringify(descriptor["bounds_min"]), JSON.stringify(descriptor["bounds_max"]), anchor.streaming_reference, 1]
		)
		return cell["outcome"] == "ok"
	)
	if state.has("result"):
		return state["result"]
	if committed["outcome"] != "ok":
		return committed
	return {"outcome": "ok", "detail": "Interior anchor committed.", "anchor": anchor}


func get_anchor(interior_id: Variant) -> Dictionary:
	if not _ready():
		return _result("not_open", "Anchor persistence dependencies are not open.")
	if not Contract.valid_id(interior_id):
		return _result("invalid_anchor", "Interior identity is invalid.")
	return _lookup("a.interior_id = ?", [interior_id])


func resolve_entry(exterior_reference_intent: Variant) -> Dictionary:
	if not _ready():
		return _result("not_open", "Anchor persistence dependencies are not open.")
	var parsed: Dictionary = Contract.parse_entry_intent(exterior_reference_intent)
	if parsed["outcome"] != "ok":
		return parsed
	var intent: Dictionary = parsed["intent"]
	var exterior: Dictionary = _exterior_context(intent["exterior_sector_id"], intent["exterior_entity_guid"])
	if exterior["outcome"] != "ok":
		return exterior
	return _lookup("a.exterior_sector_id = ? AND a.exterior_entity_guid = ?", [intent["exterior_sector_id"], intent["exterior_entity_guid"]])


func _lookup(predicate: String, bindings: Array) -> Dictionary:
	# Predicate is selected only by this module; all variable values are bound.
	var selected: Dictionary = _store.query_with_bindings(
		"SELECT a.interior_id, a.exterior_sector_id, a.exterior_entity_guid, a.plot_id, a.entry_json, a.schema_version, a.revision, a.exterior_revision, c.cell_x, c.cell_y, c.cell_z, c.bounds_min_json, c.bounds_max_json, c.streaming_reference, c.revision AS cell_revision FROM interior_anchors a LEFT JOIN interior_cells c ON c.interior_id = a.interior_id WHERE " + predicate + ";",
		bindings
	)
	if selected["outcome"] != "ok":
		return selected
	var rows: Array = selected["rows"]
	if rows.is_empty():
		return _result("not_found", "No registered interior anchor.")
	if rows.size() != 1:
		return _result("invalid_record", "Initial anchor must have exactly one bound cell.")
	var row: Dictionary = rows[0]
	if row["cell_revision"] != 1:
		return _result("invalid_record", "Initial cell is absent or incompatible.")
	var record: Dictionary = {
		"schema_version": row["schema_version"], "interior_id": row["interior_id"],
		"exterior_sector_id": row["exterior_sector_id"], "exterior_entity_guid": row["exterior_entity_guid"],
		"plot_id": row["plot_id"], "entry_position": JSON.parse_string(row["entry_json"]),
		"cell_coordinate": [row["cell_x"], row["cell_y"], row["cell_z"]],
		"bounds_min": JSON.parse_string(row["bounds_min_json"]), "bounds_max": JSON.parse_string(row["bounds_max_json"]),
		"streaming_reference": row["streaming_reference"], "revision": row["revision"], "exterior_revision": row["exterior_revision"],
	}
	var parsed: Dictionary = Contract.parse_record(record)
	if parsed["outcome"] != "ok":
		return _result("invalid_record", parsed["detail"])
	return parsed


func _exterior_context(sector_id: String, entity_guid: String) -> Dictionary:
	var canonical: Dictionary = _canon.get_canonical_sector(sector_id)
	if canonical["outcome"] == "not_found":
		return _result("orphan_anchor", "Exterior sector is not Canon.")
	if canonical["outcome"] != "ok":
		return canonical
	var history: Dictionary = _mutations.list_mutations(sector_id)
	if history["outcome"] != "ok":
		return history
	var base: Dictionary = Integrity.inspect_base(sector_id, canonical, history)
	if base["outcome"] != "ok":
		return {"outcome": "invalid_record", "detail": "Exterior Canon integrity rejected.", "failure_class": base["failure_class"]}
	var inspected: Dictionary = Integrity.inspect_history(sector_id, base["blueprint"], history)
	if inspected["outcome"] != "ok":
		return {"outcome": "invalid_record", "detail": "Exterior mutation integrity rejected.", "failure_class": inspected["failure_class"]}
	var revision: int = inspected["revision"]
	if revision > Contract.MAX_REVISION:
		return _result("invalid_record", "Exterior mutation history is incompatible.")
	var effective: Dictionary = Resolver.resolve_effective_blueprint(base["blueprint"], inspected["mutations"])
	for entity: Dictionary in Guid.list_entities(effective):
		if entity["entity_class"] == "structure" and entity["guid"] == entity_guid:
			return {"outcome": "ok", "detail": "", "revision": revision}
	return _result("orphan_anchor", "Exterior structure is absent or destroyed.")


func _ready() -> bool:
	return _store != null and _store.is_open() and _canon != null and _mutations != null


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}
