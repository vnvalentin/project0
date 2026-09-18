extends Label
## Displays the NetworkClient autoload's connection status in the gameplay
## scene and starts the connection attempt on scene entry. Public seam for
## Slice 002's connection proof: docs/slices/002-client-connects-to-server.md.


func _ready() -> void:
	NetworkClient.connection_status_changed.connect(_on_status_changed)
	_on_status_changed(NetworkClient.status)
	# Slice 044: login owns the authenticated connection; gameplay inherits it.
	if not NetworkClient.status.begins_with("connected"):
		NetworkClient.connect_to_server(PlayerIdentity.target_host)
	call_deferred("_replay_pending_sector_blueprint")


func _replay_pending_sector_blueprint() -> void:
	NetworkClient.render_pending_player_representations()
	NetworkClient.render_pending_remote_players()
	NetworkClient.render_pending_sector_blueprint()
	NetworkClient.render_pending_monsters()
	NetworkClient.render_pending_town_npcs()


func _on_status_changed(status: String) -> void:
	text = "Server: %s" % status
	add_theme_color_override("font_color", _color_for_status(status))


## Maps a NetworkClient status string to a readable indicator color.
## Uses prefix checks since NetworkClient appends detail, e.g.
## "connected: player spawned" or "failed: connection refused".
## Falls back to neutral gray for any status this UI doesn't recognize.
func _color_for_status(status: String) -> Color:
	if status.begins_with("connected"):
		return Color(0.35, 0.85, 0.35, 1)
	if status == "connecting":
		return Color(0.9, 0.75, 0.25, 1)
	if status.begins_with("failed") or status == "disconnected":
		return Color(0.9, 0.35, 0.35, 1)
	return Color(0.85, 0.85, 0.85, 1)
