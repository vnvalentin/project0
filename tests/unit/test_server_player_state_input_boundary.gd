extends GutTest
## #1452 bounded release-policy and latest-intent controls at public seams.
## ServerPlayerState is real; relaying position_updated through the public
## NetworkClient receive/signal method is direct simulation, not wire delivery.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const MovementObservationScript: Script = preload("res://tests/fixtures/prediction_movement_observation.gd")
const STEP_DELTA: float = 1.0 / 60.0
const OWNER_PEER: int = 1

var _network_client: Node
var _previous_network_name: StringName = &""
var _state: Node
var _observer: RefCounted
var _snapshot_callback: Callable = Callable()
var _position_callback: Callable = Callable()
var _held_floor: int = -1
var _published_sequence: int = -1


func before_all() -> void:
	_network_client = get_tree().root.get_node_or_null("NetworkClient")
	if _network_client != null:
		_previous_network_name = _network_client.name
		_network_client.name = "InputBoundaryTestNetworkClient"


func after_all() -> void:
	if is_instance_valid(_network_client):
		_network_client.name = _previous_network_name
	_network_client = null


func before_each() -> void:
	if _network_client == null:
		return
	_observer = MovementObservationScript.new()
	_snapshot_callback = _observer.observe
	_network_client.authoritative_position_received.connect(_snapshot_callback)
	_held_floor = _network_client.next_input_sequence()
	_published_sequence = _held_floor
	_state = ServerPlayerStateScript.new()
	add_child(_state)
	_state.set_physics_process(false)
	_state.start_for_peer(OWNER_PEER, Vector3.ZERO)
	_position_callback = _receive_controlled_position
	_state.position_updated.connect(_position_callback)
	_network_client.receive_authoritative_position(_state.position, _published_sequence)
	_observer.begin_hold(_held_floor)


func after_each() -> void:
	if is_instance_valid(_state):
		if _state.position_updated.is_connected(_position_callback):
			_state.position_updated.disconnect(_position_callback)
		_state.free()
	_state = null
	if is_instance_valid(_network_client) and _snapshot_callback.is_valid():
		if _network_client.authoritative_position_received.is_connected(_snapshot_callback):
			_network_client.authoritative_position_received.disconnect(_snapshot_callback)
	if _observer != null:
		_observer.finish()
	_observer = null
	_position_callback = Callable()
	_snapshot_callback = Callable()


func _receive_controlled_position(peer_id: int, position: Vector3) -> void:
	if peer_id == OWNER_PEER:
		_network_client.receive_authoritative_position(position, _published_sequence)


func test_release_is_rejected_without_authoritative_progress() -> void:
	assert_true(_state != null, "1452 public-node simulation fixture is available")
	if _state == null:
		return
	var held_sequence: int = _network_client.next_input_sequence()
	_state.apply_input_intent(OWNER_PEER, Vector2(0.0, 1.0), held_sequence)
	_published_sequence = _network_client.next_input_sequence()
	_state.apply_input_intent(OWNER_PEER, Vector2.ZERO, _published_sequence)
	_state._physics_process(STEP_DELTA)
	assert_true(is_zero_approx(_state.position.z), "1452 direct simulation release before integration remains stationary")
	assert_false(
		_observer.release_ready(30),
		"1452 release requires authoritative progress while input remains held"
	)


func _hold_and_integrate(ticks: int) -> int:
	var sequence: int = _network_client.next_input_sequence()
	_published_sequence = sequence
	_state.apply_input_intent(OWNER_PEER, Vector2(0.0, 1.0), sequence)
	for _index: int in ticks:
		_state._physics_process(STEP_DELTA)
	return sequence


func _replace_observer(with_baseline: bool) -> void:
	if _network_client.authoritative_position_received.is_connected(_snapshot_callback):
		_network_client.authoritative_position_received.disconnect(_snapshot_callback)
	_observer.finish()
	_observer = MovementObservationScript.new()
	_snapshot_callback = _observer.observe
	_network_client.authoritative_position_received.connect(_snapshot_callback)
	_held_floor = _network_client.next_input_sequence()
	if with_baseline:
		_network_client.receive_authoritative_position(Vector3.ZERO, _held_floor)
	_observer.begin_hold(_held_floor)


