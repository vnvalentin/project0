extends SceneTree

const SCENARIO: String = "character-sheet-v1"
const FIELDS: Array[String] = ["STR", "DEX", "CON", "INT", "WIS", "CHA", "KineticVolume", "KineticControl", "KineticOutput", "BaseHP", "BaseStamina"]
const GROUPS: Array[String] = ["Vessel Attributes", "Kinetic Flow", "Biological Pools"]

var _output_path: String = ""
var _failures: Array[String] = []
var _network: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		_failures.append("expected one output path")
	else:
		_output_path = arguments[0]
		await _exercise_character_sheet()
	_write_result()
	quit(0 if _failures.is_empty() else 1)


func _exercise_character_sheet() -> void:
	var gameplay: Node = load("res://client/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	current_scene = gameplay
	await process_frame
	await process_frame
	_network = root.get_node_or_null("NetworkClient")
	_check(_network != null, "NetworkClient autoload exists")
	if _network == null:
		gameplay.queue_free()
		return

	var toggle: Button = gameplay.get_node_or_null("UI/CharacterSheetToggle") as Button
	var panel: Control = gameplay.get_node_or_null("UI/CharacterSheetPanel") as Control
	_check(toggle != null and panel != null, "Character Sheet toggle and panel exist")
	if toggle == null or panel == null:
		gameplay.queue_free()
		return

	_check(not panel.visible, "Character Sheet starts closed")
	toggle.emit_signal("pressed")
	_check(panel.visible, "toggle opens Character Sheet")
	var snapshot: Dictionary = _snapshot(10.0)
	_network.set("latest_authoritative_stats", snapshot)
	_network.authoritative_stats_changed.emit(snapshot)
	await process_frame
	_check_rendered(panel, snapshot)

	var scroll: ScrollContainer = panel.get_node_or_null("StatsScroll") as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 17
	toggle.emit_signal("pressed")
	_check(not panel.visible, "toggle closes Character Sheet")
	toggle.emit_signal("pressed")
	_check(panel.visible, "toggle reopens Character Sheet")
	_check_rendered(panel, snapshot)
	if scroll != null:
		_check(scroll.scroll_vertical == 17, "reopen preserves scroll offset")

	var rejected: Dictionary = {}
	_network.authoritative_stats_changed.emit(rejected)
	await process_frame
	_check_rendered(panel, snapshot)
	_check(panel.get_node_or_null("StatsScroll/StatsContent") != null, "rendered projection remains present after rejected snapshot")
	gameplay.queue_free()


func _snapshot(offset: float) -> Dictionary:
	return {"stats": {
		"STR": 10.0 + offset, "DEX": 11.0 + offset, "CON": 12.0 + offset,
		"INT": 13.0 + offset, "WIS": 14.0 + offset, "CHA": 15.0 + offset,
		"KineticVolume": 16.0 + offset, "KineticControl": 17.0 + offset,
		"KineticOutput": 18.0 + offset, "BaseHP": 244.0 + offset, "BaseStamina": 215.0 + offset,
	}}


func _check_rendered(panel: Control, snapshot: Dictionary) -> void:
	var content: VBoxContainer = panel.get_node_or_null("StatsScroll/StatsContent") as VBoxContainer
	_check(content != null, "stats content exists")
	if content == null:
		return
	for group: String in GROUPS:
		_check(_find_label(content, group), "group rendered: %s" % group)
	for field: String in FIELDS:
		var expected: String = "%.1f" % float(snapshot["stats"][field])
		_check(_find_label(content, "%s: %s" % [field_display_name(field), expected]), "field parity: %s" % field)


func _find_label(content: VBoxContainer, text: String) -> bool:
	for child: Node in content.get_children():
		if child is Label and (child as Label).text == text:
			return true
	return false


func field_display_name(field: String) -> String:
	return {"KineticVolume": "Kinetic Volume", "KineticControl": "Kinetic Control", "KineticOutput": "Kinetic Output", "BaseHP": "Base HP", "BaseStamina": "Base Stamina"}.get(field, field)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _write_result() -> void:
	if _output_path.is_empty():
		return
	var file: FileAccess = FileAccess.open(_output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"scenario": SCENARIO, "status": "passed" if _failures.is_empty() else "failed", "failures": _failures, "field_count": FIELDS.size(), "group_count": GROUPS.size()}))
		file.close()