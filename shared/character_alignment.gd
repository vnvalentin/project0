extends RefCounted
class_name CharacterAlignment
## Slice 117 (Phase 14): the Character alignment + disposition contract that
## drives how an AI Character relates to an observer (typically the player).
## Pure value + deterministic helpers, like the other shared contracts
## (shared/character_foundation.gd, shared/world_scale.gd): no scene tree, no
## network I/O, no authority, no secrets. See issue #228 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## Two continuous axes drive game logic: morality (-1 evil .. +1 good) and
## chaos (-1 lawful .. +1 chaotic). A D&D-style label is DERIVED for narration,
## but a `declared_label` may deliberately differ (a pretty knight that is
## secretly evil). disposition_toward() is deterministic: relationship history
## overrides alignment; strong alignment conflict turns unknowns hostile; and a
## Lawful Character is restrained from hostility while an authority is present.
## The stochastic "chaotic may attack anyway" chance and time-based relationship
## decay are separate later slices (see the Phase 14 map's non-goals).

const SCHEMA_VERSION: int = 1

const MORALITY_MIN: float = -1.0
const MORALITY_MAX: float = 1.0
const CHAOS_MIN: float = -1.0
const CHAOS_MAX: float = 1.0
const RELATIONSHIP_MIN: float = -100.0
const RELATIONSHIP_MAX: float = 100.0

## Label band edge: |axis| >= this reads as the pole; between reads Neutral.
const LABEL_BAND: float = 0.3

const DISPOSITION_HOSTILE: String = "hostile"
const DISPOSITION_NEUTRAL: String = "neutral"
const DISPOSITION_PASSIVE: String = "passive"
const SUPPORTED_DISPOSITIONS: PackedStringArray = ["hostile", "neutral", "passive"]

## Decision thresholds: relationship strong-override + alignment-conflict gate.
const RELATIONSHIP_TRUST: float = 50.0
const RELATIONSHIP_ENMITY: float = -50.0
const RELATIONSHIP_WARY_CEILING: float = 25.0
const ALIGNMENT_CONFLICT_THRESHOLD: float = 1.2
## A Character is "lawful" (authority-restrained) below this chaos value.
const LAWFUL_CHAOS_CEILING: float = -0.3

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_UNSUPPORTED_DISPOSITION: String = "unsupported_disposition"

var schema_version: int
var morality: float
var chaos: float
var declared_label: String
var default_disposition: String
var player_relationship: float


func _init(
	p_morality: float,
	p_chaos: float,
	p_default_disposition: String,
	p_player_relationship: float = 0.0,
	p_declared_label: String = ""
) -> void:
	schema_version = SCHEMA_VERSION
	morality = p_morality
	chaos = p_chaos
	default_disposition = p_default_disposition
	player_relationship = p_player_relationship
	declared_label = p_declared_label


## Deterministic D&D-style label from the two axes. Pure; used for narration.
static func derive_label(p_morality: float, p_chaos: float) -> String:
	var order: String = "Neutral"
	if p_chaos <= -LABEL_BAND:
		order = "Lawful"
	elif p_chaos >= LABEL_BAND:
		order = "Chaotic"
	var morals: String = "Neutral"
	if p_morality >= LABEL_BAND:
		morals = "Good"
	elif p_morality <= -LABEL_BAND:
		morals = "Evil"
	if order == "Neutral" and morals == "Neutral":
		return "True Neutral"
	return order + " " + morals


## The label an observer perceives: the declared one when set (deception),
## otherwise the true derived label.
func perceived_label() -> String:
	return declared_label if not declared_label.is_empty() else derive_label(morality, chaos)


## The true label from this Character's actual axes.
func true_label() -> String:
	return derive_label(morality, chaos)


## Whether a present authority restrains this Character from acting on hostility.
## True only for Lawful Characters; Chaotic/Neutral are not restrained here (the
## stochastic chaotic-attack chance is a later slice).
func respects_authority() -> bool:
	return _is_lawful()


## Deterministic disposition toward an observer with the given alignment, in the
## given context. Relationship history dominates; then alignment conflict; then
## a Lawful Character is restrained from hostility while an authority is present
## (`context.authority_present`).
func disposition_toward(observer_morality: float, observer_chaos: float, context: Dictionary) -> String:
	var base: String = _base_disposition(observer_morality, observer_chaos)
	if base == DISPOSITION_HOSTILE and _is_lawful() and bool(context.get("authority_present", false)):
		return DISPOSITION_PASSIVE
	return base


func _base_disposition(observer_morality: float, observer_chaos: float) -> String:
	if player_relationship >= RELATIONSHIP_TRUST:
		return DISPOSITION_PASSIVE
	if player_relationship <= RELATIONSHIP_ENMITY:
		return DISPOSITION_HOSTILE
	var conflict: float = absf(morality - observer_morality) + absf(chaos - observer_chaos)
	if conflict > ALIGNMENT_CONFLICT_THRESHOLD and player_relationship < RELATIONSHIP_WARY_CEILING:
		return DISPOSITION_HOSTILE
	return default_disposition


func _is_lawful() -> bool:
	return chaos < LAWFUL_CHAOS_CEILING


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, axis/relationship bounds, and the disposition enum.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var morality_res: Dictionary = _validate_axis(data.get("morality"), MORALITY_MIN, MORALITY_MAX, "morality")
	if morality_res["outcome"] != OUTCOME_OK:
		return morality_res
	var chaos_res: Dictionary = _validate_axis(data.get("chaos"), CHAOS_MIN, CHAOS_MAX, "chaos")
	if chaos_res["outcome"] != OUTCOME_OK:
		return chaos_res
	var rel_res: Dictionary = _validate_axis(
		data.get("player_relationship", 0.0), RELATIONSHIP_MIN, RELATIONSHIP_MAX, "player_relationship"
	)
	if rel_res["outcome"] != OUTCOME_OK:
		return rel_res
	var disposition: Variant = data.get("default_disposition")
	if not (disposition is String) or not SUPPORTED_DISPOSITIONS.has(disposition):
		return _fail(OUTCOME_UNSUPPORTED_DISPOSITION, "unknown default_disposition")
	var declared: Variant = data.get("declared_label", "")
	if not (declared is String):
		return _fail(OUTCOME_MALFORMED, "declared_label must be a string")
	var alignment := CharacterAlignment.new(
		morality_res["value"], chaos_res["value"], String(disposition), rel_res["value"], String(declared)
	)
	return {"outcome": OUTCOME_OK, "detail": "", "alignment": alignment}


static func _validate_axis(value: Variant, min_v: float, max_v: float, axis_name: String) -> Dictionary:
	if not (value is float or value is int):
		return _fail(OUTCOME_MALFORMED, axis_name + " is not numeric")
	var num: float = float(value)
	if not is_finite(num):
		return _fail(OUTCOME_OUT_OF_BOUNDS, axis_name + " is not finite")
	if num < min_v or num > max_v:
		return _fail(OUTCOME_OUT_OF_BOUNDS, axis_name + " out of bounds")
	return {"outcome": OUTCOME_OK, "detail": "", "value": num}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "alignment": null}
