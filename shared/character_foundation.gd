extends RefCounted
class_name CharacterFoundation
## Slice 116 (Phase 14): the unified, server-authoritative Character foundation
## shared by players and NPCs. One contract, one fixed baseline, one
## presentation-safe snapshot. Pure value + stateless helpers, like the other
## shared value contracts (shared/character_record.gd, shared/world_scale.gd):
## no scene tree, no network I/O, no authority, no secrets. Both processes read
## it identically. See docs/adr/0007-unified-character-and-npc-generalization.md
## and docs/slices/116-phase14-character-foundation-handoff.md.
##
## controller_type (PLAYER vs AI) is separate from disposition and from the
## six-node vessel: a player and an NPC are the SAME Character, differing only by
## controller and kind context. base_nodes is the fixed-area creation baseline;
## development is the uncapped organic layer above it. The presentation snapshot
## exposes ONLY normalized graph proportions, never raw numeric stat values.

const SCHEMA_VERSION: int = 1

const CONTROLLER_PLAYER: String = "PLAYER"
const CONTROLLER_AI: String = "AI"
const SUPPORTED_CONTROLLERS: PackedStringArray = ["PLAYER", "AI"]

const KIND_HUMANOID: String = "humanoid"

## Fixed, deterministic node order. Never reorder without a SCHEMA_VERSION bump.
const NODE_KEYS: PackedStringArray = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]

## Fixed balanced creation baseline: the fixed-area budget split equally.
const BASELINE_BUDGET: float = 60.0
const BASELINE_PER_NODE: float = 10.0

## Boundary guards. Development is uncapped by design, but the contract still
## rejects non-finite or absurd values fail-closed.
const MIN_BASE_VALUE: float = 0.0
const MIN_DEVELOPMENT_VALUE: float = 0.0
const MAX_NODE_VALUE: float = 1.0e9
const BUDGET_EPSILON: float = 0.0001

const OUTCOME_OK: String = "ok"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_CONTROLLER: String = "unsupported_controller"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_BUDGET_VIOLATION: String = "budget_violation"

var schema_version: int
var controller_type: String
var character_kind: String
var base_nodes: Dictionary
var development: Dictionary


func _init(
	p_controller_type: String,
	p_character_kind: String,
	p_base_nodes: Dictionary,
	p_development: Dictionary
) -> void:
	schema_version = SCHEMA_VERSION
	controller_type = p_controller_type
	character_kind = p_character_kind
	base_nodes = p_base_nodes
	development = p_development


## Server-side factory: a fresh Character with the fixed balanced baseline and
## zero development. Returns {outcome, detail, character}. Fails closed on an
## unsupported controller so no caller can mint an out-of-contract Character.
static func create_baseline(controller_type: String, character_kind: String) -> Dictionary:
	if not SUPPORTED_CONTROLLERS.has(controller_type):
		return _fail(OUTCOME_UNSUPPORTED_CONTROLLER, "unknown controller_type")
	if character_kind.is_empty():
		return _fail(OUTCOME_MALFORMED, "character_kind must be a non-empty string")
	var base: Dictionary = {}
	var dev: Dictionary = {}
	for key in NODE_KEYS:
		base[key] = BASELINE_PER_NODE
		dev[key] = 0.0
	var character := CharacterFoundation.new(controller_type, character_kind, base, dev)
	return {"outcome": OUTCOME_OK, "detail": "", "character": character}


## Parse + validate an untrusted wire Dictionary into a typed Character. Fails
## closed: version, structure, controller, finiteness/bounds, and the fixed
## budget are all checked before a Character is returned.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var controller: Variant = data.get("controller_type")
	if not (controller is String) or not SUPPORTED_CONTROLLERS.has(controller):
		return _fail(OUTCOME_UNSUPPORTED_CONTROLLER, "unknown controller_type")
	var kind: Variant = data.get("character_kind")
	if not (kind is String) or String(kind).is_empty():
		return _fail(OUTCOME_MALFORMED, "character_kind must be a non-empty string")
	var base_result: Dictionary = _validate_node_map(data.get("base_nodes"), MIN_BASE_VALUE)
	if base_result["outcome"] != OUTCOME_OK:
		return base_result
	var dev_result: Dictionary = _validate_node_map(data.get("development"), MIN_DEVELOPMENT_VALUE)
	if dev_result["outcome"] != OUTCOME_OK:
		return dev_result
	var base: Dictionary = base_result["nodes"]
	if absf(_sum_values(base) - BASELINE_BUDGET) > BUDGET_EPSILON:
		return _fail(OUTCOME_BUDGET_VIOLATION, "base_nodes must preserve the fixed budget")
	var character := CharacterFoundation.new(String(controller), String(kind), base, dev_result["nodes"])
	return {"outcome": OUTCOME_OK, "detail": "", "character": character}


## Pure derivation: effective node = base + development for every node.
## Deterministic and order-stable; no clamping beyond the validated bounds.
static func derive_effective_nodes(p_base_nodes: Dictionary, p_development: Dictionary) -> Dictionary:
	var effective: Dictionary = {}
	for key in NODE_KEYS:
		effective[key] = float(p_base_nodes.get(key, 0.0)) + float(p_development.get(key, 0.0))
	return effective


## This instance's effective nodes.
func effective_nodes() -> Dictionary:
	return derive_effective_nodes(base_nodes, development)


## Presentation-safe snapshot for the client. Exposes ONLY normalized graph
## proportions (each axis's share of the effective total, summing to 1.0) plus
## controller/kind context — never the raw base, development, or effective
## numbers. The client draws the spider-graph SHAPE without learning values.
func to_presentation_snapshot() -> Dictionary:
	var effective: Dictionary = effective_nodes()
	var total: float = _sum_values(effective)
	var axes: Dictionary = {}
	for key in NODE_KEYS:
		axes[key] = (float(effective[key]) / total) if total > 0.0 else 0.0
	return {
		"schema_version": schema_version,
		"controller_type": controller_type,
		"character_kind": character_kind,
		"graph_axes": axes,
	}


static func _validate_node_map(value: Variant, min_value: float) -> Dictionary:
	if not (value is Dictionary):
		return _fail(OUTCOME_MALFORMED, "node map is not a Dictionary")
	var raw: Dictionary = value
	if raw.size() != NODE_KEYS.size():
		return _fail(OUTCOME_MALFORMED, "node map must have exactly six nodes")
	var nodes: Dictionary = {}
	for key in NODE_KEYS:
		if not raw.has(key):
			return _fail(OUTCOME_MALFORMED, "missing node: " + key)
		var raw_value: Variant = raw[key]
		if not (raw_value is float or raw_value is int):
			return _fail(OUTCOME_MALFORMED, "node value is not numeric: " + key)
		var num: float = float(raw_value)
		if not is_finite(num):
			return _fail(OUTCOME_OUT_OF_BOUNDS, "node value is not finite: " + key)
		if num < min_value or num > MAX_NODE_VALUE:
			return _fail(OUTCOME_OUT_OF_BOUNDS, "node value out of bounds: " + key)
		nodes[key] = num
	return {"outcome": OUTCOME_OK, "detail": "", "nodes": nodes}


static func _sum_values(node_map: Dictionary) -> float:
	var total: float = 0.0
	for key in NODE_KEYS:
		total += float(node_map.get(key, 0.0))
	return total


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "character": null}
