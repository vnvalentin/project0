extends GutTest
## Slice 134 (Phase 15, P-016-A): the derived, presentation-safe effective
## mechanics snapshot (shared/effective_mechanics_snapshot.gd). Derivation is
## pure/deterministic; only normalized graph proportions (never raw numbers)
## cross to the client. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const SnapshotScript: Script = preload("res://shared/effective_mechanics_snapshot.gd")
const VesselScript: Script = preload("res://shared/vessel_progression_state.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")
const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func test_derive_effective_equals_base_at_the_foundation() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	var snapshot: Object = SnapshotScript.derive(vessel, tuning)
	for key: String in SchemaScript.NODE_KEYS:
		assert_almost_eq(float(snapshot.effective_nodes[key]), 10.0, 0.0001, "%s effective equals earned base" % key)
	assert_eq(snapshot.derived.size(), 0, "no subsystem modifiers at the foundation")


func test_derive_stamps_the_current_tuning_version() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	var snapshot: Object = SnapshotScript.derive(vessel, tuning)
	assert_eq(snapshot.tuning_version, tuning.tuning_version, "the snapshot is stamped with the current tuning")


func test_derive_is_deterministic() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	vessel.train("STR", 6.0, tuning)
	var a: Dictionary = SnapshotScript.derive(vessel, tuning).to_presentation_snapshot()
	var b: Dictionary = SnapshotScript.derive(vessel, tuning).to_presentation_snapshot()
	assert_eq(a, b, "the same vessel + tuning derives an identical snapshot")


func test_presentation_snapshot_is_normalized_and_reflects_proportions() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	vessel.train("STR", 6.0, tuning)  # STR 16, others 8.8
	var presentation: Dictionary = SnapshotScript.derive(vessel, tuning).to_presentation_snapshot()
	var axes: Dictionary = presentation["graph_axes"]
	var total: float = 0.0
	for key: String in SchemaScript.NODE_KEYS:
		total += float(axes[key])
	assert_almost_eq(total, 1.0, 0.0001, "graph axes are normalized proportions")
	assert_almost_eq(float(axes["STR"]), 16.0 / 60.0, 0.0001, "STR's larger share is reflected")
	assert_true(float(axes["STR"]) > float(axes["DEX"]), "the trained node dominates the graph")


func test_presentation_snapshot_never_leaks_raw_numbers() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	var presentation: Dictionary = SnapshotScript.derive(vessel, tuning).to_presentation_snapshot()
	assert_false(presentation.has("effective_nodes"), "raw effective numbers never cross to the client")
	assert_false(presentation.has("base_nodes"), "raw base numbers never cross to the client")


func test_from_presentation_wire_accepts_a_valid_snapshot() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	var presentation: Dictionary = SnapshotScript.derive(vessel, tuning).to_presentation_snapshot()
	var result: Dictionary = SnapshotScript.from_presentation_wire(presentation)
	assert_eq(result["outcome"], "ok", "the server's own presentation snapshot round-trips")


func test_from_presentation_wire_rejects_unnormalized_axes() -> void:
	var wire: Dictionary = {
		"schema_version": 1, "tuning_version": "vessel-2026q4-baseline",
		"graph_axes": {"STR": 0.9, "DEX": 0.9, "CON": 0.9, "INT": 0.9, "WIS": 0.9, "CHA": 0.9},
		"derived": {},
	}
	assert_eq(SnapshotScript.from_presentation_wire(wire)["outcome"], "out_of_bounds")


func test_from_presentation_wire_rejects_bad_version_and_non_dictionary() -> void:
	assert_eq(SnapshotScript.from_presentation_wire("not a dict")["outcome"], "malformed")
	var bad: Dictionary = {
		"schema_version": 2, "tuning_version": "v",
		"graph_axes": {"STR": 1.0, "DEX": 0.0, "CON": 0.0, "INT": 0.0, "WIS": 0.0, "CHA": 0.0},
		"derived": {},
	}
	assert_eq(SnapshotScript.from_presentation_wire(bad)["outcome"], "unsupported_version")
