extends RefCounted
class_name TechniqueContract
## Slice 119 (Phase 14): the technique definition + readiness contract. Pure
## value + deterministic helpers, like the other shared contracts
## (shared/character_foundation.gd, shared/item_contract.gd): no scene tree, no
## network I/O, no authority, no secrets. See issues #230/#234 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## A technique is NOT unlocked by a single stat threshold. It becomes usable
## when a Character develops the whole COMBINATION of attributes its action
## needs — e.g. a Jump Slash needs enough STR to leave the ground, DEX to swing
## airborne, WIS to read the blade, and INT to concentrate on the sequence.
## Readiness is a pure predicate over effective nodes; per-Character technique
## proficiency (0..1) then drives how reliably it executes. Proficiency decay,
## failed-attempts-teach, teaching flow, discovery, and combinations are later
## slices; this contract only defines a technique and derives readiness,
## reliability, and mastery from given values.

const SCHEMA_VERSION: int = 1

## The six vessel nodes a requirement may reference.
const SUPPORTED_NODES: PackedStringArray = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]

const PROFICIENCY_MIN: float = 0.0
const PROFICIENCY_MAX: float = 1.0
## At full proficiency the technique is permanently known and fully reliable.
const MASTERY_THRESHOLD: float = 1.0
const MAX_REQUIREMENT: float = 1.0e9

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_UNSUPPORTED_NODE: String = "unsupported_node"
const OUTCOME_EMPTY_REQUIREMENTS: String = "empty_requirements"
const OUTCOME_PRIMARY_NOT_REQUIRED: String = "primary_not_required"

var schema_version: int
var technique_id: String
var primary_node: String
var requirements: Dictionary


func _init(p_technique_id: String, p_primary_node: String, p_requirements: Dictionary) -> void:
	schema_version = SCHEMA_VERSION
	technique_id = p_technique_id
	primary_node = p_primary_node
	requirements = p_requirements


## True when every required node meets its threshold in the given effective
## nodes. A missing node reads as 0.0 and therefore fails any positive threshold.
func is_ready(effective_nodes: Dictionary) -> bool:
	for node in requirements:
		if float(effective_nodes.get(node, 0.0)) < float(requirements[node]):
			return false
	return true


## Per-node shortfalls: node -> deficit (> 0) for each requirement not yet met.
## Empty when the technique is ready.
func readiness_shortfalls(effective_nodes: Dictionary) -> Dictionary:
	var shortfalls: Dictionary = {}
	for node in requirements:
		var deficit: float = float(requirements[node]) - float(effective_nodes.get(node, 0.0))
		if deficit > 0.0:
			shortfalls[node] = deficit
	return shortfalls


## Reliability/quality of execution for a given per-Character proficiency,
## clamped to 0..1. Low proficiency executes unreliably; mastery is fully
## reliable. Deterministic; the combat layer decides how to consume it.
static func reliability(proficiency: float) -> float:
	return clampf(proficiency, PROFICIENCY_MIN, PROFICIENCY_MAX)


## Whether this proficiency is full mastery (permanently known).
static func is_mastered(proficiency: float) -> bool:
	return clampf(proficiency, PROFICIENCY_MIN, PROFICIENCY_MAX) >= MASTERY_THRESHOLD


## Whether a Character with this proficiency may formally teach the technique.
## Teaching requires mastery (any willing learner may then be taught).
static func can_teach(proficiency: float) -> bool:
	return is_mastered(proficiency)


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, the requirements map (nodes/thresholds), and the primary node.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var technique_id: Variant = data.get("technique_id")
	if not (technique_id is String) or String(technique_id).is_empty():
		return _fail(OUTCOME_MALFORMED, "technique_id must be a non-empty string")
	var raw_requirements: Variant = data.get("requirements")
	if not (raw_requirements is Dictionary):
		return _fail(OUTCOME_MALFORMED, "requirements is not a Dictionary")
	var reqs: Dictionary = raw_requirements
	if reqs.is_empty():
		return _fail(OUTCOME_EMPTY_REQUIREMENTS, "requirements must not be empty")
	var validated: Dictionary = {}
	for node in reqs:
		if not (node is String) or not SUPPORTED_NODES.has(node):
			return _fail(OUTCOME_UNSUPPORTED_NODE, "unknown required node")
		var threshold_raw: Variant = reqs[node]
		if not (threshold_raw is float or threshold_raw is int):
			return _fail(OUTCOME_MALFORMED, "threshold is not numeric")
		var threshold: float = float(threshold_raw)
		if not is_finite(threshold) or threshold < 0.0 or threshold > MAX_REQUIREMENT:
			return _fail(OUTCOME_OUT_OF_BOUNDS, "threshold out of bounds")
		validated[node] = threshold
	var primary: Variant = data.get("primary_node")
	if not (primary is String) or not SUPPORTED_NODES.has(primary):
		return _fail(OUTCOME_UNSUPPORTED_NODE, "unknown primary_node")
	if not validated.has(primary):
		return _fail(OUTCOME_PRIMARY_NOT_REQUIRED, "primary_node must be one of the requirements")
	var technique := TechniqueContract.new(String(technique_id), String(primary), validated)
	return {"outcome": OUTCOME_OK, "detail": "", "technique": technique}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "technique": null}
