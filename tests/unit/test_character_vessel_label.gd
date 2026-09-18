extends GutTest
## Slice 127: the pure presentation summary of a Character snapshot used by the
## HUD vessel label (client/character_vessel_label.gd). Tests the static helpers
## directly, without the NetworkClient autoload or a Label node. See
## docs/slices/127-phase14-character-foundation-server.md.

const VesselLabelScript: Script = preload("res://client/character_vessel_label.gd")


func _balanced_axes() -> Dictionary:
	var axes: Dictionary = {}
	for key in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
		axes[key] = 1.0 / 6.0
	return axes


func test_dominant_axis_is_balanced_for_the_equal_baseline() -> void:
	assert_eq(VesselLabelScript.dominant_axis(_balanced_axes()), "balanced")


func test_dominant_axis_reports_the_peak_when_skewed() -> void:
	var axes: Dictionary = {"STR": 0.4, "DEX": 0.1, "CON": 0.1, "INT": 0.15, "WIS": 0.15, "CHA": 0.1}
	assert_eq(VesselLabelScript.dominant_axis(axes), "STR", "the strongest axis is named")


func test_dominant_axis_handles_no_axes() -> void:
	assert_eq(VesselLabelScript.dominant_axis({}), "—")


func test_summarize_renders_kind_and_axis() -> void:
	var snapshot: Dictionary = {
		"schema_version": 1,
		"controller_type": "PLAYER",
		"character_kind": "humanoid",
		"graph_axes": _balanced_axes(),
	}
	assert_eq(VesselLabelScript.summarize(snapshot), "Vessel: humanoid (balanced)")


func test_summarize_handles_an_empty_snapshot() -> void:
	assert_eq(VesselLabelScript.summarize({}), "Vessel: —")
