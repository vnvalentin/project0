extends "res://server/server_main.gd"


func _on_peer_connected(peer_id: int) -> void:
	super._on_peer_connected(peer_id)
	_peer.get_peer(peer_id).set_timeout(32, 1000, 5000)