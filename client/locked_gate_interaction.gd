extends Node3D
## M0.4 client seam for the visible locked gate. This node submits only the
## human-selected verb and renders the server's accepted/rejected resolution.
## Slice 1349: once the gate is known unlocked (Canon overlay or an accepted
## unlock) the same input requests `open`; an accepted open clears the local
## gate colliders so predicted movement matches the server's opened collision.

const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")

const SECTOR_ID: String = "starting_town_hub"
const STRUCTURE_ID: String = "gate_01"
const SECTOR_GEOMETRY_PATH: String = "../SectorGeometry"
const OPENED_REASONS: PackedStringArray = ["opened", "already_open"]

var submit_intent: Callable = Callable()
var _next_sequence: int = 0
var _pending_sequence: int = -1
var _unlocked: bool = false
var _opened: bool = false
var _status_label: Label = null
var _gate_mesh: MeshInstance3D = null


func _ready() -> void:
	_status_label = get_node_or_null("../UI/GateStatus") as Label
	_gate_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not submit_intent.is_valid():
		submit_intent = NetworkClient.submit_environmental_interaction_intent
	NetworkClient.environmental_interaction_resolution_received.connect(apply_resolution)
	NetworkClient.sector_blueprint_received.connect(_on_sector_blueprint_received)
	apply_blueprint(NetworkClient.latest_sector_blueprint())


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		request_interaction()


func is_unlocked() -> bool:
	return _unlocked


func is_opened() -> bool:
	return _opened


## Submits the next verb for the gate; returns the sent intent or {} when none was sent.
func request_interaction() -> Dictionary:
	if _pending_sequence >= 0 or _opened:
		return {}
	var player: Node3D = get_node_or_null("../Player") as Node3D
	if player == null:
		return {}
	var sequence: int = _next_sequence
	_next_sequence += 1
	_pending_sequence = sequence
	var target_guid: String = CanonEntityGuidScript.derive(SECTOR_ID, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, STRUCTURE_ID)
	var verb: String = InteractionScript.VERB_OPEN if _unlocked else InteractionScript.VERB_LOCK_PICK
	var intent: Dictionary = InteractionScript.build_intent(SECTOR_ID, target_guid, verb, 0, -player.global_transform.basis.z, sequence)
	_set_status("Gate: requesting %s..." % verb)
	submit_intent.call(intent)
	return intent


## Reads the gate's unlocked flag from a presented hub blueprint (server-built, Canon overlay applied).
func apply_blueprint(blueprint: Dictionary) -> void:
	if String(blueprint.get("sector_id", "")) != SECTOR_ID:
		return
	for structure: Variant in blueprint.get("structures", []):
		if structure is Dictionary and String(structure.get("structure_id", "")) == STRUCTURE_ID and bool(structure.get("unlocked", false)):
			_mark_unlocked("Gate: unlocked (closed) - press F to open")
	if _opened:
		_set_gate_colliders_disabled(true)


func apply_resolution(resolution: Dictionary) -> void:
	if int(resolution.get("client_seq", -1)) != _pending_sequence:
		return
	_pending_sequence = -1
	var reason: String = String(resolution.get("reason", "unknown"))
	if resolution.get("status") == "accepted":
		if OPENED_REASONS.has(reason):
			_opened = true
			_unlocked = true
			_set_gate_colliders_disabled(true)
			_set_status("Gate: open")
			return
		_mark_unlocked("Gate: unlocked (%s execution, %d ticks) - press F to open" % [resolution.get("execution_profile", "standard"), int(resolution.get("execution_ticks", 0))])
		return
	_set_status("Gate: rejected (%s)" % reason)


func _on_sector_blueprint_received(sector_id: String, _outcome: String, _tiles: int, _structures: int) -> void:
	if sector_id == SECTOR_ID:
		apply_blueprint(NetworkClient.latest_sector_blueprint())


func _mark_unlocked(message: String) -> void:
	_unlocked = true
	_set_status(message)
	if _gate_mesh != null and _gate_mesh.material_override is StandardMaterial3D:
		(_gate_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.25, 0.8, 0.35, 1.0)


func _set_gate_colliders_disabled(disabled: bool) -> void:
	var bodies: Array[Node] = [self]
	var placeholder: Node = get_node_or_null("%s/Structure_%s" % [SECTOR_GEOMETRY_PATH, STRUCTURE_ID])
	if placeholder != null:
		bodies.append(placeholder)
	for body: Node in bodies:
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).set_deferred("disabled", disabled)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
