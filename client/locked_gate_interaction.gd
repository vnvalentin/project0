extends Node3D
## M0.4 client seam for the visible locked gate. This node submits only the
## human-selected verb and renders the server's accepted/rejected resolution.

const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")

const SECTOR_ID: String = "starting_town_hub"
const STRUCTURE_ID: String = "gate_01"

var _next_sequence: int = 0
var _pending_sequence: int = -1
var _status_label: Label = null
var _gate_mesh: MeshInstance3D = null


func _ready() -> void:
	_status_label = get_node_or_null("../UI/GateStatus") as Label
	_gate_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	NetworkClient.environmental_interaction_resolution_received.connect(_on_resolution_received)


func _physics_process(_delta: float) -> void:
	if not Input.is_action_just_pressed("interact") or _pending_sequence >= 0:
		return
	var player: Node3D = get_node_or_null("../Player") as Node3D
	if player == null:
		return
	var sequence: int = _next_sequence
	_next_sequence += 1
	_pending_sequence = sequence
	var target_guid: String = CanonEntityGuidScript.derive(
		SECTOR_ID,
		CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE,
		STRUCTURE_ID
	)
	var intent: Dictionary = InteractionScript.build_intent(
		SECTOR_ID,
		target_guid,
		InteractionScript.VERB_LOCK_PICK,
		0,
		-player.global_transform.basis.z,
		sequence
	)
	_set_status("Gate: requesting authoritative interaction...")
	NetworkClient.submit_environmental_interaction_intent(intent)


func _on_resolution_received(resolution: Dictionary) -> void:
	if int(resolution.get("client_seq", -1)) != _pending_sequence:
		return
	_pending_sequence = -1
	if resolution.get("status") == "accepted":
		_set_status("Gate: unlocked (%s execution, %d ticks)" % [resolution.get("execution_profile", "standard"), int(resolution.get("execution_ticks", 0))])
		if _gate_mesh != null and _gate_mesh.material_override is StandardMaterial3D:
			(_gate_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.25, 0.8, 0.35, 1.0)
		return
	_set_status("Gate: rejected (%s)" % String(resolution.get("reason", "unknown")))


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message