extends GutTest

const FIXTURE_PATH: String = "res://tests/fixtures/prediction_port_ownership.gd"
const FIXTURE_LABEL: String = "1447 port ownership diagnostic fixture exists before native qualification"


func test_probe_release_gap_and_bound_port_ownership() -> void:
	var fixture_exists: bool = FileAccess.file_exists(FIXTURE_PATH)
	assert_true(fixture_exists, FIXTURE_LABEL)
	if not fixture_exists:
		return
	var fixture_script: GDScript = load(FIXTURE_PATH) as GDScript
	assert_not_null(fixture_script, "1447 fixed diagnostic fixture loads")
	if fixture_script == null:
		return
	var fixture: RefCounted = fixture_script.new()
	assert_true(fixture.has_method("run"), "1447 fixed diagnostic public run seam exists")
	if not fixture.has_method("run"):
		return
	var raw_result: Variant = fixture.call("run")
	assert_eq(typeof(raw_result), TYPE_DICTIONARY, "1447 diagnostic result is a Dictionary")
	if typeof(raw_result) != TYPE_DICTIONARY:
		return
	var result: Dictionary = raw_result
	var schema_valid: bool = _closed_result(result)
	assert_true(schema_valid, "1447 diagnostic result has exact typed closed schema")
	if not schema_valid:
		return
	print("1447_PORT_REPORT:" + JSON.stringify(result))
	for field: String in BOOLEAN_FIELDS:
		assert_true(result[field] == true, "1447 diagnostic observation " + field)
	assert_eq(result["failure_code"], "none", "1447 fixed sequence and release controls complete")
	assert_eq(result["takeover_result"], "ERR_CANT_CREATE", "1447 held takeover rejects fresh ENet bind")
	assert_eq(result["duplicate_result"], "ERR_CANT_CREATE", "1447 held actual listener rejects duplicate bind")
	assert_eq(result["historical_cause"], "UNKNOWN", "1447 diagnostic preserves historical-cause limit")
	assert_eq(result["production_countermeasure"], "NOT_OBSERVED", "1447 diagnostic grants no production adoption")


const BOOLEAN_FIELDS: Array[String] = [
	"passed", "probe_port_selected", "probe_closed_before_takeover", "takeover_held",
	"released_port_rebound", "rebound_port_matches", "os_bound_port_positive",
	"listener_remained_active", "resources_released", "released_selected_port_rebound",
	"released_listener_port_rebound",
]
const STRING_FIELDS: Array[String] = [
	"failure_code", "takeover_result", "duplicate_result", "historical_cause", "production_countermeasure",
]
const FAILURE_CODES: Array[String] = [
	"none", "probe_bind_failed", "probe_port_invalid", "probe_release_failed", "takeover_bind_failed",
	"takeover_not_rejected", "released_bind_failed", "rebound_host_missing", "rebound_port_mismatch",
	"listener_bind_failed", "listener_host_missing", "listener_port_invalid", "duplicate_not_rejected",
	"listener_not_active", "listener_port_changed", "cleanup_rebind_failed", "cleanup_status_failed",
]
const BIND_RESULTS: Array[String] = ["NOT_OBSERVED", "ERR_CANT_CREATE", "UNEXPECTED"]


func _closed_result(result: Dictionary) -> bool:
	if result.size() != BOOLEAN_FIELDS.size() + STRING_FIELDS.size() + 1:
		return false
	if not result.has("schema_version") or typeof(result["schema_version"]) != TYPE_INT or result["schema_version"] != 1:
		return false
	for field: String in BOOLEAN_FIELDS:
		if not result.has(field):
			return false
		if field == "passed":
			if typeof(result[field]) != TYPE_BOOL:
				return false
		elif typeof(result[field]) != TYPE_BOOL and typeof(result[field]) != TYPE_NIL:
			return false
	for field: String in STRING_FIELDS:
		if not result.has(field) or typeof(result[field]) != TYPE_STRING:
			return false
	return FAILURE_CODES.has(result["failure_code"]) and BIND_RESULTS.has(result["takeover_result"]) \
		and BIND_RESULTS.has(result["duplicate_result"]) and result["historical_cause"] == "UNKNOWN" \
		and result["production_countermeasure"] == "NOT_OBSERVED"
