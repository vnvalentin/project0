extends RefCounted
class_name VesselProgressionState
## Slice 133 (Phase 15, P-016-A): the durable, server-owned six-node vessel a
## Character earns through play, plus the fixed-budget redistribution the spec
## mandates. Pure value + deterministic helpers — no scene tree, no network I/O,
## no authority, no secrets; the server owns the live state and only ever
## replicates a derived, presentation-safe snapshot (Slice 134). See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md (redistribution
## shape) and issues #219/#223.
##
## `base_nodes` is FROZEN EARNED STATE: what the player worked for. Every gain
## preserves the fixed budget by compressing opposing nodes (weighted, floored),
## re-spreading any floored deficit across still-eligible opposers, and rejecting
## atomically only when no eligible capacity remains. A vessel is PINNED to the
## `tuning_version` it was built under; future gains use that pinned tuning.

const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")

const SCHEMA_VERSION: int = 1
const BUDGET_EPSILON: float = 0.0001

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_UNSUPPORTED_NODE: String = "unsupported_node"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_BUDGET_VIOLATION: String = "budget_violation"
## A gain that cannot preserve the budget (every opposer already at its floor).
const OUTCOME_REJECTED_AT_CAPACITY: String = "rejected_at_capacity"
## The supplied tuning is not the one this vessel is pinned to.
const OUTCOME_TUNING_MISMATCH: String = "tuning_mismatch"

var schema_version: int
var tuning_version: String
var base_nodes: Dictionary


func _init(p_tuning_version: String, p_base_nodes: Dictionary) -> void:
	schema_version = SCHEMA_VERSION
	tuning_version = p_tuning_version
	base_nodes = p_base_nodes


## Server-side factory: a fresh vessel with the balanced baseline (budget split
## equally across the six nodes), pinned to the given tuning.
static func create_baseline(tuning: Object) -> VesselProgressionState:
	var per_node: float = tuning.budget / float(SchemaScript.NODE_KEYS.size())
	var base: Dictionary = {}
	for key: String in SchemaScript.NODE_KEYS:
		base[key] = per_node
	return VesselProgressionState.new(tuning.tuning_version, base)


## Apply a training gain to one node, compressing its opposers to preserve the
## fixed budget. Atomic: on any non-ok outcome nothing changes. Uses the pinned
## tuning (the supplied tuning must match this vessel's version). Returns
## {outcome, detail}.
func train(trained_node: String, evidence_units: float, tuning: Object) -> Dictionary:
	if not SchemaScript.is_supported_node(trained_node):
		return _result(OUTCOME_UNSUPPORTED_NODE, "unknown node: %s" % trained_node)
	if not is_finite(evidence_units) or evidence_units <= 0.0:
		return _result(OUTCOME_MALFORMED, "evidence_units must be a positive finite number")
	if String(tuning.tuning_version) != tuning_version:
		return _result(OUTCOME_TUNING_MISMATCH, "tuning does not match the vessel's pinned version")
	var gain: float = evidence_units * tuning.gain_per_evidence
	var redistributed: Dictionary = _redistribute(trained_node, gain, tuning)
	if redistributed["outcome"] != OUTCOME_OK:
		return _result(redistributed["outcome"], redistributed["detail"])
	# Commit atomically only on success.
	base_nodes = redistributed["nodes"]
	return _result(OUTCOME_OK, "")


