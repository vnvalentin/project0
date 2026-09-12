extends GutTest
## Public-seam unit test for Slice 019's assigned-house HUD label
## (client/assigned_house_label.gd). Tests the display handler in isolation
## (not added to the tree, so its _ready NetworkClient wiring does not run) —
## the wiring is a single autoload signal connection covered by the full-suite
## scene load. See docs/slices/019-player-house-allocation.md.

const AssignedHouseLabelScript: Script = preload("res://client/assigned_house_label.gd")


func _label() -> Label:
	var label: Label = Label.new()
	label.set_script(AssignedHouseLabelScript)
	autofree(label)
	return label


func test_shows_the_assigned_house_id() -> void:
	var label: Label = _label()
	label._on_assigned_house_received("house_03")
	assert_true(label.visible, "receiving an assigned house makes the label visible")
	assert_eq(label.text, "Your house: house_03", "the assigned house id is shown")
