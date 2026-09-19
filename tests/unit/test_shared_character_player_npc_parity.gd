extends GutTest
## Slice 128: Player/NPC Character parity — the Phase 14 thesis. The Player
## (ServerPlayerState) and the monster (ServerMonsterState) both carry the SAME
## unified CharacterFoundation, differing only in controller type. This is the
## "NPC == Player Character, without duplicating Monster logic" validation for
## the F-036 exit gate. See docs/slices/128-phase14-npc-character-foundation.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const ServerMonsterStateScript: Script = preload("res://server/server_monster_state.gd")


func _player_snapshot() -> Dictionary:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(1, Vector3.ZERO)
	return state.character_snapshot()


func _monster_snapshot() -> Dictionary:
	# ServerMonsterState is a RefCounted; no SceneTree needed.
	var monster: Object = ServerMonsterStateScript.new("monster_0", Vector3(10, 0, 0))
	return monster.character_snapshot()


func test_player_is_a_player_controlled_character() -> void:
	assert_eq(_player_snapshot()["controller_type"], "PLAYER", "the Player is PLAYER-controlled")


func test_monster_is_an_ai_controlled_character() -> void:
	var snapshot: Dictionary = _monster_snapshot()
	assert_eq(snapshot["controller_type"], "AI", "the monster is AI-controlled")
	assert_eq(snapshot["character_kind"], "monster", "the monster's Character kind is 'monster'")


func test_player_and_npc_share_one_vessel_structure() -> void:
	# Both derive from the same CharacterFoundation baseline: six normalized,
	# balanced graph axes. The only difference is the controller type.
	var player: Dictionary = _player_snapshot()
	var monster: Dictionary = _monster_snapshot()
	assert_eq(
		(player["graph_axes"] as Dictionary).keys(),
		(monster["graph_axes"] as Dictionary).keys(),
		"Player and NPC expose the same six vessel axes"
	)
	for key: String in (player["graph_axes"] as Dictionary):
		assert_almost_eq(
			float(player["graph_axes"][key]),
			float(monster["graph_axes"][key]),
			0.0001,
			"the baseline vessel proportion for %s is identical for Player and NPC" % key
		)
	assert_ne(player["controller_type"], monster["controller_type"], "they differ only in controller type")


func test_npc_snapshot_is_presentation_safe() -> void:
	var snapshot: Dictionary = _monster_snapshot()
	# Presentation safety holds for NPCs too: no raw stat numbers cross the seam.
	assert_false(snapshot.has("base_nodes"), "raw base_nodes are never exposed")
	assert_false(snapshot.has("development"), "raw development is never exposed")
	assert_false(snapshot.has("effective_nodes"), "raw effective nodes are never exposed")
