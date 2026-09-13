extends Node3D
## Slice 033: purely cosmetic client representation of one living
## server-authoritative monster (server/server_monster_state.gd via
## server/server_monster_manager.gd). A distinct instance of this script/scene
## is spawned per target_id by client/network_client.gd
## (spawn_monster_representation), named by that target_id, and never shared
## between two different monsters — mirrors client/remote_player.gd's
## per-peer instancing. Smooths toward each incoming authoritative position
## snapshot the same bounded way client/remote_player.gd does, so ordinary
## network jitter does not read as a teleport. Reacts to the existing
## authoritative CombatEvent.HIT/DEATH broadcast
## (NetworkClient.combat_event_received) for its own target_id only, mirroring
## client/target_dummy.gd's hit-flash reaction, plus a brief death reaction
## before freeing itself. This node never decides a hit, death, or respawn —
## it only renders state the server has already computed and broadcast. See
## docs/slices/033-client-monster-replication-and-rendering.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

## Bounded, non-tuning presentation constant: how long the hit-reaction
## flash/wobble lasts. Purely cosmetic — has no effect on server state.
const HIT_REACTION_DURATION_SEC: float = 0.5

## Bounded, non-tuning presentation constant: how long the death reaction
## plays before this node frees itself. Purely cosmetic.
const DEATH_REACTION_DURATION_SEC: float = 0.4

## Must match the target_id (ServerMonsterManager spawn_id) the server
## broadcasts for the corresponding living monster. Set once, immediately
## after instantiation, by network_client.gd's spawn_monster_representation().
@export var target_id: String = ""

var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false

var _mesh_instance: MeshInstance3D = null
var _base_material: StandardMaterial3D = null
var _original_color: Color = Color(0.75, 0.15, 0.15, 1.0)
var _hit_reaction_time_remaining: float = 0.0

var _dying: bool = false
var _death_reaction_time_remaining: float = 0.0


func _ready() -> void:
	_target_position = position
	_mesh_instance = get_node_or_null("MeshInstance3D")
	if _mesh_instance != null:
		var mat: Material = _mesh_instance.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			# Duplicate material so this instance doesn't mutate the shared resource permanently
			_base_material = mat.duplicate() as StandardMaterial3D
			_mesh_instance.set_surface_override_material(0, _base_material)
			_original_color = _base_material.albedo_color
	NetworkClient.combat_event_received.connect(_on_combat_event_received)


## Public seam: binds this node to the specific monster target_id it
## represents. Called once, immediately after instantiation, by
## network_client.gd's spawn_monster_representation().
func set_target_id(new_target_id: String) -> void:
	target_id = new_target_id


## Public seam: updates the authoritative position this node smooths toward.
## Called by network_client.gd's receive_monster_position().
func set_target_position(new_position: Vector3) -> void:
	_target_position = new_position
	_has_target = true


func _physics_process(delta: float) -> void:
	if _dying:
		_advance_death_reaction(delta)
		return

	if _hit_reaction_time_remaining > 0.0:
		_advance_hit_reaction(delta)

	if not _has_target:
		return

	if position.distance_to(_target_position) > NetworkConfigScript.NETWORKED_PLAYER_SNAP_DISTANCE:
		position = _target_position
		return

	position = position.move_toward(_target_position, NetworkConfigScript.NETWORKED_PLAYER_SMOOTH_SPEED * delta)


func _advance_hit_reaction(delta: float) -> void:
	_hit_reaction_time_remaining -= delta
	var reaction_progress: float = clampf(_hit_reaction_time_remaining / HIT_REACTION_DURATION_SEC, 0.0, 1.0)
	rotation.y = sin(reaction_progress * TAU * 2.0) * 0.2 * reaction_progress
	if _base_material != null:
		_base_material.albedo_color = _original_color.lerp(Color.WHITE, reaction_progress)

	if _hit_reaction_time_remaining <= 0.0:
		rotation.y = 0.0
		if _base_material != null:
			_base_material.albedo_color = _original_color


func _advance_death_reaction(delta: float) -> void:
	_death_reaction_time_remaining -= delta
	var progress: float = clampf(_death_reaction_time_remaining / DEATH_REACTION_DURATION_SEC, 0.0, 1.0)
	scale = Vector3.ONE * progress
	if _death_reaction_time_remaining <= 0.0:
		queue_free()


func _on_combat_event_received(kind: String, _attacker_peer_id: int, event_target_id: String, _impact_position: Vector3, _server_tick: int) -> void:
	if event_target_id != target_id:
		return
	if kind == CombatContractsScript.COMBAT_EVENT_HIT:
		_hit_reaction_time_remaining = HIT_REACTION_DURATION_SEC
	elif kind == CombatContractsScript.COMBAT_EVENT_DEATH:
		_dying = true
		_death_reaction_time_remaining = DEATH_REACTION_DURATION_SEC