func test_release_before_integration_supersedes_held_input() -> void:
	var held_sequence: int = _network_client.next_input_sequence()
	_state.apply_input_intent(OWNER_PEER, Vector2(0.0, 1.0), held_sequence)
	_published_sequence = _network_client.next_input_sequence()
	_state.apply_input_intent(OWNER_PEER, Vector2.ZERO, _published_sequence)
	_state._physics_process(STEP_DELTA)
	assert_true(is_zero_approx(_state.position.z), "1452 direct simulation newer release supersedes unintegrated held intent")
	assert_false(_observer.authoritative_progress_observed(), "1452 direct simulation release acknowledgement does not prove displacement")


func test_held_integration_precedes_release() -> void:
	_hold_and_integrate(7)
	var held_position: Vector3 = _state.position
	assert_true(held_position.z > 0.5, "1452 real node integration produces positive Z progress while held")
	_published_sequence = _network_client.next_input_sequence()
	_state.apply_input_intent(OWNER_PEER, Vector2.ZERO, _published_sequence)
	_state._physics_process(STEP_DELTA)
	assert_true(_state.position.is_equal_approx(held_position), "1452 direct simulation release preserves already integrated displacement")


func test_stale_release_preserves_held_input() -> void:
	var held_sequence: int = _hold_and_integrate(0)
	_state.apply_input_intent(OWNER_PEER, Vector2.ZERO, held_sequence)
	for _index: int in 7:
		_state._physics_process(STEP_DELTA)
	assert_true(_state.position.z > 0.5, "1452 stale equal-sequence release cannot replace the owner's held intent")


func test_foreign_release_preserves_held_input() -> void:
	_hold_and_integrate(0)
	var foreign_sequence: int = _network_client.next_input_sequence()
	_state.apply_input_intent(OWNER_PEER + 1, Vector2.ZERO, foreign_sequence)
	for _index: int in 7:
		_state._physics_process(STEP_DELTA)
	assert_true(_state.position.z > 0.5, "1452 foreign-owner release cannot replace the owner's held intent")


func test_subsequent_held_progress_qualifies_release() -> void:
	_hold_and_integrate(7)
	assert_true(
		_observer.release_ready(7),
		"1452 equal acknowledged sequence with real positive Z integration qualifies held release"
	)
	assert_false(_observer.release_ready(31), "1452 progress cannot qualify beyond the original held frame cap")
	var stale_sequence: int = _held_floor - 1
	_network_client.receive_authoritative_position(Vector3.ZERO, stale_sequence)
	assert_true(_observer.release_ready(7), "1452 stale snapshot does not revoke already observed valid held progress")
	_observer.finish()
	assert_false(_observer.release_ready(7), "1452 stopped observation cannot qualify a later release")


func test_missing_baseline_or_stale_boundary_rejects_release() -> void:
	_replace_observer(false)
	_network_client.receive_authoritative_position(Vector3(0.0, 0.0, 2.0), _held_floor + 1)
	assert_false(_observer.release_ready(30), "1452 the first received snapshot establishes baseline without qualifying progress")
	_replace_observer(true)
	_network_client.receive_authoritative_position(Vector3(0.0, 0.0, 1.0), _held_floor)
	assert_false(_observer.release_ready(30), "1452 equality with the held sequence floor cannot qualify displacement")
	_network_client.receive_authoritative_position(Vector3(0.0, 0.0, 1.0), _held_floor - 1)
	assert_false(_observer.release_ready(30), "1452 decreasing acknowledgement cannot qualify displacement")
	_network_client.receive_authoritative_position(Vector3(2.0, 0.0, 0.0), _held_floor + 1)
	assert_false(_observer.release_ready(30), "1452 movement on another axis cannot qualify the positive Z contract")
	_network_client.receive_authoritative_position(Vector3(0.0, 0.0, 0.5), _held_floor + 1)
	assert_false(_observer.release_ready(30), "1452 positive Z progress must exceed the unchanged threshold")
	_network_client.receive_authoritative_position(Vector3(NAN, 0.0, 1.0), _held_floor + 1)
	assert_false(_observer.release_ready(30), "1452 nonfinite snapshot position cannot qualify held displacement")
	_network_client.receive_authoritative_position(Vector3(0.0, 0.0, INF), _held_floor + 1)
	assert_false(_observer.release_ready(30), "1452 infinite positive Z cannot qualify held displacement")
