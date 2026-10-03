extends GutTest

const FIXTURE_PATH: String = "res://tests/fixtures/persistence_thread_affinity_fixture.gd"


func test_direct_sqlite_worker_lifecycle_has_complete_fixture_coverage() -> void:
	# Initial RED tracer only. Root qualifies the absent fixture before implementation.
	var fixture_exists: bool = FileAccess.file_exists(FIXTURE_PATH)
	assert_true(fixture_exists, "1444 affinity experiment fixture exists before lifecycle qualification")
	if not fixture_exists:
		return
