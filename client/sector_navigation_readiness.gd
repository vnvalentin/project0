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
var _coverage: RefCounted
var _owned_map: RID

const MAX_EMPTY_PATH_CHECKS: int = 30


func configure(result: Dictionary, region: NavigationRegion3D, ingress: Vector3, target: Vector3, parent: Node3D, initial_child_count: int, coverage: RefCounted = null) -> void:
	_result = result
	_region = region
	_ingress = ingress
	_target = target
	_parent = parent
	_initial_child_count = initial_child_count
	_coverage = coverage
	if _coverage != null:
		_owned_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(_owned_map, NavigationServer3D.map_get_cell_size(region.get_navigation_map()))
		NavigationServer3D.map_set_active(_owned_map, true)
		_region.set_navigation_map(_owned_map)


func _exit_tree() -> void:
	if _owned_map.is_valid():
		if is_instance_valid(_region):
			_region.set_navigation_map(RID())
		NavigationServer3D.free_rid(_owned_map)
		_owned_map = RID()


func _physics_process(_delta: float) -> void:
	if _checked or _region == null or not is_instance_valid(_region):
		return
	var map: RID = _region.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, _ingress, _target, true)
	if path.is_empty() or not _path_is_covered(path):
		_empty_path_checks += 1
		if _empty_path_checks < MAX_EMPTY_PATH_CHECKS:
			return
		if _parent != null and is_instance_valid(_parent):
			for child: Node in _parent.get_children().slice(_initial_child_count):
				child.queue_free()
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


func _path_is_covered(path: PackedVector3Array) -> bool:
	if _coverage == null:
		return true
	if Vector2(path[0].x, path[0].z).distance_to(Vector2(_ingress.x, _ingress.z)) > 0.05:
		return false
	if Vector2(path[-1].x, path[-1].z).distance_to(Vector2(_target.x, _target.z)) > 0.05:
		return false
	for index: int in range(path.size()):
		if not _coverage.contains_world(path[index]):
			return false
		if index == 0:
			continue
		var steps: int = maxi(1, ceili(path[index - 1].distance_to(path[index]) / 0.2))
		for step: int in range(1, steps):
			if not _coverage.contains_world(path[index - 1].lerp(path[index], float(step) / steps)):
				return false
	return true
