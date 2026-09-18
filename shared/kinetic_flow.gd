extends RefCounted
class_name KineticFlow
## Slice 136 (Phase 15, P-016-C): the Kinetic Flow layer. Three derived kinetic
## nodes come from the effective vessel: Volume (reservoir, backed by CON),
## Control (surgical efficiency, backed by DEX), and Output (explosive venting,
## driven by STR). When Control is low relative to Volume, energy sloshes
## inefficiently and inflates authoritative action energy costs. Pure,
## deterministic derivation from the effective nodes under the current kinetic
## tuning; the server folds the result into the snapshot's `derived` map and
## owns every kinetic action outcome. See docs/SYSTEMS-SPECIFICATION.md
## ("Kinetic Flow Layer") and docs/adr/0006-versioned-embodiment-mechanics-architecture.md.


## Derive Volume/Control/Output and the energy-cost inflation from effective
## nodes. Returns a fixed-shape Dictionary the snapshot's `derived["kinetic"]`
## carries. `energy_cost_factor` is 1.0 when Control matches or exceeds Volume,
## and rises toward 1 + slosh_penalty as Control falls to zero relative to Volume.
static func derive(effective_nodes: Dictionary, tuning: Object) -> Dictionary:
	var params: Dictionary = tuning.kinetic()
	var volume: float = maxf(0.0, float(effective_nodes.get("CON", 0.0))) * float(params["volume_coefficient"])
	var control: float = maxf(0.0, float(effective_nodes.get("DEX", 0.0))) * float(params["control_coefficient"])
	var output: float = maxf(0.0, float(effective_nodes.get("STR", 0.0))) * float(params["output_coefficient"])
	var efficiency: float = clampf(control / volume, 0.0, 1.0) if volume > 0.0 else 1.0
	var energy_cost_factor: float = 1.0 + (1.0 - efficiency) * float(params["slosh_penalty"])
	return {
		"volume": volume,
		"control": control,
		"output": output,
		"energy_cost_factor": energy_cost_factor,
	}
