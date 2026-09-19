extends RefCounted
class_name EmbodimentProgressionService
## Slice 140 (Phase 15, P-016-A/G): the server-authoritative embodiment
## progression service. It owns the durable vessels, Meridian states, and active
## Burnouts, accepts server-validated (deduplicated) training/cross-training
## evidence, and composes the vessel + all five subsystems (friction, kinetic,
## meridian, burnout, magic) into one presentation-safe EffectiveMechanicsSnapshot
## the client can render. Hidden numeric state stays server-side; only derived,
## presentation-safe results replicate. This closes the Phase 15 exit gate by
## layering every subsystem onto the P-016-A read-model under server authority.
## See docs/adr/0006-versioned-embodiment-mechanics-architecture.md and
## docs/SYSTEMS-SPECIFICATION.md.

const VesselScript: Script = preload("res://shared/vessel_progression_state.gd")
const SnapshotScript: Script = preload("res://shared/effective_mechanics_snapshot.gd")
const FrictionScript: Script = preload("res://shared/friction_modifier.gd")
const KineticScript: Script = preload("res://shared/kinetic_flow.gd")
const MeridianScript: Script = preload("res://shared/meridian_state.gd")
const BurnoutScript: Script = preload("res://shared/burnout_instance.gd")
const MagicScript: Script = preload("res://shared/magic_equilibrium.gd")

const OUTCOME_OK: String = "ok"
const OUTCOME_UNKNOWN_CHARACTER: String = "unknown_character"
const OUTCOME_DUPLICATE_EVIDENCE: String = "duplicate_evidence"

var _vessels: Dictionary = {}
var _meridians: Dictionary = {}
var _burnouts: Dictionary = {}
## Deduplicated training-evidence ids per character (trusted progression evidence).
var _consumed_training: Dictionary = {}


## Register a fresh Character with a baseline vessel pinned to the given tuning.
func create_character(character_id: String, tuning: Object) -> void:
	_vessels[character_id] = VesselScript.create_baseline(tuning)
	_meridians[character_id] = {}
	_burnouts[character_id] = []
	_consumed_training[character_id] = {}


func has_character(character_id: String) -> bool:
	return _vessels.has(character_id)


## Accept a server-validated, deduplicated unit of training evidence and apply the
## vessel gain. A replayed evidence id is a no-op. Returns {outcome, detail}.
func accept_training(character_id: String, node: String, evidence_id: String, amount: float, tuning: Object) -> Dictionary:
	if not _vessels.has(character_id):
		return {"outcome": OUTCOME_UNKNOWN_CHARACTER, "detail": "no such character"}
	var consumed: Dictionary = _consumed_training[character_id]
	if evidence_id.is_empty() or consumed.has(evidence_id):
		return {"outcome": OUTCOME_DUPLICATE_EVIDENCE, "detail": "evidence already consumed or empty id"}
	var result: Dictionary = (_vessels[character_id] as Object).train(node, amount, tuning)
	if result["outcome"] == VesselScript.OUTCOME_OK:
		consumed[evidence_id] = true
	return result


## Record deduplicated Meridian cross-training evidence for a pathway.
func record_meridian_evidence(character_id: String, pathway: String, evidence_id: String, amount: float, tuning: Object) -> Dictionary:
	if not _vessels.has(character_id):
		return {"outcome": OUTCOME_UNKNOWN_CHARACTER, "progressed": false, "newly_unlocked": false}
	var pathways: Dictionary = _meridians[character_id]
	if not pathways.has(pathway):
		pathways[pathway] = MeridianScript.new(pathway)
	return (pathways[pathway] as Object).record_evidence(evidence_id, amount, tuning)


## Begin a Burnout from an accepted Overload Surge. Returns the from_accepted_surge
## outcome; on success the instance is tracked for snapshot derivation.
func begin_burnout(character_id: String, burnout_id: String, pathway: String, source_action_id: String, start_tick: int, tuning: Object) -> Dictionary:
	if not _vessels.has(character_id):
		return {"outcome": OUTCOME_UNKNOWN_CHARACTER, "detail": "no such character", "burnout": null}
	var result: Dictionary = BurnoutScript.from_accepted_surge(burnout_id, pathway, source_action_id, start_tick, tuning)
	if result["outcome"] == BurnoutScript.OUTCOME_OK:
		(_burnouts[character_id] as Array).append(result["burnout"])
	return result


## Resolve a magic attempt from the Character's current effective vessel.
func resolve_magic(character_id: String, spell_tier: int, tuning: Object) -> Dictionary:
	if not _vessels.has(character_id):
		return {"outcome": MagicScript.OUTCOME_REJECTED, "reason": "unknown_character"}
	return MagicScript.resolve((_vessels[character_id] as Object).base_nodes, spell_tier, tuning)


## Compose the vessel + all five subsystems into one EffectiveMechanicsSnapshot.
## The `derived` map carries presentation-safe subsystem RESULTS (profile, factors,
## unlock flags, active-burnout pathways) — never raw stat magnitudes. Pure and
## deterministic given the same state, tuning, and tick.
func effective_snapshot(character_id: String, tuning: Object, current_tick: int) -> Object:
	if not _vessels.has(character_id):
		return null
	var vessel: Object = _vessels[character_id]
	var base_snapshot: Object = SnapshotScript.derive(vessel, tuning)
	var effective_nodes: Dictionary = base_snapshot.effective_nodes
	var friction: Dictionary = FrictionScript.derive(effective_nodes, tuning)
	var kinetic: Dictionary = KineticScript.derive(effective_nodes, tuning)
	var active_burnout_pathways: Array = []
	for burnout: Variant in (_burnouts[character_id] as Array):
		if (burnout as Object).is_active(current_tick):
			active_burnout_pathways.append((burnout as Object).pathway)
	var meridian_unlocks: Dictionary = {}
	for pathway: String in (_meridians[character_id] as Dictionary):
		meridian_unlocks[pathway] = (_meridians[character_id][pathway] as Object).is_unlocked()
	var derived: Dictionary = {
		"friction_profile": friction["profile"],
		"kinetic_energy_cost_factor": kinetic["energy_cost_factor"],
		"meridian_unlocks": meridian_unlocks,
		"burnout_active_pathways": active_burnout_pathways,
	}
	return SnapshotScript.new(String(tuning.tuning_version), effective_nodes, derived)
