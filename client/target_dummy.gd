extends Node3D
## Slice 012: client-side visual feedback for the server-owned stationary
## TargetDummy (server/server_main.gd spawns the authoritative version; this
## node is a purely cosmetic client representation with the same target_id).
## Listens for NetworkClient's replicated CombatEvent.HIT and, when this
## dummy's target_id matches, plays a brief flash/wobble reaction. Never
## decides whether a hit occurred — it only reacts to an authoritative event
## already confirmed by the server. See
## docs/slices/012-authoritative-melee-strike.md.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

## Bounded, non-tuning presentation constant: how long the hit-reaction
## flash/wobble lasts (0.5 seconds). Purely cosmetic — has no effect on server state.
const HIT_REACTION_DURATION_SEC: float = 0.5

## Must match the target_id server/server_main.gd registers for the
## corresponding server-owned dummy (TARGET_DUMMY_ID).
@export var target_id: String = "target_dummy_0"

var _mesh_instance: MeshInstance3D = null
var _base_material: StandardMaterial3D = null
var _original_color: Color = Color(0.6, 0.6, 0.6, 1.0)
var _hit_reaction_time_remaining: float = 0.0


func _ready() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D")
	if _mesh_instance != null:
		var mat: Material = _mesh_instance.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			# Duplicate material so this instance doesn't mutate shared resource permanently
			_base_material = mat.duplicate() as StandardMaterial3D
			_mesh_instance.set_surface_override_material(0, _base_material)
			_original_color = _base_material.albedo_color
	NetworkClient.combat_event_received.connect(_on_combat_event_received)


func _process(delta: float) -> void:
	if _hit_reaction_time_remaining <= 0.0:
		return

	_hit_reaction_time_remaining -= delta
	var reaction_progress: float = clampf(_hit_reaction_time_remaining / HIT_REACTION_DURATION_SEC, 0.0, 1.0)
	rotation.y = sin(reaction_progress * TAU * 2.0) * 0.2 * reaction_progress
	if _base_material != null:
		_base_material.albedo_color = _original_color.lerp(Color.WHITE, reaction_progress)

	if _hit_reaction_time_remaining <= 0.0:
		rotation.y = 0.0
		if _base_material != null:
			_base_material.albedo_color = _original_color


func _on_combat_event_received(kind: String, _attacker_peer_id: int, hit_target_id: String, _impact_position: Vector3, _server_tick: int) -> void:
	if kind != CombatContractsScript.COMBAT_EVENT_HIT:
		return
	if hit_target_id != target_id:
		return
	_hit_reaction_time_remaining = HIT_REACTION_DURATION_SEC
