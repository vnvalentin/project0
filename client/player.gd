extends CharacterBody3D
## Player movement for the first playable slice, client-side-first for
## immediate responsiveness (see docs/adr/0001 for why the underlying
## movement authority for this node started fully client-side). Slice 005
## adds prediction/reconciliation on top of that unchanged responsive feel:
## this node still moves immediately from local input every tick with no
## wait on the network, but now also tags each input sample with a
## monotonically increasing sequence number, reports it to the server via
## NetworkClient, and — when the server's authoritative snapshot for this
## peer arrives — discards acknowledged samples and replays only the
## still-unacknowledged ones on top of the authoritative position. The server
## remains the sole owner of the authoritative position; this node's own
## position is a prediction that is corrected, never the source of truth.
## See docs/slices/005-prediction-reconciliation.md.

@export var move_speed: float = 5.0

## One recorded local input sample awaiting server acknowledgement.
class PendingInput:
	var sequence: int
	var intent: Vector2
	var delta: float

	func _init(p_sequence: int, p_intent: Vector2, p_delta: float) -> void:
		sequence = p_sequence
		intent = p_intent
		delta = p_delta

var _next_sequence: int = 0
var _pending_inputs: Array[PendingInput] = []


func _ready() -> void:
	NetworkClient.authoritative_position_received.connect(_on_authoritative_position_received)


func _physics_process(delta: float) -> void:
	var planar_input: Vector2 = get_planar_input()
	_apply_intent(planar_input, delta)
	move_and_slide()

	var sequence: int = _next_sequence
	_next_sequence += 1
	_pending_inputs.append(PendingInput.new(sequence, planar_input, delta))
	NetworkClient.submit_input_intent(planar_input, sequence)


## Public seam: reads the four directional input actions and returns a
## normalized-or-zero planar direction (x = right/left, y = forward/back).
func get_planar_input() -> Vector2:
	var input_vector: Vector2 = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	return input_vector


## Moves this node the same way the server integrates ServerPlayerState, so a
## replayed sample reproduces the server's own math exactly (same speed,
## same normalization rule, same per-sample delta).
func _apply_intent(planar_input: Vector2, delta: float) -> void:
	var direction: Vector3 = Vector3(planar_input.x, 0.0, planar_input.y)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	velocity.y = 0.0


## Reconciliation: called whenever the server's authoritative snapshot for
## this peer arrives. Discards every pending input the server has already
## processed (sequence <= last_processed_sequence), snaps this node to the
## authoritative position, then replays the remaining unacknowledged inputs
## on top of it so already-responded-to local input is not visually lost.
## Does not change server authority — the server's position is always the
## replay's starting point, never overridden by the client.
func _on_authoritative_position_received(authoritative_position: Vector3, last_processed_sequence: int) -> void:
	var still_pending: Array[PendingInput] = []
	for pending_input: PendingInput in _pending_inputs:
		if pending_input.sequence > last_processed_sequence:
			still_pending.append(pending_input)
	_pending_inputs = still_pending

	position = authoritative_position
	velocity = Vector3.ZERO

	for pending_input: PendingInput in _pending_inputs:
		_apply_intent(pending_input.intent, pending_input.delta)
		move_and_slide()
