extends GutTest
## Slice 142 (Phase 15 follow-on): the local Player's presentation-safe
## effective-mechanics HUD label (client/effective_mechanics_label.gd). Tests the
## static summary helpers directly, without the NetworkClient autoload or a Label
## node, mirroring test_character_vessel_label.gd. The label only renders derived,
## presentation-safe state the server replicated. See
## docs/slices/142-effective-mechanics-replication.md.

const MechanicsLabelScript: Script = preload("res://client/effective_mechanics_label.gd")


func test_empty_snapshot_summarizes_as_placeholder() -> void:
	assert_eq(MechanicsLabelScript.summarize({}), "Mechanics: —", "no snapshot shows the placeholder")


func test_balanced_baseline_summarizes_profile_and_balanced_axis() -> void:
	var snapshot: Dictionary = {
		"tuning_version": "vessel-2026q4-baseline",
		"graph_axes": {"STR": 1.0 / 6.0, "DEX": 1.0 / 6.0, "CON": 1.0 / 6.0, "INT": 1.0 / 6.0, "WIS": 1.0 / 6.0, "CHA": 1.0 / 6.0},
		"derived": {"friction_profile": "neutral"},
	}
	assert_eq(MechanicsLabelScript.summarize(snapshot), "Mechanics: neutral (balanced)", "balanced axes render as balanced")


func test_dominant_axis_is_named_when_unbalanced() -> void:
	var snapshot: Dictionary = {
		"graph_axes": {"STR": 0.5, "DEX": 0.1, "CON": 0.1, "INT": 0.1, "WIS": 0.1, "CHA": 0.1},
		"derived": {"friction_profile": "massive_bulk"},
	}
	assert_eq(MechanicsLabelScript.summarize(snapshot), "Mechanics: massive_bulk (STR)", "the dominant axis is named")


func test_missing_friction_profile_falls_back_to_placeholder() -> void:
	var snapshot: Dictionary = {"graph_axes": {"STR": 0.7, "DEX": 0.3}, "derived": {}}
	assert_eq(MechanicsLabelScript.summarize(snapshot), "Mechanics: — (STR)", "absent profile shows the placeholder")


func test_dominant_axis_helper_handles_no_axes() -> void:
	assert_eq(MechanicsLabelScript.dominant_axis({}), "—", "no axes render as the placeholder")
