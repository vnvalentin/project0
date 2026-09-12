extends Label
## Slice 019: shows the local player's server-assigned starting-town house id
## in the HUD. Cosmetic, client-only — the server owns the allocation; this
## just presents what it reports. See docs/slices/019-player-house-allocation.md.


func _ready() -> void:
	visible = false
	text = ""
	NetworkClient.assigned_house_received.connect(_on_assigned_house_received)


func _on_assigned_house_received(house_id: String) -> void:
	text = "Your house: %s" % house_id
	visible = true
