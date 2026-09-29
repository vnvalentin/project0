extends Button
## Dedicated Character Sheet toggle control. It changes visibility only.

@export var panel_path: NodePath


func _ready() -> void:
	pressed.connect(_toggle_panel)


func _toggle_panel() -> void:
	var panel: Node = get_node_or_null(panel_path)
	if panel != null and panel.has_method("toggle_panel"):
		panel.toggle_panel()