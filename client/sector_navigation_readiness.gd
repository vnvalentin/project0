extends Node

signal completed(result: Dictionary)

var _result: Dictionary = {}
var _region: NavigationRegion3D
var _ingress: Vector3
var _target: Vector3
var _parent: Node3D
var _initial_child_count: int
var _checked: bool = false
var _empty_path_checks: int = 0

const MAX_EMPTY_PATH_CHECKS: int = 30


func configure(result: Dictionary, region: NavigationRegion3D, ingress: Vector3, target: Vector3, parent: Node3D, initial_child_count: int) -> void:
	_result = result
	_region = region
	_ingress = ingress
	_target = target
	_parent = parent
	_initial_child_count = initial_child_count


func _physics_process(_delta: float) -> void:
	if _checked or _region == null or not is_instance_valid(_region):
		return
	var map: RID = _region.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, _ingress, _target, true)
	if path.is_empty():
		_empty_path_checks += 1
		if _empty_path_checks < MAX_EMPTY_PATH_CHECKS:
			return
		if _parent != null and is_instance_valid(_parent):
			while _parent.get_child_count() > _initial_child_count:
				_parent.get_child(_parent.get_child_count() - 1).queue_free()
		_checked = true
		set_physics_process(false)
		return
	_result["path"] = path
	_result["navigation_ready"] = true
	_result["geometry_assembly_completed"] = true
	_result["completion_count"] = 1
	_checked = true
	completed.emit(_result)
	set_physics_process(false)
