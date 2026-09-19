extends RefCounted
class_name MeridianState
## Slice 137 (Phase 15, P-016-D): a Meridian pathway a Character can permanently
## burn open through repeated, server-observed cross-training between two vessel
## nodes. Progress is driven by DEDUPLICATED cross-training evidence, never raw
## client counters: replaying the same evidence id can neither increment progress
## nor emit a second unlock (deterministic + idempotent). Unlocks are DURABLE;
## activation costs, effects, and temporary status are runtime state elsewhere.
## Pure value + deterministic transitions — the server owns the live state. See
## docs/SYSTEMS-SPECIFICATION.md ("Meridian Pathways") and
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")

const SCHEMA_VERSION: int = 1

const PATHWAY_IMPACT: String = "impact"
const PATHWAY_FLOW: String = "flow"
const PATHWAY_SPARK: String = "spark"
const SUPPORTED_PATHWAYS: PackedStringArray = ["impact", "flow", "spark"]

## The two vessel nodes each pathway channels between.
const PATHWAY_NODES: Dictionary = {
	"impact": ["STR", "CON"],
	"flow": ["DEX", "WIS"],
	"spark": ["STR", "DEX"],
}

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_PATHWAY: String = "unsupported_pathway"
const OUTCOME_DUPLICATE_EVIDENCE: String = "duplicate_evidence"

var schema_version: int
var pathway: String
var progress: float
var unlocked: bool
## Consumed cross-training evidence ids, for deduplication.
var _consumed: Dictionary


func _init(p_pathway: String) -> void:
	schema_version = SCHEMA_VERSION
	pathway = p_pathway
	progress = 0.0
	unlocked = false
	_consumed = {}


## The two vessel nodes this pathway channels between.
static func nodes_for(p_pathway: String) -> Array:
	return PATHWAY_NODES.get(p_pathway, [])


## Record a unit of deduplicated cross-training evidence. Idempotent: a
## previously-seen evidence id is a no-op (no progress, no second unlock). On a
## fresh id, progress accumulates and the pathway unlocks once it reaches the
## tuning threshold. Returns {outcome, progressed, newly_unlocked}.
func record_evidence(evidence_id: String, amount: float, tuning: Object) -> Dictionary:
	if not SUPPORTED_PATHWAYS.has(pathway):
		return {"outcome": OUTCOME_UNSUPPORTED_PATHWAY, "progressed": false, "newly_unlocked": false}
	if evidence_id.is_empty() or not is_finite(amount) or amount <= 0.0:
		return {"outcome": OUTCOME_MALFORMED, "progressed": false, "newly_unlocked": false}
	if _consumed.has(evidence_id):
		# Deterministic idempotency: replay cannot progress or re-unlock.
		return {"outcome": OUTCOME_DUPLICATE_EVIDENCE, "progressed": false, "newly_unlocked": false}
	_consumed[evidence_id] = true
	progress += amount
	var newly_unlocked: bool = false
	if not unlocked and progress >= float(tuning.meridian()["unlock_threshold"]):
		unlocked = true
		newly_unlocked = true
	return {"outcome": OUTCOME_OK, "progressed": true, "newly_unlocked": newly_unlocked}


func is_unlocked() -> bool:
	return unlocked
