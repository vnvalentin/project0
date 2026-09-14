extends Button

func _ready() -> void:
	pressed.connect(_on_logout_pressed)

func _on_logout_pressed() -> void:
	PlayerIdentity.clear_selected_character()
	get_tree().change_scene_to_file("res://client/character_gate.tscn")
