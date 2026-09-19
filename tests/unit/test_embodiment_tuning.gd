extends GutTest
## Slice 132 (Phase 15, P-016-A): the versioned embodiment tuning resolve seam
## (server/embodiment_tuning.gd) and its shared shape (shared/
## embodiment_tuning_schema.gd). Resolve is the sole, fail-closed access path;
## unknown versions yield no tuning. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")
const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")


func test_resolve_returns_the_frozen_default_tuning() -> void:
	var result: Dictionary = EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)
	assert_eq(result["outcome"], "ok")
	var tuning: Object = result["tuning"]
	assert_eq(tuning.tuning_version, EmbodimentTuningScript.DEFAULT_TUNING_VERSION, "stamps the resolved provenance")
	assert_eq(tuning.schema_version, 1)
	assert_almost_eq(tuning.budget, 60.0, 0.0001, "budget matches the fixed vessel area")
	assert_almost_eq(tuning.floor_per_node, 4.0, 0.0001)
	assert_almost_eq(tuning.gain_per_evidence, 1.0, 0.0001)


func test_resolve_rejects_an_unknown_tuning_version() -> void:
	var result: Dictionary = EmbodimentTuningScript.resolve("nonexistent-tuning")
	assert_eq(result["outcome"], "unsupported_tuning_version", "an unknown version fails closed")
	assert_null(result["tuning"], "no fallback tuning is guessed")


func test_resolve_rejects_an_empty_tuning_version() -> void:
	assert_eq(EmbodimentTuningScript.resolve("")["outcome"], "unsupported_tuning_version")


func test_opposition_weights_cover_the_other_five_nodes_only() -> void:
	var tuning: Object = EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]
	var row: Dictionary = tuning.opposition_weights_for("STR")
	assert_eq(row.size(), 5, "a trained node opposes the other five")
	assert_false(row.has("STR"), "a node is never in its own opposition row")
	for other: String in ["DEX", "CON", "INT", "WIS", "CHA"]:
		assert_almost_eq(float(row[other]), 1.0, 0.0001, "the baseline weight is uniform for %s" % other)


func test_opposition_weights_for_an_unknown_node_are_empty() -> void:
	var tuning: Object = EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]
	assert_eq(tuning.opposition_weights_for("ZZZ").size(), 0)


func test_floor_for_supported_and_unsupported_nodes() -> void:
	var tuning: Object = EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]
	assert_almost_eq(tuning.floor_for("CON"), 4.0, 0.0001)
	assert_almost_eq(tuning.floor_for("ZZZ"), 0.0, 0.0001, "an unsupported node has no floor")


func test_schema_helpers() -> void:
	assert_true(SchemaScript.is_supported_node("WIS"))
	assert_false(SchemaScript.is_supported_node("ZZZ"))
	assert_false(SchemaScript.is_supported_node(3))
	assert_eq(SchemaScript.other_nodes("STR").size(), 5)
	assert_false(SchemaScript.other_nodes("STR").has("STR"))
	assert_almost_eq(SchemaScript.sum_over_nodes({"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10}), 60.0, 0.0001)


func test_check_bounded_fails_closed_on_non_finite_and_out_of_range() -> void:
	assert_eq(SchemaScript.check_bounded(5.0, 0.0, 10.0), "ok")
	assert_eq(SchemaScript.check_bounded(INF, 0.0, 10.0), "out_of_bounds")
	assert_eq(SchemaScript.check_bounded(-1.0, 0.0, 10.0), "out_of_bounds")
	assert_eq(SchemaScript.check_bounded(11.0, 0.0, 10.0), "out_of_bounds")
