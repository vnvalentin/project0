extends GutTest

const OpsSnapshotScript: Script = preload("res://server/ops_snapshot.gd")

func _valid_inputs() -> Dictionary:
	return {
		"server_id": "project0-game",
		"server_type": OpsSnapshotScript.SERVER_TYPE_WORLD,
		"server_version": "sha-test",
		"status": "healthy",
		"tick_rate": 30,
		"uptime_seconds": 12.5,
		"server_tick": 375,
		"connected_peers": 2,
		"max_peers": 10,
		"app_schema_version": 1,
		"timestamp": 1_726_000_000,
		"extension_schema_version": 1,
		"extension": {"active_encounters": 0, "queue_depth": 1},
	}

func test_build_composes_server_health_core_and_extension() -> void:
	var result: Dictionary = OpsSnapshotScript.build(_valid_inputs())
	assert_eq(result["outcome"], OpsSnapshotScript.OUTCOME_OK)
	var snapshot: Dictionary = result["snapshot"]
	assert_eq(snapshot["snapshot_schema_version"], 1)
	assert_eq(snapshot["server_id"], "project0-game")
	assert_eq(snapshot["server_type"], OpsSnapshotScript.SERVER_TYPE_WORLD)
	assert_eq(snapshot["connected_peers"], 2)
	assert_eq(snapshot["extension"]["queue_depth"], 1)

func test_build_rejects_unknown_server_type() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["server_type"] = "worker"
	var result: Dictionary = OpsSnapshotScript.build(inputs)
	assert_eq(result["outcome"], OpsSnapshotScript.OUTCOME_INVALID)

func test_wire_rejects_incompatible_schema() -> void:
	var wire: Dictionary = _valid_inputs()
	wire["snapshot_schema_version"] = 99
	var result: Dictionary = OpsSnapshotScript.from_wire_dict(wire)
	assert_eq(result["outcome"], OpsSnapshotScript.OUTCOME_UNSUPPORTED_VERSION)

func test_build_rejects_unbounded_extension() -> void:
	var inputs: Dictionary = _valid_inputs()
	var extension: Dictionary = {}
	for index: int in range(OpsSnapshotScript.MAX_EXTENSION_KEYS + 1):
		extension["key_%d" % index] = index
	inputs["extension"] = extension
	var result: Dictionary = OpsSnapshotScript.build(inputs)
	assert_eq(result["outcome"], OpsSnapshotScript.OUTCOME_INVALID)

func test_build_rejects_nested_extension_values() -> void:
	var inputs: Dictionary = _valid_inputs()
	inputs["extension"] = {"nested": {"secret": "value"}}
	var result: Dictionary = OpsSnapshotScript.build(inputs)
	assert_eq(result["outcome"], OpsSnapshotScript.OUTCOME_INVALID)
