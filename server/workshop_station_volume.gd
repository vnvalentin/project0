extends Area3D
class_name WorkshopStationVolume
## Supported world-yard box. Cached overlap alone never grants permission.

const Contract: Script = preload("res://server/workshop_station_contract.gd")
const Sensor: Script = preload("res://server/workshop_character_sensor.gd")

var _station: WorkshopStationContract.StationValue
var _shape: CollisionShape3D
var _created_frame: int = -1


func _init(value: WorkshopStationContract.StationValue) -> void:
	top_level = true
	collision_layer = 0
	collision_mask = 1
	_shape = CollisionShape3D.new()
	if value != null:
		var parsed: Dictionary = Contract.parse_server_descriptor(value.to_dict())
		if parsed["outcome"] == "ok":
			_station = parsed["station"]
	if _station != null:
		position = (_station.bounds_min + _station.bounds_max) * 0.5
		var box: BoxShape3D = BoxShape3D.new()
		box.size = _station.bounds_max - _station.bounds_min
		_shape.shape = box
		_shape.disabled = not _station.active
		monitoring = _station.active
	else:
		monitoring = false
	add_child(_shape)


func _ready() -> void:
	_created_frame = Engine.get_physics_frames()


func validate_character(body: Node3D) -> Dictionary:
	if _station == null or not _station.active:
		return {"outcome": "inactive_station"}
	if not _valid_geometry():
		return {"outcome": "invalid_station_binding"}
	if not is_instance_valid(body) or not body is Sensor or body.is_queued_for_deletion():
		return {"outcome": "invalid_character_binding"}
	var actor: Dictionary = body.current_actor()
	if actor["outcome"] != "ok":
		return actor
	if body.get_world_3d() != get_world_3d():
		return {"outcome": "invalid_character_binding"}
	if not _station.contains_center(actor["position"]):
		return {"outcome": "outside_station"}
	if not actor["settled"] or Engine.get_physics_frames() <= _created_frame:
		return {"outcome": "physics_not_settled"}
	if not overlaps_body(body):
		return {"outcome": "outside_station"}
	return actor


func station_snapshot() -> Dictionary:
	return {} if _station == null else _station.to_dict()


func _valid_geometry() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and top_level \
		and global_basis == Basis.IDENTITY and global_position == (_station.bounds_min + _station.bounds_max) * 0.5 \
		and collision_layer == 0 and collision_mask == 1 and monitoring \
		and is_instance_valid(_shape) and _shape.get_parent() == self and not _shape.disabled \
		and _shape.transform == Transform3D.IDENTITY and _shape.shape is BoxShape3D \
		and _shape.shape.size == _station.bounds_max - _station.bounds_min and get_child_count() == 1
