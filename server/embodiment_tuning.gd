extends RefCounted
class_name EmbodimentTuning
## Slice 132 (Phase 15, P-016-A): the versioned, server-owned embodiment tuning
## registry. Frozen `const` tables behind the SOLE, fail-closed access seam
## `resolve(tuning_version)`. Subsystems (vessel, friction, kinetic, meridian,
## burnout, magic) never read the tables directly — they resolve a tuning by its
## opaque version string and read the returned value object. Server-owned: tuning
## values never ship to or are authored by the client, which only ever receives
## replicated derived results. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md and issues
## #219/#220.
##
## One tuning set exists today, internally namespaced by subsystem as the layers
## land. Its `tuning_version` is an opaque, immutable provenance stamp; a bump
## re-freezes the whole set. Unknown versions fail closed (no fallback guess) so
## the server never boots a mis-tuned authoritative world.

const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")

const SCHEMA_VERSION: int = 1

## The default (and currently only) tuning set's opaque provenance stamp.
const DEFAULT_TUNING_VERSION: String = "vessel-2026q4-baseline"

## Frozen vessel-foundation tables for the default set. Server-owned constants.
## Budget matches CharacterFoundation.BASELINE_BUDGET so a baseline Character and
## a fresh vessel agree on the fixed area.
const _BUDGET: float = 60.0
## No node may be compressed below this floor during redistribution.
const _FLOOR_PER_NODE: float = 4.0
## Bounded vessel gain applied per accepted unit of training evidence.
const _GAIN_PER_EVIDENCE: float = 1.0
## Opposition weights: for each trained node, the weight it compresses each of
## the other five by (0 = ineligible). Baseline set: uniform 1.0, i.e. training a
## node compresses its five opposers equally. Refined per-node weights are a
## later tuning revision behind this same seam (ADR 0006).
const _UNIFORM_WEIGHT: float = 1.0

var schema_version: int
var tuning_version: String
var budget: float
var floor_per_node: float
var gain_per_evidence: float


func _init(
	p_tuning_version: String,
	p_budget: float,
	p_floor_per_node: float,
	p_gain_per_evidence: float
) -> void:
	schema_version = SCHEMA_VERSION
	tuning_version = p_tuning_version
	budget = p_budget
	floor_per_node = p_floor_per_node
	gain_per_evidence = p_gain_per_evidence


## The SOLE access seam. Resolves an opaque tuning_version to its frozen value
## object, fail-closed: an unknown version yields no tuning (no fallback guess),
## and a table that violates its own bounds is refused rather than served.
## Returns {outcome, detail, tuning}.
static func resolve(tuning_version: String) -> Dictionary:
	if tuning_version != DEFAULT_TUNING_VERSION:
		return _fail(SchemaScript.OUTCOME_UNSUPPORTED_TUNING_VERSION, "unknown tuning_version: %s" % tuning_version)
	var bounds_check: String = _validate_default_tables()
	if bounds_check != SchemaScript.OUTCOME_OK:
		return _fail(bounds_check, "default tuning tables are out of bounds")
	var tuning := EmbodimentTuning.new(DEFAULT_TUNING_VERSION, _BUDGET, _FLOOR_PER_NODE, _GAIN_PER_EVIDENCE)
	return {"outcome": SchemaScript.OUTCOME_OK, "detail": "", "tuning": tuning}


## The floor this node may not be compressed below during redistribution.
func floor_for(node: String) -> float:
	return floor_per_node if SchemaScript.is_supported_node(node) else 0.0


## The opposition-weight row for a trained node: each of the other five nodes to
## the weight it is compressed by. The trained node is never in its own row.
func opposition_weights_for(node: String) -> Dictionary:
	var row: Dictionary = {}
	if not SchemaScript.is_supported_node(node):
		return row
	for other: String in SchemaScript.other_nodes(node):
		row[other] = _UNIFORM_WEIGHT
	return row


static func _validate_default_tables() -> String:
	var budget_check: String = SchemaScript.check_bounded(_BUDGET, SchemaScript.MIN_BUDGET, SchemaScript.MAX_BUDGET)
	if budget_check != SchemaScript.OUTCOME_OK:
		return budget_check
	var floor_check: String = SchemaScript.check_bounded(_FLOOR_PER_NODE, SchemaScript.MIN_FLOOR, _BUDGET)
	if floor_check != SchemaScript.OUTCOME_OK:
		return floor_check
	var gain_check: String = SchemaScript.check_bounded(_GAIN_PER_EVIDENCE, SchemaScript.MIN_GAIN, SchemaScript.MAX_GAIN)
	if gain_check != SchemaScript.OUTCOME_OK:
		return gain_check
	# The floors must fit inside the budget (all six floored must not exceed it).
	if _FLOOR_PER_NODE * float(SchemaScript.NODE_KEYS.size()) > _BUDGET:
		return SchemaScript.OUTCOME_OUT_OF_BOUNDS
	return SchemaScript.OUTCOME_OK


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "tuning": null}
