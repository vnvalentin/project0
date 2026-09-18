extends GutTest
## Slice 129: the server-owned town NPC — a Character (shared CharacterFoundation,
## AI-controlled) that lives to an ActivityRoutine. Its world position is a pure
## function of elapsed ticks (off-screen simulation + route-consistent arrival),
## routines are interruptible, and it exposes a presentation-safe snapshot. See
## docs/slices/129-phase14-town-npc-state.md.

const ServerTownNpcStateScript: Script = preload("res://server/server_town_npc_state.gd")
const ActivityRoutineScript: Script = preload("res://shared/activity_routine.gd")

const HOME: Vector3 = Vector3(0, 1, 0)
const FORGE: Vector3 = Vector3(10, 1, 0)
const MARKET: Vector3 = Vector3(0, 1, 10)


func _routine(steps: Array, fallback: String = "idle") -> Object:
	return ActivityRoutineScript.from_wire_dict(
		{"schema_version": 1, "steps": steps, "fallback_mode": fallback}
	)["routine"]


func _npc() -> Object:
	var steps: Array = [
		{"activity_id": "forge", "duration_ticks": 10},
		{"activity_id": "market", "duration_ticks": 10},
	]
	return ServerTownNpcStateScript.new(
		"villager_0", HOME, _routine(steps), {"forge": FORGE, "market": MARKET}, "Rowan"
	)


func test_town_npc_is_an_ai_villager_character() -> void:
	var snapshot: Dictionary = _npc().character_snapshot()
	assert_eq(snapshot["controller_type"], "AI", "a town NPC is AI-controlled")
	assert_eq(snapshot["character_kind"], "villager", "a town NPC's Character kind is 'villager'")


func test_position_travels_between_activity_locations() -> void:
	# Mid forge step (elapsed 5): halfway from the previous station (market) to
	# the forge.
	assert_true(_npc().position_at(5).is_equal_approx(MARKET.lerp(FORGE, 0.5)), "travels along the route")


func test_arrives_at_station_by_end_of_step() -> void:
	# End of the forge step (elapsed 10): arrived at the forge.
	assert_true(_npc().position_at(10).is_equal_approx(FORGE), "arrives at the forge by the end of its step")


func test_position_loops_route_consistently_for_offscreen_simulation() -> void:
	# The period is 20; elapsed 25 == elapsed 5. Computing directly (no stepping)
	# lands exactly on the route with no drift.
	var npc: Object = _npc()
	assert_true(npc.position_at(25).is_equal_approx(npc.position_at(5)), "route is consistent across loops")


func test_empty_routine_holds_at_home() -> void:
	var npc: Object = ServerTownNpcStateScript.new("idler", HOME, _routine([]), {})
	assert_true(npc.position_at(0).is_equal_approx(HOME), "an empty routine holds at home")
	assert_true(npc.position_at(500).is_equal_approx(HOME), "still at home much later")


func test_interrupt_freezes_position_and_resume_restores_the_route() -> void:
	var npc: Object = _npc()
	var frozen: Vector3 = npc.position_at(5)
	npc.interrupt("react_to_event", 5)
	assert_true(npc.is_interrupted())
	assert_true(npc.position_at(8).is_equal_approx(frozen), "holds its position while interrupted")
	npc.resume()
	assert_false(npc.is_interrupted())
	assert_true(npc.position_at(8).is_equal_approx(MARKET.lerp(FORGE, 0.8)), "resumes the route clock")


func test_current_activity_reflects_the_routine() -> void:
	var current: Dictionary = _npc().current_activity(12)
	assert_eq(current["activity_id"], "market", "at elapsed 12 the NPC is at market")
	assert_eq(current["source"], "routine")


func test_is_relevant_detects_a_nearby_observer() -> void:
	var npc: Object = _npc()
	assert_true(npc.is_relevant([HOME + Vector3(2, 0, 0)], 5.0), "a nearby observer makes the NPC relevant")
	assert_false(npc.is_relevant([HOME + Vector3(100, 0, 0)], 5.0), "a distant observer does not")


func test_snapshot_is_presentation_safe() -> void:
	var snapshot: Dictionary = _npc().character_snapshot()
	assert_false(snapshot.has("base_nodes"), "raw base_nodes are never exposed")
	assert_false(snapshot.has("development"), "raw development is never exposed")
	assert_false(snapshot.has("effective_nodes"), "raw effective nodes are never exposed")
