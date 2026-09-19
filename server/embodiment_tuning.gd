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

## Friction namespace (Slice 135, P-016-B): inverse-friction profile thresholds
## and modifier factors. Massive Bulk (high STR + high CON) and Fragile Agility
## (high DEX + low CON) are derived from the effective nodes. Values are frozen
## tuning; the qualitative effects come from docs/SYSTEMS-SPECIFICATION.md.
const _MASSIVE_BULK_THRESHOLD: float = 16.0
const _FRAGILE_DEX_THRESHOLD: float = 16.0
const _FRAGILE_CON_CEILING: float = 6.0
const _BULK_DODGE_FACTOR: float = 0.5
const _BULK_WINDUP_RECOVERY_FACTOR: float = 1.5
const _FRAGILE_STAMINA_REGEN_FACTOR: float = 3.0
const _FRAGILE_STAGGER_RESISTANCE_FACTOR: float = 0.0

## Kinetic namespace (Slice 136, P-016-C): the three Kinetic Flow nodes are
## derived from their backing vessel nodes (Volume<-CON, Control<-DEX,
## Output<-STR); low Control relative to Volume makes energy slosh and inflates
## action energy cost. Coefficients + slosh penalty are frozen tuning; the
## qualitative behaviour comes from docs/SYSTEMS-SPECIFICATION.md.
const _KINETIC_VOLUME_COEFFICIENT: float = 1.0
const _KINETIC_CONTROL_COEFFICIENT: float = 1.0
const _KINETIC_OUTPUT_COEFFICIENT: float = 1.0
const _KINETIC_SLOSH_PENALTY: float = 1.0

## Meridian namespace (Slice 137, P-016-D): the deduplicated cross-training
## evidence a pathway must accumulate before it permanently unlocks. One frozen
## threshold for the baseline set; per-pathway thresholds are a later revision.
const _MERIDIAN_UNLOCK_THRESHOLD: float = 100.0

## Burnout namespace (Slice 138, P-016-E): how many authoritative ticks a pathway
## stays burned out after an accepted Overload Surge, during which its effective
## Control/DEX are flattened. Frozen tuning; expiry is on the server clock.
const _BURNOUT_DURATION_TICKS: int = 180

## Magic namespace (Slice 139, P-016-F): physical bulk (STR + CON) acts as an
## electrical insulator that grounds magical currents; higher spell tiers demand
## a leaner vessel. Insulation at/under a tier's ceiling channels; within the
## fizzle margin above it fizzles; beyond that it backlashes. Frozen tuning.
const _MAGIC_INSULATION_COEFFICIENT: float = 1.0
const _MAGIC_BASE_CHANNEL_CEILING: float = 40.0
const _MAGIC_CEILING_STEP_PER_TIER: float = 8.0
const _MAGIC_FIZZLE_MARGIN: float = 12.0
const _MAGIC_MAX_TIER: int = 5

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


## The friction subsystem's frozen tuning: profile thresholds and the modifier
## factors each profile applies (P-016-B).
func friction() -> Dictionary:
	return {
		"massive_bulk_threshold": _MASSIVE_BULK_THRESHOLD,
		"fragile_dex_threshold": _FRAGILE_DEX_THRESHOLD,
		"fragile_con_ceiling": _FRAGILE_CON_CEILING,
		"bulk_dodge_factor": _BULK_DODGE_FACTOR,
		"bulk_windup_recovery_factor": _BULK_WINDUP_RECOVERY_FACTOR,
		"fragile_stamina_regen_factor": _FRAGILE_STAMINA_REGEN_FACTOR,
		"fragile_stagger_resistance_factor": _FRAGILE_STAGGER_RESISTANCE_FACTOR,
	}


## The Kinetic Flow subsystem's frozen tuning: node coefficients + slosh penalty
## (P-016-C).
func kinetic() -> Dictionary:
	return {
		"volume_coefficient": _KINETIC_VOLUME_COEFFICIENT,
		"control_coefficient": _KINETIC_CONTROL_COEFFICIENT,
		"output_coefficient": _KINETIC_OUTPUT_COEFFICIENT,
		"slosh_penalty": _KINETIC_SLOSH_PENALTY,
	}


## The Meridian subsystem's frozen tuning: the deduplicated cross-training
## evidence threshold a pathway unlocks at (P-016-D).
func meridian() -> Dictionary:
	return {
		"unlock_threshold": _MERIDIAN_UNLOCK_THRESHOLD,
	}


## The Burnout subsystem's frozen tuning: the cooldown duration in ticks
## (P-016-E).
func burnout() -> Dictionary:
	return {
		"duration_ticks": _BURNOUT_DURATION_TICKS,
	}


## The Magic-equilibrium subsystem's frozen tuning: insulation coefficient, the
## per-tier channel ceiling, the fizzle margin, and the max tier (P-016-F).
func magic() -> Dictionary:
	return {
		"insulation_coefficient": _MAGIC_INSULATION_COEFFICIENT,
		"base_channel_ceiling": _MAGIC_BASE_CHANNEL_CEILING,
		"ceiling_step_per_tier": _MAGIC_CEILING_STEP_PER_TIER,
		"fizzle_margin": _MAGIC_FIZZLE_MARGIN,
		"max_tier": _MAGIC_MAX_TIER,
	}


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
