extends RefCounted
class_name EffectiveMechanicsSnapshot
## Slice 134 (Phase 15, P-016-A): the derived, replicated read-model of a
## Character's runtime mechanics. Pure value + deterministic derivation: the
## server derives it from the durable vessel (base_nodes) using the CURRENT
## tuning, and replicates only a PRESENTATION-SAFE view (normalized graph
## proportions + subsystem-safe summaries, never raw stat numbers) to the client
## — the same boundary CharacterFoundation established. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md and issue #224.
##
## Per ADR 0006: earned `base_nodes` are pinned to their build tuning, but the
## EFFECTIVE derivation (runtime power) uses the CURRENT tuning — so balance
## changes flow through this snapshot transparently and universally, never as a
## retroactive edit of saved progression. This foundation snapshot carries the
## effective nodes with no subsystem modifiers yet; friction, kinetic, meridian,
## burnout, and magic layers (P-016-B…F) populate the `derived` map on top.

const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")

const SCHEMA_VERSION: int = 1

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"

var schema_version: int
## The tuning used to DERIVE this snapshot (current tuning, stamped for
## provenance) — not necessarily the vessel's pinned build tuning.
var tuning_version: String
## Server-side raw effective node values (base + subsystem modifiers). Never
## replicated raw; only the normalized presentation graph crosses to the client.
var effective_nodes: Dictionary
## Subsystem-derived outputs (friction/kinetic/meridian/burnout/magic). Empty in
## this foundation snapshot; later layers populate it.
var derived: Dictionary


func _init(p_tuning_version: String, p_effective_nodes: Dictionary, p_derived: Dictionary) -> void:
	schema_version = SCHEMA_VERSION
	tuning_version = p_tuning_version
	effective_nodes = p_effective_nodes
	derived = p_derived


## Pure, deterministic derivation from a durable vessel under the current tuning.
## Foundation: effective nodes equal the earned base (no subsystem modifiers yet).
## Stamps the CURRENT tuning's version for provenance.
static func derive(vessel: Object, current_tuning: Object) -> EffectiveMechanicsSnapshot:
	var effective: Dictionary = {}
	for key: String in SchemaScript.NODE_KEYS:
		effective[key] = float(vessel.base_nodes.get(key, 0.0))
	return EffectiveMechanicsSnapshot.new(String(current_tuning.tuning_version), effective, {})


## The presentation-safe snapshot replicated to the client: normalized graph
## proportions (each axis's share of the effective total, summing to 1.0) + the
## tuning provenance + subsystem-safe summaries — never the raw effective numbers.
func to_presentation_snapshot() -> Dictionary:
	var total: float = SchemaScript.sum_over_nodes(effective_nodes)
	var axes: Dictionary = {}
	for key: String in SchemaScript.NODE_KEYS:
		axes[key] = (float(effective_nodes[key]) / total) if total > 0.0 else 0.0
	return {
		"schema_version": schema_version,
		"tuning_version": tuning_version,
		"graph_axes": axes,
		"derived": derived.duplicate(),
	}


## Parse + validate an untrusted presentation snapshot on the client, fail-closed
## on version, structure, and the normalized-axis bounds. Returns
## {outcome, detail, snapshot} where snapshot is the validated presentation
## Dictionary (the client renders graph_axes; it never receives raw numbers).
static func from_presentation_wire(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var version: Variant = data.get("tuning_version")
	if not (version is String) or String(version).is_empty():
		return _fail(OUTCOME_MALFORMED, "tuning_version must be a non-empty string")
	var raw_axes: Variant = data.get("graph_axes")
	if not (raw_axes is Dictionary):
		return _fail(OUTCOME_MALFORMED, "graph_axes is not a Dictionary")
	var axes: Dictionary = raw_axes
	if axes.size() != SchemaScript.NODE_KEYS.size():
		return _fail(OUTCOME_MALFORMED, "graph_axes must have exactly six axes")
	var total: float = 0.0
	for key: String in SchemaScript.NODE_KEYS:
		if not axes.has(key):
			return _fail(OUTCOME_MALFORMED, "missing axis: %s" % key)
		var value: Variant = axes[key]
		if not (value is float or value is int):
			return _fail(OUTCOME_MALFORMED, "axis value is not numeric: %s" % key)
		var num: float = float(value)
		if SchemaScript.check_bounded(num, 0.0, 1.0) != SchemaScript.OUTCOME_OK:
			return _fail(OUTCOME_OUT_OF_BOUNDS, "axis proportion out of 0..1: %s" % key)
		total += num
	if total > 0.0 and absf(total - 1.0) > 0.001:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "graph_axes must be normalized to sum 1.0")
	return {"outcome": OUTCOME_OK, "detail": "", "snapshot": data}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "snapshot": null}
