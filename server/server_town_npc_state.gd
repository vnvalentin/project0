extends RefCounted
class_name ServerTownNpcState
## Slice 129 (Phase 14): a server-owned TOWN NPC — a Character (the same unified
## CharacterFoundation the Player and monster use, AI-controlled) that lives to an
## ActivityRoutine. Its world position is a PURE function of elapsed ticks: it
## travels between the world locations of its scheduled activities, so an
## unobserved NPC is simulated off-screen for free and, when re-observed, is
## exactly where its route says (route-consistent arrival) with no drift.
## Routines are interruptible (e.g. to react to a nearby event); an interrupted
## NPC holds its position until it resumes. A RefCounted + deterministic so its
## whole lifecycle is unit-testable without a SceneTree, like ServerMonsterState.
##
## The ActivityRoutine contract deliberately owns only WHICH activity is current
## over time, not WHERE it happens; this state maps each activity to a world
## location and interpolates the route. See issue #229 and
## docs/adr/0007-unified-character-and-npc-generalization.md.

const CharacterFoundationScript: Script = preload("res://shared/character_foundation.gd")
const ActivityRoutineScript: Script = preload("res://shared/activity_routine.gd")

## Town NPCs are AI-controlled Characters of this kind — the same vessel the
## Player uses, differing only in controller and kind context.
const CHARACTER_KIND: String = "villager"

var npc_id: String
var display_name: String
var home_position: Vector3
var _character: Object
var _routine: Object
## activity_id -> world Vector3. Activities without a mapped location resolve to
## home_position.
var _activity_locations: Dictionary
## While interrupted, the frozen world position the NPC holds until it resumes.
var _interrupt_position: Vector3 = Vector3.ZERO


func _init(
	p_npc_id: String,
	p_home_position: Vector3,
	p_routine: Object,
	p_activity_locations: Dictionary,
	p_display_name: String = ""
) -> void:
	npc_id = p_npc_id
	home_position = p_home_position
	_routine = p_routine
	_activity_locations = p_activity_locations
	display_name = p_display_name if not p_display_name.is_empty() else p_npc_id
	_character = CharacterFoundationScript.create_baseline(
		CharacterFoundationScript.CONTROLLER_AI, CHARACTER_KIND
	)["character"]


## The NPC's current activity at the given elapsed ticks (routine, fallback, or
## interruption), delegated to its ActivityRoutine.
func current_activity(elapsed_ticks: int) -> Dictionary:
	return _routine.current_activity(elapsed_ticks)


## The NPC's world position at the given elapsed ticks. While interrupted it
## holds the frozen position; otherwise it is the pure route position (traveling
## between activity locations), so off-screen simulation and re-observation are
## consistent by construction.
func position_at(elapsed_ticks: int) -> Vector3:
	if _routine.is_interrupted():
		return _interrupt_position
	return _route_position(elapsed_ticks)


## Interrupt the routine with an overriding activity, freezing the NPC at its
## current route position (captured from the given tick) until it resumes.
func interrupt(activity_id: String, at_elapsed_ticks: int) -> void:
	_interrupt_position = _route_position(at_elapsed_ticks)
	_routine.interrupt(activity_id)


func resume() -> void:
	_routine.resume()


func is_interrupted() -> bool:
	return _routine.is_interrupted()


## Whether any observer is within the relevance radius — the seam the manager
## uses to detect relevance transitions (observed vs off-screen-simulated).
func is_relevant(observer_positions: Array, radius_yards: float) -> bool:
	var here: Vector3 = position_at(0) if _routine.is_interrupted() else home_position
	for observer: Variant in observer_positions:
		if (observer as Vector3).distance_to(here) <= radius_yards:
			return true
	return false


## The NPC's presentation-safe Character snapshot (controller/kind + normalized
## graph axes only, never raw stat numbers) — the same shape the Player exposes.
func character_snapshot() -> Dictionary:
	return _character.to_presentation_snapshot()


## Pure route position: linearly interpolate from the previous activity's
## location to the current activity's location across the current step, so the
## NPC arrives at each station by the end of its step and travel is continuous
## across the looping route. An empty routine holds at home.
func _route_position(elapsed_ticks: int) -> Vector3:
	var steps: Array = _routine.steps
	if steps.is_empty():
		return home_position
	var resolved: Dictionary = ActivityRoutineScript.resolve_step(steps, elapsed_ticks)
	var index: int = int(resolved["index"])
	if index < 0:
		return home_position
	var count: int = steps.size()
	var prev_index: int = (index - 1 + count) % count
	var curr_location: Vector3 = _location_for(String((steps[index] as Dictionary).get("activity_id", "")))
	var prev_location: Vector3 = _location_for(String((steps[prev_index] as Dictionary).get("activity_id", "")))
	var duration: int = int(resolved["step_elapsed"]) + int(resolved["step_remaining"])
	if duration <= 0:
		return curr_location
	var t: float = float(resolved["step_elapsed"]) / float(duration)
	return prev_location.lerp(curr_location, t)


func _location_for(activity_id: String) -> Vector3:
	return _activity_locations.get(activity_id, home_position)
