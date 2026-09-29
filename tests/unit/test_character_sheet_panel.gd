extends GutTest
## Experiment 1 for Epic #1294: Character Sheet presentation helpers.

const PanelScript: Script = preload("res://client/character_sheet_panel.gd")


func _snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"tuning_version": "vessel-2026q4-baseline",
		"stats": {
			"STR": 10.0, "DEX": 11.0, "CON": 12.0, "INT": 13.0, "WIS": 14.0, "CHA": 15.0,
			"KineticVolume": 12.0, "KineticControl": 11.0, "KineticOutput": 10.0,
			"BaseHP": 244.0, "BaseStamina": 215.0,
		},
	}


func test_groups_cover_all_eleven_fields() -> void:
	var fields: Array[String] = []
	for group: Dictionary in PanelScript.GROUPS:
		fields.append_array(group["fields"])
	assert_eq(fields.size(), 11)
	assert_eq(fields, ["STR", "DEX", "CON", "INT", "WIS", "CHA", "KineticVolume", "KineticControl", "KineticOutput", "BaseHP", "BaseStamina"])


func test_displayed_values_are_read_only_snapshot_values() -> void:
	var panel: Object = PanelScript.new()
	panel._snapshot = _snapshot()
	assert_eq(panel.displayed_value("STR"), "10.0")
	assert_eq(panel.displayed_value("BaseHP"), "244.0")
	assert_eq(panel.displayed_value("Unknown"), "—")
	assert_eq(panel.field_display_name("KineticControl"), "Kinetic Control")
	panel.free()


func test_rejected_or_empty_snapshot_has_no_invented_values() -> void:
	var panel: Object = PanelScript.new()
	panel._snapshot = {}
	assert_eq(panel.displayed_value("STR"), "—")
	panel.free()