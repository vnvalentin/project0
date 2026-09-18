extends GutTest
## Slice 127: server-owned Character foundation + presentation-snapshot
## replication. ServerPlayerState creates a baseline unified Character at world
## entry and emits `character_snapshot_ready` with a PRESENTATION-SAFE snapshot
## (derived graph axes + controller/kind only, never raw stat numbers) so
## server_main.gd can replicate it to the owning client. Mirrors the
## character-identity replication test pattern. See
## docs/slices/127-phase14-character-foundation-server.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")


func _new_state(peer_id: int) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(peer_id, Vector3.ZERO)
	return state


func test_world_entry_emits_character_snapshot_ready_with_peer_and_snapshot() -> void:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	watch_signals(state)
	state.start_for_peer(9, Vector3.ZERO)
	assert_signal_emitted(state, "character_snapshot_ready")
	var params: Array = get_signal_parameters(state, "character_snapshot_ready", 0)
	assert_eq(params[0], 9, "emits the owning peer id")
	assert_eq(params[1], state.character_snapshot(), "emits the presentation-safe snapshot")


func test_snapshot_is_the_unified_baseline_humanoid_character() -> void:
	var snapshot: Dictionary = _new_state(7).character_snapshot()
	assert_eq(snapshot["controller_type"], "PLAYER", "the Player is a PLAYER-controlled Character")
	assert_eq(snapshot["character_kind"], "humanoid", "the baseline Player vessel is humanoid")


func test_snapshot_graph_axes_are_normalized_and_balanced() -> void:
	var axes: Dictionary = _new_state(7).character_snapshot()["graph_axes"]
	assert_eq(axes.size(), 6, "all six vessel nodes are present as graph axes")
	var total: float = 0.0
	for key: String in axes:
		total += float(axes[key])
	assert_almost_eq(total, 1.0, 0.0001, "graph axes are normalized proportions summing to 1.0")
	# The balanced creation baseline splits the budget equally: every axis 1/6.
	for key: String in axes:
		assert_almost_eq(float(axes[key]), 1.0 / 6.0, 0.0001, "the baseline vessel is balanced")


func test_snapshot_never_leaks_raw_stat_numbers() -> void:
	var snapshot: Dictionary = _new_state(7).character_snapshot()
	# Presentation safety: only derived graph state crosses to the client.
	assert_false(snapshot.has("base_nodes"), "raw base_nodes are never in the snapshot")
	assert_false(snapshot.has("development"), "raw development is never in the snapshot")
	assert_false(snapshot.has("effective_nodes"), "raw effective nodes are never in the snapshot")
