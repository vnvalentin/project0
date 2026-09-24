extends RefCounted
class_name SectorIdentity

const LEGACY_STARTING_TOWN_ID: String = "starting_town_hub"


static func parse(sector_id: String) -> Dictionary:
	if sector_id == LEGACY_STARTING_TOWN_ID:
		return {"outcome": "valid", "coordinate": Vector2i.ZERO}
	var expression: RegEx = RegEx.new()
	if expression.compile("^sector-(-?[0-9]+)-(-?[0-9]+)$") != OK:
		return {"outcome": "invalid"}
	var match_result: RegExMatch = expression.search(sector_id)
	if match_result == null:
		return {"outcome": "invalid"}
	return {
		"outcome": "valid",
		"coordinate": Vector2i(int(match_result.get_string(1)), int(match_result.get_string(2))),
	}