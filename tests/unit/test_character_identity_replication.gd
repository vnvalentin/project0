extends GutTest
## Public-seam unit tests for Slice 086: multi-peer Character identity
## replication. The server-side ServerPlayerState emits `character_bound` at
## world entry so server_main.gd can broadcast the peer's Character identity;
## the client-side RemotePlayer labels its representation from that identity,
## and ignores identities for other peers. See
## docs/slices/086-multipeer-character-replication.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const RemotePlayerScene: PackedScene = preload("res://client/remote_player.tscn")


func _new_state(peer_id: int) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(peer_id, Vector3.ZERO)
	return state


func test_bind_character_emits_character_bound_with_peer_and_identity() -> void:
	var state: Node = _new_state(7)
	watch_signals(state)
	state.bind_character("char-1", "Aria", {"hue": 3})
	assert_signal_emitted(state, "character_bound")
	var params: Array = get_signal_parameters(state, "character_bound", 0)
	assert_eq(params[0], 7, "emits the owning peer id")
	assert_eq(params[1], "Aria", "emits the Character display name")
	assert_eq(params[2], {"hue": 3}, "emits the Character cosmetic")


func test_bind_character_sets_identity_fields() -> void:
	var state: Node = _new_state(7)
	state.bind_character("char-1", "Aria", {"hue": 3})
	assert_eq(state.character_id, "char-1", "stores the Character id")
	assert_eq(state.character_display_name, "Aria", "stores the display name")
	assert_eq(state.character_cosmetic, {"hue": 3}, "stores the cosmetic")


func _new_remote_player(peer_id: int) -> Node:
	var remote_player: Node = RemotePlayerScene.instantiate()
	add_child_autofree(remote_player)
	remote_player.set_peer_id(peer_id)
	return remote_player


func test_set_character_identity_labels_the_remote_player() -> void:
	var remote_player: Node = _new_remote_player(5)
	remote_player.set_character_identity("Bram", {})
	assert_eq(remote_player.get_node("NameLabel").text, "Bram", "the floating label shows the bound Character name")


func test_identity_signal_only_labels_the_matching_peer() -> void:
	var remote_player: Node = _new_remote_player(5)
	NetworkClient.remote_player_identity_received.emit(9, "Other", {})
	assert_eq(remote_player.get_node("NameLabel").text, "", "an identity for a different peer leaves this node unlabeled")
	NetworkClient.remote_player_identity_received.emit(5, "Mine", {})
	assert_eq(remote_player.get_node("NameLabel").text, "Mine", "an identity for this peer labels this node")
