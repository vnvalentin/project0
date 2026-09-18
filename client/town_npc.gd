extends Node3D
## Slice 131: purely cosmetic client representation of one living
## server-authoritative town NPC (server/server_town_npc_state.gd via
## server/server_town_npc_manager.gd). A distinct instance is spawned per npc_id
## by client/network_client.gd (spawn_town_npc_representation), named by that
## npc_id, and never shared between two NPCs — mirroring client/monster.gd. It
## smooths toward each incoming authoritative position the same bounded way, so
## ordinary network jitter does not read as a teleport. This node never decides
## movement, spawning, or removal — it only renders state the server broadcast.
## Built procedurally (no scene file) so it stays self-contained and testable.

## Smoothing rate (units/sec fraction per second) toward the latest authoritative
## position — purely cosmetic, no effect on server state.
const SMOOTHING_PER_SECOND: float = 12.0

@export var npc_id: String = ""

var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false


func _ready() -> void:
	_target_position = position
	if get_node_or_null("MeshInstance3D") == null:
		_build_mesh()


func _build_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	mesh_instance.mesh = capsule
	var material := StandardMaterial3D.new()
	# Distinct from players (green) and monsters (red): town NPCs are teal.
	material.albedo_color = Color(0.15, 0.6, 0.6, 1.0)
	mesh_instance.set_surface_override_material(0, material)
	add_child(mesh_instance)


## Public seam: binds this node to the npc_id it represents. Called once,
## immediately after instantiation, by network_client.gd.
func set_npc_id(p_npc_id: String) -> void:
	npc_id = p_npc_id


## Public seam: records the latest authoritative position to smooth toward.
func set_target_position(p_position: Vector3) -> void:
	_target_position = p_position
	_has_target = true


func _process(delta: float) -> void:
	if not _has_target:
		return
	var t: float = clampf(SMOOTHING_PER_SECOND * delta, 0.0, 1.0)
	position = position.lerp(_target_position, t)
