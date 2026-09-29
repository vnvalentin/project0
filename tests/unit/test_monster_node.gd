extends GutTest
## Public-seam unit test for Slice 033's client/monster.gd: a purely cosmetic
## node that reacts to the existing authoritative combat_event_received signal
## (client/network_client.gd) — mirrors client/target_dummy.gd's own
## HIT-reaction pattern, plus a death reaction that frees the node. This node
## never decides a hit or death itself; it only renders what NetworkClient has
## already relayed. See docs/slices/033-client-monster-replication-and-rendering.md.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const MonsterSceneScript: PackedScene = preload("res://client/monster.tscn")


func _make_monster(target_id: String) -> Node3D:
	var monster: Node3D = MonsterSceneScript.instantiate()
	monster.target_id = target_id
	add_child_autofree(monster)
	return monster


func test_hit_event_for_its_own_target_id_starts_a_reaction() -> void:
	var monster: Node3D = _make_monster("m0")
	await wait_physics_frames(1)

	NetworkClient.combat_event_received.emit(CombatContractsScript.COMBAT_EVENT_HIT, 1, "m0", Vector3.ZERO, 10)

	assert_gt(monster.get("_hit_reaction_time_remaining"), 0.0, "a HIT for this monster's own target_id starts the cosmetic reaction")


func test_windup_snapshot_starts_a_facing_aligned_telegraph() -> void:
	var monster: Node3D = _make_monster("m0")
	await wait_physics_frames(1)
	NetworkClient.combat_event_received.emit(
		CombatContractsScript.COMBAT_EVENT_MONSTER_WINDUP,
		-1,
		"m0",
		Vector3.LEFT,
		20
	)

	assert_eq(monster.get("_telegraph_target_tick"), 20, "the client retains the server target timestamp")
	assert_eq(monster.get("_telegraph_facing"), Vector3.LEFT, "the client retains the server locked facing")
	assert_gt(monster.get("_telegraph_time_remaining"), 0.0, "WINDUP starts a visible bounded telegraph")
	assert_almost_eq(monster.rotation.y, PI / 2.0, 0.001, "the telegraph faces the server-approved direction")
	assert_true(monster.get_node("TelegraphArrow").visible, "the telegraph shows a visible facing cue")
	assert_true(monster.get_node("TelegraphRange").visible, "the telegraph shows the authoritative reach")


func test_unknown_attack_state_schema_is_ignored() -> void:
	var monster: Node3D = _make_monster("m0")
	await wait_physics_frames(1)

	monster.set_attack_state({"schema_version": 999, "phase": "WINDUP", "target_tick": 20, "duration_ticks": 10, "facing": Vector3.LEFT})

	assert_eq(monster.get("_telegraph_time_remaining"), 0.0, "unknown attack-state schemas fail closed")


func test_hit_event_for_a_different_target_id_is_ignored() -> void:
	var monster: Node3D = _make_monster("m0")
	await wait_physics_frames(1)

	NetworkClient.combat_event_received.emit(CombatContractsScript.COMBAT_EVENT_HIT, 1, "some_other_monster", Vector3.ZERO, 10)

	assert_eq(monster.get("_hit_reaction_time_remaining"), 0.0, "a HIT for a different target_id does not start a reaction")


func test_death_event_for_its_own_target_id_frees_the_node() -> void:
	var monster: Node3D = MonsterSceneScript.instantiate()
	monster.target_id = "m0"
	add_child(monster)
	await wait_physics_frames(1)

	NetworkClient.combat_event_received.emit(CombatContractsScript.COMBAT_EVENT_DEATH, 1, "m0", Vector3.ZERO, 10)
	# The death reaction plays out over real physics ticks before freeing —
	# wait long enough for MonsterScript.DEATH_REACTION_DURATION_SEC to elapse.
	await wait_physics_frames(30)

	assert_true(not is_instance_valid(monster) or monster.is_queued_for_deletion(), "a DEATH for this monster's own target_id frees the node")


func test_death_event_for_a_different_target_id_is_ignored() -> void:
	var monster: Node3D = _make_monster("m0")
	await wait_physics_frames(1)

	NetworkClient.combat_event_received.emit(CombatContractsScript.COMBAT_EVENT_DEATH, 1, "some_other_monster", Vector3.ZERO, 10)
	await wait_physics_frames(1)

	assert_true(is_instance_valid(monster) and not monster.is_queued_for_deletion(), "a DEATH for a different target_id does not free this node")
