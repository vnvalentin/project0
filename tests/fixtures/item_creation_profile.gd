extends RefCounted
## Authored validation-only data. No runtime/default profile is registered.


static func authored() -> Dictionary:
	return {
		"schema_version": 1,
		"profile_id": "fixture:forge-creation", "profile_revision": "fixture:r1",
		"blueprint_id": "fixture:sword", "blueprint_revision": "fixture:b1",
		"tuning_version": "fixture:creation-v1", "arithmetic_version": 1,
		"inputs": {
			"material_purity": {"unit": "fixture_points", "minimum": 0, "maximum": 100},
			"catalyst_quality": {"unit": "fixture_points", "minimum": 0, "maximum": 100},
			"workstation_parameter": {"unit": "fixture_points", "minimum": 0, "maximum": 100},
		},
		"outputs": {
			"purity": {"unit": "fixture_points", "minimum": 0, "maximum": 100,
				"offset": 0, "divisor": 1, "weights": {
					"material_purity": 1, "catalyst_quality": 0, "workstation_parameter": 0}},
			"quality": {"unit": "fixture_points", "minimum": 0, "maximum": 100,
				"offset": 0, "divisor": 4, "weights": {
					"material_purity": 2, "catalyst_quality": 1, "workstation_parameter": 1}},
			"durability": {"unit": "fixture_points", "minimum": 0, "maximum": 1000,
				"offset": 10, "divisor": 2, "weights": {
					"material_purity": 3, "catalyst_quality": 2, "workstation_parameter": 1}},
		},
	}
