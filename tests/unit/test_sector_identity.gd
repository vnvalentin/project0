extends GutTest

const SectorIdentityScript: Script = preload("res://shared/sector_identity.gd")


func test_signed_sector_identity_parses_to_grid_coordinate() -> void:
	assert_eq(SectorIdentityScript.parse("sector-1--2"), {
		"outcome": "valid",
		"coordinate": Vector2i(1, -2),
	})


func test_starting_town_identity_maps_to_legacy_origin() -> void:
	assert_eq(SectorIdentityScript.parse("starting_town_hub"), {
		"outcome": "valid",
		"coordinate": Vector2i.ZERO,
	})


func test_malformed_sector_identity_fails_closed() -> void:
	assert_eq(SectorIdentityScript.parse("sector-east-0"), {"outcome": "invalid"})