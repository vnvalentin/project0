extends GutTest
## Slice 1349: the client gate requests `open` once it is known unlocked and an
## accepted open clears both local gate colliders so prediction can traverse.

const GateScript: Script = preload("res://client/locked_gate_interaction.gd")

var _root: Node3D
var _gate: Node3D
var _sent: Array[Dictionary] = []


func before_each() -> void:
	_sent.clear()
	_root = Node3D.new()
	var player: Node3D = Node3D.new()
	player.name = "Player"
	_root.add_child(player)
	var geometry: Node3D = Node3D.new()
	geometry.name = "SectorGeometry"
	_root.add_child(geometry)
	geometry.add_child(_body("Structure_gate_01"))
	_gate = _body("LockedGate")
	_gate.set_script(GateScript)
	_gate.submit_intent = func(intent: Dictionary) -> void: _sent.append(intent)
	_root.add_child(_gate)
	add_child_autofree(_root)


func _body(body_name: String) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	return body


func _hub(unlocked: bool) -> Dictionary:
	var gate: Dictionary = {"structure_id": "gate_01", "kind": "locked_gate", "x": 0, "y": -5, "facing_degrees": 0.0}
	if unlocked:
		gate["unlocked"] = true
	return {"sector_id": "starting_town_hub", "structures": [gate]}


func _colliders_disabled() -> Array:
	var placeholder: Node = _root.get_node("SectorGeometry/Structure_gate_01")
	return [(_gate.get_child(0) as CollisionShape3D).disabled, (placeholder.get_child(0) as CollisionShape3D).disabled]


func test_locked_gate_requests_lock_pick() -> void:
	assert_eq(_gate.request_interaction().get("verb"), "lock_pick")
	assert_eq(_sent.size(), 1)


func test_canon_unlocked_blueprint_makes_input_request_open() -> void:
	_gate.apply_blueprint(_hub(true))
	assert_true(_gate.is_unlocked(), "restored unlocked-but-closed state is read from the presented hub")
	assert_eq(_gate.request_interaction().get("verb"), "open")


func test_blueprints_for_other_sectors_or_locked_gate_do_not_unlock() -> void:
	_gate.apply_blueprint({"sector_id": "sector-0-0", "structures": [{"structure_id": "gate_01", "unlocked": true}]})
	_gate.apply_blueprint(_hub(false))
	assert_false(_gate.is_unlocked())


func test_accepted_unlock_then_input_requests_open() -> void:
	var unlock: Dictionary = _gate.request_interaction()
	_gate.apply_resolution({"status": "accepted", "reason": "ok", "client_seq": unlock["client_seq"]})
	assert_eq(_gate.request_interaction().get("verb"), "open")


func test_accepted_open_disables_both_local_gate_colliders() -> void:
	_gate.apply_blueprint(_hub(true))
	var request: Dictionary = _gate.request_interaction()
	_gate.apply_resolution({"status": "accepted", "reason": "opened", "client_seq": request["client_seq"], "structure_cell": [0, -5]})
	await wait_physics_frames(2)
	assert_true(_gate.is_opened())
	assert_eq(_colliders_disabled(), [true, true], "scene gate and translated placeholder no longer block prediction")


func test_already_open_also_clears_colliders() -> void:
	_gate.apply_blueprint(_hub(true))
	var request: Dictionary = _gate.request_interaction()
	_gate.apply_resolution({"status": "accepted", "reason": "already_open", "client_seq": request["client_seq"]})
	await wait_physics_frames(2)
	assert_eq(_colliders_disabled(), [true, true])


func test_rejected_open_keeps_gate_solid() -> void:
	_gate.apply_blueprint(_hub(true))
	var request: Dictionary = _gate.request_interaction()
	_gate.apply_resolution({"status": "rejected", "reason": "gate_locked", "client_seq": request["client_seq"]})
	await wait_physics_frames(2)
	assert_false(_gate.is_opened())
	assert_eq(_colliders_disabled(), [false, false])


func test_resolution_for_another_sequence_is_ignored() -> void:
	_gate.apply_blueprint(_hub(true))
	var request: Dictionary = _gate.request_interaction()
	_gate.apply_resolution({"status": "accepted", "reason": "opened", "client_seq": int(request["client_seq"]) + 7})
	await wait_physics_frames(2)
	assert_eq(_colliders_disabled(), [false, false])


func test_rerendered_placeholder_stays_open() -> void:
	_gate.apply_blueprint(_hub(true))
	var request: Dictionary = _gate.request_interaction()
	_gate.apply_resolution({"status": "accepted", "reason": "opened", "client_seq": request["client_seq"]})
	var geometry: Node = _root.get_node("SectorGeometry")
	var old: Node = geometry.get_node("Structure_gate_01")
	geometry.remove_child(old)
	old.free()
	geometry.add_child(_body("Structure_gate_01"))
	_gate.apply_blueprint(_hub(true))
	await wait_physics_frames(2)
	assert_eq(_colliders_disabled(), [true, true], "a re-presented hub does not restore the opened gate's collider")
