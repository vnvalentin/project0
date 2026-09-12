extends Camera3D
## Fixed 3/4 isometric-style camera for the gameplay scene. Keeps its
## isometric offset and look angle, but re-centers on the local Player each
## physics tick so the player stays framed as it moves.

## Offset from the local Player's position that preserves the original
## fixed isometric angle (was a fixed world position looking at the origin).
const CAMERA_OFFSET: Vector3 = Vector3(10, 10, 10)

var _follow_target: Node3D = null


func _ready() -> void:
	global_position = CAMERA_OFFSET
	make_current()
	look_at(Vector3.ZERO, Vector3.UP)

	var parent_node: Node = get_parent()
	if parent_node != null:
		var player: Node = parent_node.get_node_or_null("Player")
		if player is Node3D:
			_follow_target = player as Node3D


func _physics_process(_delta: float) -> void:
	if _follow_target == null:
		return

	global_position = _follow_target.global_position + CAMERA_OFFSET
	look_at(_follow_target.global_position, Vector3.UP)
