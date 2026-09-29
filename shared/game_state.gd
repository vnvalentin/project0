extends RefCounted
class_name GameState
## Experiment 1 for Epic #1291: the server-owned player stat aggregate.
## This value contract is pure and deterministic. The server creates and owns
## it; clients receive snapshots and cannot mutate it through this seam.

const KineticFlowScript: Script = preload("res://shared/kinetic_flow.gd")

const SCHEMA_VERSION: int = 1
const NODE_KEYS: PackedStringArray = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const STAT_KEYS: PackedStringArray = [
	"STR", "DEX", "CON", "INT", "WIS", "CHA",
	"KineticVolume", "KineticControl", "KineticOutput", "BaseHP", "BaseStamina"
]
const MAX_ATTRIBUTE_VALUE: float = 1.0e9

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_CLIENT_MUTATION_REJECTED: String = "client_mutation_rejected"
const CLIENT_MUTATION_HTTP_STATUS: int = 422

var schema_version: int
var stats: Dictionary


func _init(p_stats: Dictionary) -> void:
	schema_version = SCHEMA_VERSION
	stats = p_stats


## Server-side factory. The supplied tuning is server-owned and never comes
## from a client payload.
static func create_stat_aggregate(initial_nodes: Dictionary, tuning: Object) -> Dictionary:
	var validation: Dictionary = _validate_nodes(initial_nodes)
	if validation["outcome"] != OUTCOME_OK:
		return {"outcome": validation["outcome"], "detail": validation["detail"], "state": null}
	var nodes: Dictionary = validation["nodes"]
	var kinetic: Dictionary = KineticFlowScript.derive(nodes, tuning)
	var stat_tuning: Dictionary = tuning.stats()
	var base_hp: float = maxf(
		0.0,
		float(stat_tuning["hp_base"])
			+ float(nodes["CON"]) * float(stat_tuning["hp_per_con"])
			+ float(kinetic["volume"]) * float(stat_tuning["hp_per_volume"])
	)
	var base_stamina: float = maxf(
		0.0,
		float(stat_tuning["stamina_base"])
			+ float(nodes["CON"]) * float(stat_tuning["stamina_per_con"])
			+ float(kinetic["control"]) * float(stat_tuning["stamina_per_control"])
	)
	var aggregate: Dictionary = nodes.duplicate()
	aggregate["KineticVolume"] = float(kinetic["volume"])
	aggregate["KineticControl"] = float(kinetic["control"])
	aggregate["KineticOutput"] = float(kinetic["output"])
	aggregate["BaseHP"] = base_hp
	aggregate["BaseStamina"] = base_stamina
	return {"outcome": OUTCOME_OK, "detail": "", "state": new(aggregate)}


## A client may request presentation or actions, but never writes this state.
## The server rejects the payload before it can reach the aggregate.
func reject_client_mutation(_payload: Variant) -> Dictionary:
	return {
		"outcome": OUTCOME_CLIENT_MUTATION_REJECTED,
		"detail": "client mutation of server-owned stats is not permitted",
		"http_status": CLIENT_MUTATION_HTTP_STATUS,
	}


func to_snapshot() -> Dictionary:
	return {"schema_version": schema_version, "stats": stats.duplicate()}


static func _validate_nodes(initial_nodes: Dictionary) -> Dictionary:
	if initial_nodes.size() != NODE_KEYS.size():
		return _fail(OUTCOME_MALFORMED, "initial_nodes must have exactly six attributes")
	var nodes: Dictionary = {}
	for key: String in NODE_KEYS:
		if not initial_nodes.has(key):
			return _fail(OUTCOME_MALFORMED, "missing attribute: %s" % key)
		var raw_value: Variant = initial_nodes[key]
		if not (raw_value is float or raw_value is int):
			return _fail(OUTCOME_MALFORMED, "attribute is not numeric: %s" % key)
		var value: float = float(raw_value)
		if not is_finite(value) or value < 0.0 or value > MAX_ATTRIBUTE_VALUE:
			return _fail(OUTCOME_OUT_OF_BOUNDS, "attribute is out of bounds: %s" % key)
		nodes[key] = value
	return {"outcome": OUTCOME_OK, "detail": "", "nodes": nodes}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "nodes": {}}