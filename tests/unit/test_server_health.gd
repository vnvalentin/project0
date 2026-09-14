extends GutTest
## Public-seam unit tests for Slice 055's server health/tick contract
## (server/server_health.gd). Pure and stateless — exercises the static
## resolve_tick_rate()/build_snapshot() functions with plain values, no live
## server process or scene tree. See
## docs/slices/055-server-fixed-tick-and-health-contract.md.

const ServerHealthScript: Script = preload("res://server/server_health.gd")


func _valid_inputs() -> Dictionary:
	return {
		"status": ServerHealthScript.STATUS_HEALTHY,
		"tick_rate": 30,
		"uptime_seconds": 12.5,
		"server_tick": 375,
		"connected_peers": 2,
		"max_peers": 10,
		"app_schema_version": 1,
		"timestamp": 1_726_000_000,
	}


func test_resolve_tick_rate_defaults_on_empty() -> void:
	assert_eq(ServerHealthScript.resolve_tick_rate(""), ServerHealthScript.DEFAULT_TICK_RATE, "empty config resolves to the default tick rate")


func test_resolve_tick_rate_defaults_on_non_integer() -> void:
	assert_eq(ServerHealthScript.resolve_tick_rate("fast"), ServerHealthScript.DEFAULT_TICK_RATE, "non-integer config resolves to the default tick rate")


func test_resolve_tick_rate_clamps_below_minimum() -> void:
	assert_eq(ServerHealthScript.resolve_tick_rate("5"), ServerHealthScript.MIN_TICK_RATE, "a value below the minimum clamps up to MIN_TICK_RATE")


func test_resolve_tick_rate_clamps_above_maximum() -> void:
	assert_eq(ServerHealthScript.resolve_tick_rate("120"), ServerHealthScript.MAX_TICK_RATE, "a value above the maximum clamps down to MAX_TICK_RATE")


func test_resolve_tick_rate_passes_valid_value() -> void:
	assert_eq(ServerHealthScript.resolve_tick_rate("24"), 24, "an in-range value passes through unchanged")


func test_build_snapshot_happy_path() -> void:
	var result: Dictionary = ServerHealthScript.build_snapshot(_valid_inputs())
	assert_eq(result["outcome"], ServerHealthScript.OUTCOME_OK, "valid inputs build a snapshot")
	var snapshot: Dictionary = result["snapshot"]
	assert_eq(snapshot["snapshot_schema_version"], ServerHealthScript.SNAPSHOT_SCHEMA_VERSION, "snapshot carries the contract schema version")
	assert_eq(snapshot["status"], ServerHealthScript.STATUS_HEALTHY, "status is carried through")
	assert_eq(snapshot["tick_rate"], 30, "tick rate is carried through")
	assert_eq(snapshot["connected_peers"], 2, "connected peers is carried through")
	assert_eq(snapshot["max_peers"], 10, "max peers is carried through")
	assert_eq(snapshot["timestamp"], 1_726_000_000, "the caller-supplied timestamp is carried through, never read from a clock")


func test_build_snapshot_rejects_unknown_status() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["status"] = "on_fire"
	var result: Dictionary = ServerHealthScript.build_snapshot(inputs)
	assert_eq(result["outcome"], ServerHealthScript.OUTCOME_INVALID, "an unknown status is rejected")
	assert_false(result.has("snapshot"), "a rejected build produces no snapshot")


func test_build_snapshot_rejects_out_of_range_tick_rate() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["tick_rate"] = 120
	var result: Dictionary = ServerHealthScript.build_snapshot(inputs)
	assert_eq(result["outcome"], ServerHealthScript.OUTCOME_INVALID, "a tick rate outside 20-30 is rejected")


func test_build_snapshot_rejects_negative_uptime() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["uptime_seconds"] = -1.0
	var result: Dictionary = ServerHealthScript.build_snapshot(inputs)
	assert_eq(result["outcome"], ServerHealthScript.OUTCOME_INVALID, "a negative uptime is rejected")


func test_build_snapshot_rejects_non_finite_uptime() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["uptime_seconds"] = INF
	var result: Dictionary = ServerHealthScript.build_snapshot(inputs)
	assert_eq(result["outcome"], ServerHealthScript.OUTCOME_INVALID, "a non-finite uptime is rejected")


func test_build_snapshot_rejects_peers_over_capacity() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["connected_peers"] = 11
	inputs["max_peers"] = 10
	var result: Dictionary = ServerHealthScript.build_snapshot(inputs)
	assert_eq(result["outcome"], ServerHealthScript.OUTCOME_INVALID, "connected peers cannot exceed max peers")