## Parse + validate an untrusted persisted/wire Dictionary. Fails closed on
## version, structure, node bounds, and the fixed budget. Returns
## {outcome, detail, vessel}.
static func from_wire_dict(wire: Variant, tuning: Object) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var version: Variant = data.get("tuning_version")
	if not (version is String) or String(version).is_empty():
		return _fail(OUTCOME_MALFORMED, "tuning_version must be a non-empty string")
	var raw_nodes: Variant = data.get("base_nodes")
	if not (raw_nodes is Dictionary):
		return _fail(OUTCOME_MALFORMED, "base_nodes is not a Dictionary")
	var raw: Dictionary = raw_nodes
	if raw.size() != SchemaScript.NODE_KEYS.size():
		return _fail(OUTCOME_MALFORMED, "base_nodes must have exactly six nodes")
	var nodes: Dictionary = {}
	for key: String in SchemaScript.NODE_KEYS:
		if not raw.has(key):
			return _fail(OUTCOME_MALFORMED, "missing node: %s" % key)
		var value: Variant = raw[key]
		if not (value is float or value is int):
			return _fail(OUTCOME_MALFORMED, "node value is not numeric: %s" % key)
		var num: float = float(value)
		if SchemaScript.check_bounded(num, 0.0, SchemaScript.MAX_NODE_VALUE) != SchemaScript.OUTCOME_OK:
			return _fail(OUTCOME_OUT_OF_BOUNDS, "node value out of bounds: %s" % key)
		nodes[key] = num
	if absf(SchemaScript.sum_over_nodes(nodes) - tuning.budget) > BUDGET_EPSILON:
		return _fail(OUTCOME_BUDGET_VIOLATION, "base_nodes must preserve the fixed budget")
	var vessel := VesselProgressionState.new(String(version), nodes)
	return {"outcome": OUTCOME_OK, "detail": "", "vessel": vessel}


## Deterministic weighted, floored redistribution: add `gain` to the trained node
## and remove `gain` total from its opposers, weighted, never below floor,
## re-spreading a floored deficit across still-eligible opposers. Rejects when
## the opposers' total capacity above their floors cannot absorb the gain.
func _redistribute(trained_node: String, gain: float, tuning: Object) -> Dictionary:
	var weights: Dictionary = tuning.opposition_weights_for(trained_node)
	var floor: float = tuning.floor_for(trained_node)
	var opposers: PackedStringArray = []
	for opp: String in SchemaScript.other_nodes(trained_node):
		if float(weights.get(opp, 0.0)) > 0.0:
			opposers.append(opp)
	var capacity: Dictionary = {}
	var total_capacity: float = 0.0
	for opp: String in opposers:
		var cap: float = maxf(0.0, float(base_nodes[opp]) - floor)
		capacity[opp] = cap
		total_capacity += cap
	if total_capacity < gain - BUDGET_EPSILON:
		return {"outcome": OUTCOME_REJECTED_AT_CAPACITY, "detail": "opposers cannot absorb the gain without breaching floors", "nodes": {}}
	var removed: Dictionary = {}
	for opp: String in opposers:
		removed[opp] = 0.0
	var remaining: float = gain
	var iterations: int = 0
	# Re-spread until the whole gain is removed. Bounded: each pass either fills a
	# node to capacity or removes the remainder; 32 passes over six nodes is ample.
	while remaining > BUDGET_EPSILON and iterations < 32:
		iterations += 1
		var eligible: PackedStringArray = []
		var total_weight: float = 0.0
		for opp: String in opposers:
			if float(capacity[opp]) - float(removed[opp]) > BUDGET_EPSILON:
				eligible.append(opp)
				total_weight += float(weights[opp])
		if eligible.is_empty() or total_weight <= 0.0:
			break
		var removed_this_pass: float = 0.0
		for opp: String in eligible:
			var share: float = remaining * float(weights[opp]) / total_weight
			var avail: float = float(capacity[opp]) - float(removed[opp])
			var take: float = minf(share, avail)
			removed[opp] = float(removed[opp]) + take
			removed_this_pass += take
		remaining = gain - _sum_values(removed)
		if removed_this_pass <= BUDGET_EPSILON:
			break
	if remaining > BUDGET_EPSILON:
		return {"outcome": OUTCOME_REJECTED_AT_CAPACITY, "detail": "gain could not be fully redistributed", "nodes": {}}
	var new_nodes: Dictionary = base_nodes.duplicate()
	new_nodes[trained_node] = float(base_nodes[trained_node]) + gain
	for opp: String in opposers:
		new_nodes[opp] = float(base_nodes[opp]) - float(removed[opp])
	return {"outcome": OUTCOME_OK, "detail": "", "nodes": new_nodes}


static func _sum_values(node_map: Dictionary) -> float:
	var total: float = 0.0
	for key: Variant in node_map:
		total += float(node_map[key])
	return total


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "vessel": null}
