extends GutTest
## Slice 142 (Phase 15 follow-on, P-016): server-owned effective-mechanics
## snapshot + presentation-snapshot replication. ServerPlayerState creates a
## durable vessel (via its own EmbodimentProgressionService) at world entry and
## emits `effective_mechanics_ready` with a PRESENTATION-SAFE snapshot (normalized
## graph axes + subsystem-safe derived summaries, never raw effective numbers) so
## server_main.gd can replicate it to the owning client — the same peer-scoped
## channel proven for the Character snapshot in Phase 14. Mirrors
## test_character_foundation_replication.gd. See
## docs/slices/142-effective-mechanics-replication.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")


func _new_state(peer_id: int) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(peer_id, Vector3.ZERO)
	return state


func test_world_entry_emits_effective_mechanics_ready_with_peer_and_snapshot() -> void:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	watch_signals(state)
	state.start_for_peer(9, Vector3.ZERO)
	assert_signal_emitted(state, "effective_mechanics_ready")
	var params: Array = get_signal_parameters(state, "effective_mechanics_ready", 0)
	assert_eq(params[0], 9, "emits the owning peer id")
	assert_eq(params[1], state.effective_mechanics_snapshot(), "emits the presentation-safe snapshot")


func test_snapshot_is_empty_before_world_entry() -> void:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	assert_eq(state.effective_mechanics_snapshot(), {}, "no snapshot before the vessel is created at world entry")


func test_snapshot_graph_axes_are_normalized_and_balanced() -> void:
	var axes: Dictionary = _new_state(7).effective_mechanics_snapshot()["graph_axes"]
	assert_eq(axes.size(), 6, "all six vessel nodes are present as graph axes")
	var total: float = 0.0
	for key: String in axes:
		total += float(axes[key])
	assert_almost_eq(total, 1.0, 0.0001, "graph axes are normalized proportions summing to 1.0")
	# The balanced creation baseline splits the budget equally: every axis 1/6.
	for key: String in axes:
		assert_almost_eq(float(axes[key]), 1.0 / 6.0, 0.0001, "the baseline vessel is balanced")


func test_snapshot_carries_subsystem_safe_derived_summaries() -> void:
	var snapshot: Dictionary = _new_state(7).effective_mechanics_snapshot()
	assert_true(snapshot.has("derived"), "the composed snapshot carries a derived map")
	var derived: Dictionary = snapshot["derived"]
	assert_true(derived.has("friction_profile"), "friction subsystem result is present")
	assert_true(derived.has("kinetic_energy_cost_factor"), "kinetic subsystem result is present")
	assert_true(derived.has("meridian_unlocks"), "meridian subsystem result is present")
	assert_true(derived.has("burnout_active_pathways"), "burnout subsystem result is present")


func test_snapshot_stamps_the_current_tuning_version() -> void:
	var snapshot: Dictionary = _new_state(7).effective_mechanics_snapshot()
	assert_eq(
		String(snapshot["tuning_version"]),
		"vessel-2026q4-baseline",
		"the snapshot stamps the current tuning version for provenance"
	)


func test_snapshot_never_leaks_raw_effective_numbers() -> void:
	var snapshot: Dictionary = _new_state(7).effective_mechanics_snapshot()
	# Presentation safety: only derived graph state + subsystem-safe summaries cross.
	assert_false(snapshot.has("effective_nodes"), "raw effective nodes are never in the snapshot")
	assert_false(snapshot.has("base_nodes"), "raw base_nodes are never in the snapshot")
	assert_true(snapshot.has("graph_axes"), "only the normalized graph proportions cross")
