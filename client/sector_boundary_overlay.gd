extends Node3D

const WorldScaleScript: Script = preload("res://shared/world_scale.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

const STATE_UNEXPLORED: String = "unexplored"
const STATE_GENERATING: String = "generating"
const STATE_CANON: String = "Canon"
const EDGE_THICKNESS: float = 0.6
const EDGE_HEIGHT: float = 0.12

@export var player_path: NodePath = NodePath("../Player")
@export var label_path: NodePath = NodePath("../UI/SectorBoundaryLabel")

var current_sector_id: String = ""
var _current_state: String = STATE_UNEXPLORED
var _authoritative_sector_id: String = ""
var _canon_sector_ids: Dictionary = {}
var _player: Node3D = null
var _label: Label = null
var _boundary_material: StandardMaterial3D = null


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_label = get_node_or_null(label_path) as Label
	_build_boundary()
	visible = false
	if _label != null:
		_label.visible = false
	NetworkClient.authoritative_position_received.connect(_on_authoritative_position_received)
	NetworkClient.sector_blueprint_received.connect(_on_sector_blueprint_received)
	refresh_position()


func _process(_delta: float) -> void:
	refresh_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		if visible:
			hide_overlay()
		else:
			show_overlay()
		get_viewport().set_input_as_handled()


func show_overlay() -> void:
	visible = true
	if _label != null:
		_label.visible = true


func hide_overlay() -> void:
	visible = false
	if _label != null:
		_label.visible = false


func refresh_position() -> void:
	if _player == null:
		return
	var edge: float = WorldScaleScript.SECTOR_EDGE_UNITS
	var sector_x: int = floori(_player.global_position.x / edge)
	var sector_z: int = floori(_player.global_position.z / edge)
	var sector_id: String = "sector-%d-%d" % [sector_x, sector_z]
	if sector_id == current_sector_id:
		return
	current_sector_id = sector_id
	position = Vector3((sector_x + 0.5) * edge, 0.15, (sector_z + 0.5) * edge)
	_refresh_state()


func _build_boundary() -> void:
	_boundary_material = StandardMaterial3D.new()
	_boundary_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_boundary_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_boundary_material.albedo_color = Color(0.95, 0.7, 0.2, 0.9)
	_boundary_material.emission_enabled = true
	_boundary_material.emission = Color(0.95, 0.7, 0.2)

	var half_edge: float = WorldScaleScript.SECTOR_EDGE_UNITS * 0.5
	_add_edge("North", Vector3(0.0, 0.0, -half_edge), Vector3(WorldScaleScript.SECTOR_EDGE_UNITS, EDGE_HEIGHT, EDGE_THICKNESS))
	_add_edge("South", Vector3(0.0, 0.0, half_edge), Vector3(WorldScaleScript.SECTOR_EDGE_UNITS, EDGE_HEIGHT, EDGE_THICKNESS))
	_add_edge("West", Vector3(-half_edge, 0.0, 0.0), Vector3(EDGE_THICKNESS, EDGE_HEIGHT, WorldScaleScript.SECTOR_EDGE_UNITS))
	_add_edge("East", Vector3(half_edge, 0.0, 0.0), Vector3(EDGE_THICKNESS, EDGE_HEIGHT, WorldScaleScript.SECTOR_EDGE_UNITS))


func _add_edge(edge_name: String, edge_position: Vector3, size: Vector3) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var edge: MeshInstance3D = MeshInstance3D.new()
	edge.name = edge_name
	edge.position = edge_position
	edge.mesh = mesh
	edge.material_override = _boundary_material
	add_child(edge)


func _on_authoritative_position_received(authoritative_position: Vector3, _last_processed_sequence: int) -> void:
	_authoritative_sector_id = _sector_id_for_position(authoritative_position)
	if _authoritative_sector_id == current_sector_id:
		_refresh_state()


func _on_sector_blueprint_received(sector_id: String, outcome: String, _tile_count: int, _structure_count: int) -> void:
	if outcome != SectorBlueprintSchemaScript.OUTCOME_VALID:
		return
	_canon_sector_ids[sector_id] = true
	if sector_id == current_sector_id:
		_refresh_state()


func _refresh_state() -> void:
	if _canon_sector_ids.has(current_sector_id):
		_current_state = STATE_CANON
	elif current_sector_id == _authoritative_sector_id:
		_current_state = STATE_GENERATING
	else:
		_current_state = STATE_UNEXPLORED
	_update_presentation()


func _update_presentation() -> void:
	if _label != null:
		_label.text = "%s\n%s" % [current_sector_id, _current_state]
	var color: Color = Color(0.95, 0.7, 0.2, 0.9)
	if _current_state == STATE_GENERATING:
		color = Color(0.2, 0.8, 0.95, 0.9)
	elif _current_state == STATE_CANON:
		color = Color(0.35, 0.9, 0.45, 0.9)
	_boundary_material.albedo_color = color
	_boundary_material.emission = Color(color.r, color.g, color.b)


func _sector_id_for_position(world_position: Vector3) -> String:
	var edge: float = WorldScaleScript.SECTOR_EDGE_UNITS
	return "sector-%d-%d" % [floori(world_position.x / edge), floori(world_position.z / edge)]
