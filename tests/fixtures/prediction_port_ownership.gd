extends RefCounted

const LOOPBACK: String = "127.0.0.1"
const ERROR_BEGIN: String = "1447_PORT_ERROR_BEGIN:"
const ERROR_END: String = "1447_PORT_ERROR_END:"


func run() -> Dictionary:
	var result: Dictionary = {
		"schema_version": 1,
		"passed": false,
		"failure_code": "none",
		"probe_port_selected": null,
		"probe_closed_before_takeover": null,
		"takeover_held": null,
		"takeover_result": "NOT_OBSERVED",
		"released_port_rebound": null,
		"rebound_port_matches": null,
		"os_bound_port_positive": null,
		"duplicate_result": "NOT_OBSERVED",
		"listener_remained_active": null,
		"resources_released": null,
		"released_selected_port_rebound": null,
		"released_listener_port_rebound": null,
		"historical_cause": "UNKNOWN",
		"production_countermeasure": "NOT_OBSERVED",
	}
	var probe: PacketPeerUDP = PacketPeerUDP.new()
	var occupier: PacketPeerUDP = PacketPeerUDP.new()
	var takeover: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var rebound: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var listener: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var duplicate: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var selected_port: int = 0
	var listener_port: int = 0
	var sequence_complete: bool = false

	# A single pass lets every setup/result failure reach the same epilogue.
	while true:
		if probe.bind(0, LOOPBACK) != OK:
			result["failure_code"] = "probe_bind_failed"
			break
		selected_port = probe.get_local_port()
		result["probe_port_selected"] = selected_port >= 1 and selected_port <= 65535
		if not result["probe_port_selected"]:
			result["failure_code"] = "probe_port_invalid"
			break
		probe.close()
		result["probe_closed_before_takeover"] = not probe.is_bound()
		if not result["probe_closed_before_takeover"]:
			result["failure_code"] = "probe_release_failed"
			break
		if occupier.bind(selected_port, LOOPBACK) != OK:
			result["failure_code"] = "takeover_bind_failed"
			break
		result["takeover_held"] = occupier.is_bound()
		takeover.set_bind_ip(LOOPBACK)
		print(ERROR_BEGIN + "takeover")
		var takeover_error: Error = takeover.create_server(selected_port, 1)
		print(ERROR_END + "takeover")
		result["takeover_result"] = "ERR_CANT_CREATE" if takeover_error == ERR_CANT_CREATE else "UNEXPECTED"
		if takeover_error != ERR_CANT_CREATE or not occupier.is_bound():
			result["failure_code"] = "takeover_not_rejected"
			break

		occupier.close()
		rebound.set_bind_ip(LOOPBACK)
		var rebound_error: Error = rebound.create_server(selected_port, 1)
		result["released_port_rebound"] = rebound_error == OK
		if not result["released_port_rebound"]:
			result["failure_code"] = "released_bind_failed"
			break
		if rebound.get_host() == null:
			result["failure_code"] = "rebound_host_missing"
			break
		# The host Ref is never retained across close; only its integer is read.
		result["rebound_port_matches"] = rebound.get_host().get_local_port() == selected_port
		if not result["rebound_port_matches"]:
			result["failure_code"] = "rebound_port_mismatch"
			break
		rebound.close()

		listener.set_bind_ip(LOOPBACK)
		if listener.create_server(0, 1) != OK:
			result["failure_code"] = "listener_bind_failed"
			break
		if listener.get_host() == null:
			result["failure_code"] = "listener_host_missing"
			break
		listener_port = listener.get_host().get_local_port()
		result["os_bound_port_positive"] = listener_port > 0 and listener_port <= 65535
		if not result["os_bound_port_positive"]:
			result["failure_code"] = "listener_port_invalid"
			break
		duplicate.set_bind_ip(LOOPBACK)
		print(ERROR_BEGIN + "duplicate")
		var duplicate_error: Error = duplicate.create_server(listener_port, 1)
		print(ERROR_END + "duplicate")
		result["duplicate_result"] = "ERR_CANT_CREATE" if duplicate_error == ERR_CANT_CREATE else "UNEXPECTED"
		if duplicate_error != ERR_CANT_CREATE:
			result["failure_code"] = "duplicate_not_rejected"
			break
		result["listener_remained_active"] = listener.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		if not result["listener_remained_active"] or listener.get_host() == null:
			result["failure_code"] = "listener_not_active"
			break
		if listener.get_host().get_local_port() != listener_port:
			result["failure_code"] = "listener_port_changed"
			break
		sequence_complete = true
		break

	probe.close()
	occupier.close()
	takeover.close()
	rebound.close()
	listener.close()
	duplicate.close()
	result["resources_released"] = not probe.is_bound() and not occupier.is_bound() \
		and takeover.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED \
		and rebound.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED \
		and listener.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED \
		and duplicate.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
	if sequence_complete and result["resources_released"]:
		# Positive bind-after-close controls observe actual socket release.
		result["released_selected_port_rebound"] = _prove_rebind(selected_port)
		if result["released_selected_port_rebound"]:
			result["released_listener_port_rebound"] = _prove_rebind(listener_port)
		if not result["released_selected_port_rebound"] or not result["released_listener_port_rebound"]:
			result["failure_code"] = "cleanup_rebind_failed"
	elif sequence_complete:
		result["failure_code"] = "cleanup_status_failed"
	result["passed"] = sequence_complete and result["failure_code"] == "none" \
		and result["resources_released"] and result["released_selected_port_rebound"] \
		and result["released_listener_port_rebound"]
	probe = null
	occupier = null
	takeover = null
	rebound = null
	listener = null
	duplicate = null
	return result


func _prove_rebind(port: int) -> bool:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(LOOPBACK)
	var released: bool = false
	if peer.create_server(port, 1) == OK and peer.get_host() != null:
		released = peer.get_host().get_local_port() == port \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	peer.close()
	released = released and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
	peer = null
	return released
