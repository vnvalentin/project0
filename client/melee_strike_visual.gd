extends Node3D
## Slice 013: purely cosmetic client-side melee strike indicator. Draws a
## bright cyan/white line extending archetype.reach_yards (2.0 yd) in front of
## whichever Node3D this component is attached under, visible only while the
## owning attack is in its ACTIVE phase, and hidden the rest of the time. This
## node never reads or writes any authoritative state — it only reacts to a
## caller-driven show()/hide() timeline (see start_swing()/end_swing() below),
## matching client/target_dummy.gd's "render only what the caller/server has
## already decided" separation of concerns. See
## docs/slices/013-melee-strike-visual-indicator.md.
##
## Attach as a child of a Player/RemotePlayer node so the line renders in that
## parent's local space: the line always points down -Z (the parent's forward,
## matching CombatContracts' -global_transform.basis.z convention), so it
## automatically follows the parent's facing without this node tracking
## rotation itself.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

const STRIKE_COLOR: Color = Color(0.4, 1.0, 1.0, 1.0)
const LINE_WIDTH: float = 0.05
const FORWARD_HEIGHT_OFFSET: float = 0.9

var _mesh_instance: MeshInstance3D = null


func _ready() -> void:
	visible = false
	_mesh_instance = get_node("StrikeLineMesh") as MeshInstance3D


## Public seam: shows the strike line. Called by the owning Player/RemotePlayer
## script when its tracked attack phase enters ACTIVE.
func start_swing() -> void:
	visible = true


## Public seam: hides the strike line. Called once the tracked attack phase
## leaves ACTIVE (RECOVERY or IDLE), so the line never lingers past the swing
## that produced it.
func end_swing() -> void:
	visible = false
