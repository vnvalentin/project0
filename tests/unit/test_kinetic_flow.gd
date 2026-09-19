extends GutTest
## Slice 136 (Phase 15, P-016-C): the Kinetic Flow derivation
## (shared/kinetic_flow.gd). Volume<-CON, Control<-DEX, Output<-STR; low Control
## relative to Volume inflates action energy cost. See
## docs/SYSTEMS-SPECIFICATION.md ("Kinetic Flow Layer").

const KineticFlowScript: Script = preload("res://shared/kinetic_flow.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _nodes(str_v: float, dex_v: float, con_v: float) -> Dictionary:
	return {"STR": str_v, "DEX": dex_v, "CON": con_v, "INT": 10.0, "WIS": 10.0, "CHA": 10.0}


func test_nodes_are_backed_by_their_vessel_attributes() -> void:
	var result: Dictionary = KineticFlowScript.derive(_nodes(12, 14, 18), _tuning())
	assert_almost_eq(float(result["volume"]), 18.0, 0.0001, "Volume is backed by CON")
	assert_almost_eq(float(result["control"]), 14.0, 0.0001, "Control is backed by DEX")
	assert_almost_eq(float(result["output"]), 12.0, 0.0001, "Output is driven by STR")


func test_balanced_flow_is_efficient() -> void:
	var result: Dictionary = KineticFlowScript.derive(_nodes(10, 10, 10), _tuning())
	assert_almost_eq(float(result["energy_cost_factor"]), 1.0, 0.0001, "matched Control and Volume slosh nothing")


func test_low_control_high_volume_sloshes_and_inflates_cost() -> void:
	# CON 20 -> Volume 20, DEX 5 -> Control 5: efficiency 0.25 -> cost 1 + 0.75.
	var result: Dictionary = KineticFlowScript.derive(_nodes(10, 5, 20), _tuning())
	assert_almost_eq(float(result["energy_cost_factor"]), 1.75, 0.0001, "sloshing energy inflates action cost")


func test_high_control_caps_efficiency_and_keeps_cost_baseline() -> void:
	# Control exceeding Volume cannot drop cost below baseline.
	var result: Dictionary = KineticFlowScript.derive(_nodes(10, 20, 10), _tuning())
	assert_almost_eq(float(result["energy_cost_factor"]), 1.0, 0.0001)


func test_zero_volume_does_not_divide_by_zero() -> void:
	var result: Dictionary = KineticFlowScript.derive(_nodes(10, 10, 0), _tuning())
	assert_almost_eq(float(result["volume"]), 0.0, 0.0001)
	assert_almost_eq(float(result["energy_cost_factor"]), 1.0, 0.0001, "no reservoir means no sloshing penalty")


func test_tuning_exposes_the_kinetic_namespace() -> void:
	var params: Dictionary = _tuning().kinetic()
	assert_almost_eq(float(params["volume_coefficient"]), 1.0, 0.0001)
	assert_almost_eq(float(params["slosh_penalty"]), 1.0, 0.0001)
