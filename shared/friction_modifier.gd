extends RefCounted
class_name FrictionModifier
## Slice 135 (Phase 15, P-016-B): inverse biological friction. A vessel pushed
## hard toward one physical extreme pays a derived friction cost — Massive Bulk
## (high STR + high CON) or Fragile Agility (high DEX + low CON). Pure,
## deterministic derivation from the effective nodes under the current friction
## tuning; the server folds the result into the EffectiveMechanicsSnapshot's
## `derived` map and the client renders the replicated result, never selecting
## the winning curve itself. See docs/SYSTEMS-SPECIFICATION.md ("Inverse
## Biological Friction") and docs/adr/0006-versioned-embodiment-mechanics-architecture.md.
##
## Note: the spec phrases Fragile Agility as "High DEX And High MET (Metabolism)";
## the six-node vessel has no MET node, so this contract reads it as high DEX with
## SHED STRUCTURAL MASS (low CON), matching the spec's "sheds structural mass for
## reflex velocity". Trigger thresholds and factors are frozen tuning.

const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")

const PROFILE_NONE: String = "none"
const PROFILE_MASSIVE_BULK: String = "massive_bulk"
const PROFILE_FRAGILE_AGILITY: String = "fragile_agility"

const WATER_FLOAT: String = "float"
const WATER_SINK: String = "sink"
const WATER_SKIP_THEN_SINK: String = "skip_then_sink"


## Derive the friction profile + modifier factors for the given effective nodes.
## Deterministic; Massive Bulk takes precedence if both somehow qualify (they are
## mutually exclusive by CON, but the order is documented). Returns a fixed-shape
## Dictionary the snapshot's `derived["friction"]` carries.
static func derive(effective_nodes: Dictionary, tuning: Object) -> Dictionary:
	var params: Dictionary = tuning.friction()
	var str_value: float = float(effective_nodes.get("STR", 0.0))
	var dex_value: float = float(effective_nodes.get("DEX", 0.0))
	var con_value: float = float(effective_nodes.get("CON", 0.0))

	var is_bulk: bool = str_value >= float(params["massive_bulk_threshold"]) and con_value >= float(params["massive_bulk_threshold"])
	var is_fragile: bool = dex_value >= float(params["fragile_dex_threshold"]) and con_value <= float(params["fragile_con_ceiling"])

	if is_bulk:
		return _modifiers(
			PROFILE_MASSIVE_BULK,
			float(params["bulk_dodge_factor"]),
			float(params["bulk_windup_recovery_factor"]),
			1.0,
			1.0,
			WATER_SINK
		)
	if is_fragile:
		return _modifiers(
			PROFILE_FRAGILE_AGILITY,
			1.0,
			1.0,
			float(params["fragile_stamina_regen_factor"]),
			float(params["fragile_stagger_resistance_factor"]),
			WATER_SKIP_THEN_SINK
		)
	return _modifiers(PROFILE_NONE, 1.0, 1.0, 1.0, 1.0, WATER_FLOAT)


static func _modifiers(
	profile: String,
	dodge_distance_factor: float,
	windup_recovery_factor: float,
	stamina_regen_factor: float,
	stagger_resistance_factor: float,
	water_behavior: String
) -> Dictionary:
	return {
		"profile": profile,
		"dodge_distance_factor": dodge_distance_factor,
		"windup_recovery_factor": windup_recovery_factor,
		"stamina_regen_factor": stamina_regen_factor,
		"stagger_resistance_factor": stagger_resistance_factor,
		"water_behavior": water_behavior,
	}
