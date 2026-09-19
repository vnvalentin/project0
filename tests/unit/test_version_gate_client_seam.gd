extends GutTest
## Slice 146 (Phase 16, F-037): the client half of the live version gate. The
## server owns the decision; this covers what a refused client does with it —
## retain the reason, surface a bounded status, and relay it for the UI. Exercised
## against the NetworkClient autoload directly (no socket), mirroring
## tests/unit/test_monster_node.gd. See docs/slices/146-version-gate-enforcement.md.

const VersionHandshakeScript: Script = preload("res://shared/version_handshake.gd")

var _original_status: String = ""


func before_each() -> void:
	_original_status = NetworkClient.status
	NetworkClient.latest_version_rejection = {}


func after_each() -> void:
	NetworkClient.latest_version_rejection = {}
	NetworkClient.status = _original_status


func _rejection() -> Dictionary:
	return {
		"outcome": VersionHandshakeScript.OUTCOME_CLIENT_OUTDATED,
		"detail": "client build version does not match the required version",
		"required_version": "1.3.0",
		"manifest_base_url": "https://enrollment.example/patches",
	}


func test_rejection_is_retained_for_ui_created_later() -> void:
	NetworkClient.receive_version_handshake_rejected(_rejection())
	assert_eq(
		NetworkClient.latest_version_rejection["required_version"],
		"1.3.0",
		"the refused client remembers which version it needs"
	)
	assert_eq(
		NetworkClient.latest_version_rejection["manifest_base_url"],
		"https://enrollment.example/patches",
		"and where to get it"
	)


func test_rejection_surfaces_a_bounded_status() -> void:
	NetworkClient.receive_version_handshake_rejected(_rejection())
	assert_eq(
		NetworkClient.status,
		"refused: %s" % VersionHandshakeScript.OUTCOME_CLIENT_OUTDATED,
		"the status names the bounded outcome, not a raw server string"
	)


func test_rejection_is_relayed_so_ui_can_react() -> void:
	watch_signals(NetworkClient)
	NetworkClient.receive_version_handshake_rejected(_rejection())
	assert_signal_emitted(NetworkClient, "version_handshake_rejected")
	var params: Array = get_signal_parameters(NetworkClient, "version_handshake_rejected", 0)
	assert_eq(params[0]["outcome"], VersionHandshakeScript.OUTCOME_CLIENT_OUTDATED, "relays the outcome")


func test_a_server_misconfiguration_is_reported_as_such_not_as_outdated() -> void:
	NetworkClient.receive_version_handshake_rejected({
		"outcome": VersionHandshakeScript.OUTCOME_SERVER_MISCONFIGURED,
		"detail": "required client build version is not configured correctly",
		"required_version": "",
		"manifest_base_url": "",
	})
	assert_eq(
		NetworkClient.status,
		"refused: %s" % VersionHandshakeScript.OUTCOME_SERVER_MISCONFIGURED,
		"an operator fault is never shown to the player as their client being outdated"
	)
