extends CharacterBody3D
class_name WorkshopCharacterSensor
## Owned query body; current identity comes only from the admitted state owner.

const AdmittedScript: Script = preload("res://server/admitted_player_state.gd")
const SENSOR_SIZE: Vector3 = Vector3(0.1, 1.8, 0.1)

signal invalidated

var _source: Node
var _bound_identity: Dictionary = {}
var _shape: CollisionShape3D
var _pose_changed_frame: int = -1
var _was_bound: bool = false


func _init() -> void:
	top_level = true
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = SENSOR_SIZE
	_shape.shape = box
	add_child(_shape)


func bind_admitted_player(player: Node) -> Dictionary:
	if _was_bound or not is_inside_tree() or not is_instance_valid(player) or not player is AdmittedScript:
		return {"outcome": "invalid_character_binding"}
	var identity: Dictionary = player.current_admitted_identity()
	if identity["outcome"] != "ok":
		return identity
	_source = player
	_bound_identity = identity.duplicate(true)
	_was_bound = true
	_pose_changed_frame = Engine.get_physics_frames()
	_source.position_updated.connect(_on_position_updated)
	_source.tree_exiting.connect(teardown)
	return current_actor()


func current_actor() -> Dictionary:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(_source):
		return {"outcome": "not_admitted"}
	var identity: Dictionary = _source.current_admitted_identity()
	if identity["outcome"] != "ok" or identity != _bound_identity:
		teardown()
		return {"outcome": "not_admitted"}
	if not _valid_geometry():
		return {"outcome": "invalid_character_binding"}
	var authoritative_position: Vector3 = _source.position
	if not is_finite(authoritative_position.x) or not is_finite(authoritative_position.y) or not is_finite(authoritative_position.z):
		return {"outcome": "invalid_character_position"}
	if global_position != authoritative_position:
		global_position = authoritative_position
		_pose_changed_frame = Engine.get_physics_frames()
	var actor: Dictionary = identity.duplicate(true)
	actor["position"] = authoritative_position
	actor["settled"] = Engine.get_physics_frames() > _pose_changed_frame
	actor["source_instance_id"] = _source.get_instance_id()
	actor["sensor_instance_id"] = get_instance_id()
	return actor


func teardown() -> void:
	if is_instance_valid(_source):
		if _source.position_updated.is_connected(_on_position_updated):
			_source.position_updated.disconnect(_on_position_updated)
		if _source.tree_exiting.is_connected(teardown):
			_source.tree_exiting.disconnect(teardown)
	_source = null
	_bound_identity.clear()
	invalidated.emit()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_source):
		if _source.position_updated.is_connected(_on_position_updated):
			_source.position_updated.disconnect(_on_position_updated)
		if _source.tree_exiting.is_connected(teardown):
			_source.tree_exiting.disconnect(teardown)
	_source = null
	_bound_identity.clear()


func _physics_process(_delta: float) -> void:
	if _was_bound:
		current_actor()


func _on_position_updated(_peer_id: int, _updated_position: Vector3) -> void:
	current_actor()


func _valid_geometry() -> bool:
	return top_level and global_basis == Basis.IDENTITY and collision_layer == 1 and collision_mask == 0 \
		and is_instance_valid(_shape) and _shape.get_parent() == self and not _shape.disabled \
		and _shape.transform == Transform3D.IDENTITY and _shape.shape is BoxShape3D \
		and _shape.shape.size == SENSOR_SIZE and get_child_count() == 1
