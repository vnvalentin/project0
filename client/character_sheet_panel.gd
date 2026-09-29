extends PanelContainer
## Experiment 1 for Epic #1294: read-only Character Sheet projection.

const GROUPS: Array[Dictionary] = [
	{"title": "Vessel Attributes", "fields": ["STR", "DEX", "CON", "INT", "WIS", "CHA"]},
	{"title": "Kinetic Flow", "fields": ["KineticVolume", "KineticControl", "KineticOutput"]},
	{"title": "Biological Pools", "fields": ["BaseHP", "BaseStamina"]},
]

var _snapshot: Dictionary = {}
var _scroll: ScrollContainer
var _content: VBoxContainer


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(300, 420)
	position = Vector2(520, 24)
	_snapshot = NetworkClient.latest_authoritative_stats.duplicate(true)
	NetworkClient.authoritative_stats_changed.connect(_on_stats_changed)
	_build_content()
	_render()


func _build_content() -> void:
	_scroll = ScrollContainer.new()
	_scroll.name = "StatsScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "StatsContent"
	_content.add_theme_constant_override("separation", 6)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)


func toggle_panel() -> void:
	visible = not visible


func _on_stats_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_render()


func _render() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Character Sheet"
	title.add_theme_font_size_override("font_size", 22)
	_content.add_child(title)
	for group: Dictionary in GROUPS:
		var heading := Label.new()
		heading.text = String(group["title"])
		heading.add_theme_font_size_override("font_size", 16)
		_content.add_child(heading)
		for field: String in group["fields"]:
			var value_label := Label.new()
			value_label.name = field
			value_label.text = "%s: %s" % [field_display_name(field), displayed_value(field)]
			_content.add_child(value_label)


func field_display_name(field: String) -> String:
	return {
		"KineticVolume": "Kinetic Volume",
		"KineticControl": "Kinetic Control",
		"KineticOutput": "Kinetic Output",
		"BaseHP": "Base HP",
		"BaseStamina": "Base Stamina",
	}.get(field, field)


func displayed_value(field: String) -> String:
	if not _snapshot.has("stats") or not (_snapshot["stats"] is Dictionary):
		return "—"
	if not (_snapshot["stats"] as Dictionary).has(field):
		return "—"
	return "%.1f" % float((_snapshot["stats"] as Dictionary)[field])