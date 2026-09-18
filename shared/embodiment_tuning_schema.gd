extends RefCounted
class_name EmbodimentTuningSchema
## Slice 132 (Phase 15, P-016-A): the shared, tool-neutral shape of embodiment
## tuning — bounds, outcome enums, and pure derivation helpers both the server
## and client interpret identically. No state, no tables, no authority. The
## frozen numeric tables and the resolve() registry live server-side in
## server/embodiment_tuning.gd; this module only defines the SHAPE and the
## validation/derivation both processes share. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md and issue #220.

const SCHEMA_VERSION: int = 1

## The six vessel nodes, in a fixed, deterministic order (matches
## CharacterFoundation.NODE_KEYS). Never reorder without a SCHEMA_VERSION bump.
const NODE_KEYS: PackedStringArray = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]

const MIN_BUDGET: float = 1.0
const MAX_BUDGET: float = 1.0e6
const MIN_FLOOR: float = 0.0
const MAX_NODE_VALUE: float = 1.0e9
const MIN_GAIN: float = 0.0
const MAX_GAIN: float = 1.0e6
const MIN_WEIGHT: float = 0.0
const MAX_WEIGHT: float = 1.0e6

const OUTCOME_OK: String = "ok"
const OUTCOME_UNSUPPORTED_TUNING_VERSION: String = "unsupported_tuning_version"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"


## Whether a value is one of the six supported vessel nodes.
static func is_supported_node(node: Variant) -> bool:
	return node is String and NODE_KEYS.has(node)


## The five nodes other than the given one, in fixed order — the opposition set a
## trained node compresses. Empty for an unsupported node.
static func other_nodes(node: String) -> PackedStringArray:
	var others: PackedStringArray = []
	for key: String in NODE_KEYS:
		if key != node:
			others.append(key)
	return others


## Deterministic sum of a node map over the fixed node order (missing = 0).
static func sum_over_nodes(node_map: Dictionary) -> float:
	var total: float = 0.0
	for key: String in NODE_KEYS:
		total += float(node_map.get(key, 0.0))
	return total


## Validates a finite, in-bounds numeric value for the given field; returns an
## OUTCOME_* string. Used by the server resolve() to fail closed on bad tables.
static func check_bounded(value: float, min_value: float, max_value: float) -> String:
	if not is_finite(value):
		return OUTCOME_OUT_OF_BOUNDS
	if value < min_value or value > max_value:
		return OUTCOME_OUT_OF_BOUNDS
	return OUTCOME_OK
