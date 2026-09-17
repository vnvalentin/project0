extends GutTest
## Slice 116 (Phase 14): public-seam tests for the unified Character foundation.
## Player and NPC share ONE contract; the baseline is fixed and balanced;
## development is a separate additive layer; the presentation snapshot never
## leaks raw numeric stats; and the parser fails closed on bad input.

const CharacterFoundationScript: Script = preload("res://shared/character_foundation.gd")

const _NODE_KEYS: Array = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]


func _balanced_wire(controller: String, kind: String) -> Dictionary:
	var base: Dictionary = {}
	var dev: Dictionary = {}
	for key in _NODE_KEYS:
		base[key] = 10.0
		dev[key] = 0.0
	return {
		"schema_version": 1,
		"controller_type": controller,
		"character_kind": kind,
		"base_nodes": base,
		"development": dev,
	}


func test_player_and_npc_share_one_contract_differing_only_by_controller_and_kind() -> void:
	var player: Dictionary = CharacterFoundationScript.create_baseline("PLAYER", "humanoid")
	var npc: Dictionary = CharacterFoundationScript.create_baseline("AI", "dragon")
	assert_eq(player["outcome"], "ok")
	assert_eq(npc["outcome"], "ok")
	var p: Object = player["character"]
	var n: Object = npc["character"]
	assert_eq(p.controller_type, "PLAYER")
	assert_eq(n.controller_type, "AI")
	assert_eq(p.character_kind, "humanoid")
	assert_eq(n.character_kind, "dragon")
	# Same baseline vessel regardless of controller/kind.
	assert_eq(p.base_nodes, n.base_nodes)


func test_baseline_is_balanced_and_preserves_the_fixed_budget() -> void:
	var result: Dictionary = CharacterFoundationScript.create_baseline("PLAYER", "humanoid")
	var c: Object = result["character"]
	var total: float = 0.0
	for key in _NODE_KEYS:
		assert_eq(c.base_nodes[key], 10.0)
		total += float(c.base_nodes[key])
	assert_almost_eq(total, 60.0, 0.0001)


func test_effective_nodes_add_development_across_multiple_nodes_deterministically() -> void:
	var wire: Dictionary = _balanced_wire("PLAYER", "humanoid")
	wire["development"]["STR"] = 5.0
	wire["development"]["DEX"] = 3.0
	var parsed: Dictionary = CharacterFoundationScript.from_wire_dict(wire)
	assert_eq(parsed["outcome"], "ok")
	var c: Object = parsed["character"]
	var eff: Dictionary = c.effective_nodes()
	assert_eq(eff["STR"], 15.0)
	assert_eq(eff["DEX"], 13.0)
	assert_eq(eff["CON"], 10.0)


func test_presentation_snapshot_excludes_raw_numeric_stat_values() -> void:
	var wire: Dictionary = _balanced_wire("PLAYER", "humanoid")
	wire["development"]["STR"] = 30.0
	var parsed: Dictionary = CharacterFoundationScript.from_wire_dict(wire)
	var c: Object = parsed["character"]
	var snap: Dictionary = c.to_presentation_snapshot()
	assert_false(snap.has("base_nodes"), "snapshot must not expose base_nodes")
	assert_false(snap.has("development"), "snapshot must not expose development")
	assert_false(snap.has("effective_nodes"), "snapshot must not expose effective_nodes")
	assert_true(snap.has("graph_axes"), "snapshot exposes normalized graph axes")
	var axes: Dictionary = snap["graph_axes"]
	var axis_sum: float = 0.0
	for key in _NODE_KEYS:
		axis_sum += float(axes[key])
	assert_almost_eq(axis_sum, 1.0, 0.0001)
	# STR trained highest, so its axis proportion is the largest.
	assert_true(axes["STR"] > axes["CON"], "trained axis has the larger proportion")


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _balanced_wire("PLAYER", "humanoid")
	wire["schema_version"] = 999
	var result: Dictionary = CharacterFoundationScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_version")
	assert_null(result["character"])


func test_from_wire_dict_rejects_unsupported_controller() -> void:
	var wire: Dictionary = _balanced_wire("WARLORD", "humanoid")
	var result: Dictionary = CharacterFoundationScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_controller")


func test_from_wire_dict_rejects_non_finite_value() -> void:
	var wire: Dictionary = _balanced_wire("PLAYER", "humanoid")
	wire["development"]["STR"] = INF
	var result: Dictionary = CharacterFoundationScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_budget_violation() -> void:
	var wire: Dictionary = _balanced_wire("PLAYER", "humanoid")
	wire["base_nodes"]["STR"] = 25.0  # sum becomes 75, not the fixed 60
	var result: Dictionary = CharacterFoundationScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "budget_violation")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = CharacterFoundationScript.from_wire_dict("not a dict")
	assert_eq(result["outcome"], "malformed")
