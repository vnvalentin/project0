extends GutTest
## #1452 behavioral RED at the fixture release-policy seam.
## ServerPlayerState is real; relaying position_updated through the public
## NetworkClient receive/signal method is direct simulation, not wire delivery.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const MovementObservationScript: Script = preload("res://tests/fixtures/prediction_movement_observation.gd")
const STEP_DELTA: float = 1.0 / 60.0
const OWNER_PEER: int = 1

var _network_client: Node
var _previous_network_name: StringName = &""
var _state: Node3D
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
