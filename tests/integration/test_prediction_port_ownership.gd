extends GutTest

const FIXTURE_PATH: String = "res://tests/fixtures/prediction_port_ownership.gd"
const FIXTURE_LABEL: String = "1447 port ownership diagnostic fixture exists before native qualification"


func test_probe_release_gap_and_bound_port_ownership() -> void:
	var fixture_exists: bool = FileAccess.file_exists(FIXTURE_PATH)
	assert_true(fixture_exists, FIXTURE_LABEL)
	if not fixture_exists:
		return
