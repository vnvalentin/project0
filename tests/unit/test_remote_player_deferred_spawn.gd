extends GutTest
## Regression for the late-joiner remote-Player visibility bug: a peer's spawn
## RPC that arrives before this client's gameplay scene is ready (e.g. the
## second player is still on the login/character screen mid-handoff) must be
## deferred and replayed once gameplay loads, and cleared on despawn — otherwise
## the second player to enter never sees the first. See client/network_client.gd
## (_spawn_remote_player_into, render_pending_remote_players, _latest_remote_players).


func before_each() -> void:
	NetworkClient._remote_identities.clear()
	NetworkClient._latest_remote_players.clear()


func after_each() -> void:
	NetworkClient._remote_identities.clear()
	NetworkClient._latest_remote_players.clear()


func test_spawn_into_creates_one_labeled_idempotent_node() -> void:
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	NetworkClient._remote_identities[7] = {"display_name": "Seev", "cosmetic": {}}
	NetworkClient._spawn_remote_player_into(7, Vector3(1, 0, 2), root)
	var node: Node = root.get_node_or_null("RemotePlayers/RemotePlayer_7")
	assert_not_null(node, "a RemotePlayer node is created under the RemotePlayers container")
	assert_eq(node.get_node("NameLabel").text, "Seev", "the node is labeled from the cached identity on spawn")
	NetworkClient._spawn_remote_player_into(7, Vector3(1, 0, 2), root)
	assert_eq(root.get_node("RemotePlayers").get_child_count(), 1, "a second spawn for the same peer id is a no-op")


func test_deferred_spawns_replay_into_a_ready_root() -> void:
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	# Two spawn RPCs that arrived while this client's gameplay scene was not
	# ready are tracked; render_pending_remote_players() replays each tracked
	# entry through _spawn_remote_player_into once gameplay loads.
	NetworkClient._latest_remote_players[9] = Vector3(3, 0, 4)
	NetworkClient._latest_remote_players[12] = Vector3(5, 0, 6)
	for peer_id: int in NetworkClient._latest_remote_players:
		NetworkClient._spawn_remote_player_into(peer_id, NetworkClient._latest_remote_players[peer_id], root)
	assert_not_null(root.get_node_or_null("RemotePlayers/RemotePlayer_9"), "a deferred spawn is replayed once gameplay is ready")
	assert_not_null(root.get_node_or_null("RemotePlayers/RemotePlayer_12"), "every deferred spawn is replayed")


func test_despawn_clears_the_deferred_entry() -> void:
	NetworkClient._latest_remote_players[11] = Vector3.ZERO
	NetworkClient._remote_identities[11] = {"display_name": "Gone", "cosmetic": {}}
	NetworkClient.despawn_remote_player_representation(11)
	assert_false(NetworkClient._latest_remote_players.has(11), "despawn clears the deferred spawn so it is not replayed")
	assert_false(NetworkClient._remote_identities.has(11), "despawn clears the cached identity")
