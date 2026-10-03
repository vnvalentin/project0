extends GutTest
## GUT wrapper for the real three-process E2E harness
## scripts/test_multi_peer_replication.gd (Slice 007 evidence, cited by
## docs/slices/007-multi-peer-player-replication.md and FEATURE-LIST.md). The
## harness itself is not modified or renamed (DT-006 Option A) — it spawns and
## tears down its own real server process plus two client harness processes,
## bound to 127.0.0.1:9999. This wrapper only runs it as a blocking child
## process so it appears as a testsuite in build/validation/gut.xml under
## scripts/run_gut_validation.sh.
##
## Set PROJECT0_SKIP_E2E (any non-empty value) to skip the real run (e.g. a
## sandbox with no loopback networking); the testsuite still registers so the
## hardened "every tests/**/test_*.gd present in gut.xml" gate stays green.
## Unset, the harness MUST actually execute.

class SnapshotClient extends "res://scripts/multi_peer_client_harness.gd":
	func _initialize() -> void:
		pass


class SnapshotNetwork extends Node:
	var status: String = "connected: player spawned"


func test_harness_avoids_foreign_game_and_control_listeners() -> void:
	var foreign_game: PacketPeerUDP = PacketPeerUDP.new()
	var foreign_control: TCPServer = TCPServer.new()
	var game_bound: Error = foreign_game.bind(9999, "127.0.0.1")
	var control_bound: Error = foreign_control.listen(8097, "127.0.0.1")
	assert_eq(game_bound, OK, "isolated probe owns the foreign game listener")
	assert_eq(control_bound, OK, "isolated probe owns the foreign control listener")
	if game_bound != OK or control_bound != OK:
		foreign_game.close()
		foreign_control.stop()
		return
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "scripts/test_multi_peer_replication.gd",
	]), output, true)
	var packets: int = foreign_game.get_available_packet_count()
	var control_contacted: bool = foreign_control.is_connection_available()
	foreign_game.close()
	foreign_control.stop()
	var joined_output: String = "\n".join(output)
	_save_output("multi-peer-1339-foreign-listeners", joined_output)
	assert_eq(exit_code, 0, "owned harness completes despite foreign default listeners")
	assert_true(joined_output.contains("ALL PASS"), "all original replication assertions pass")
	assert_eq(packets, 0, "clients send no traffic to the foreign game listener")
	assert_false(control_contacted, "harness never uses the foreign control listener")
	assert_false(joined_output.contains("SCRIPT ERROR:"), "collision isolation has no script errors")


func test_snapshot_publication_preserves_an_in_flight_reader() -> void:
	var client: SnapshotClient = SnapshotClient.new()
	var network: SnapshotNetwork = SnapshotNetwork.new()
	var gameplay: Node3D = Node3D.new()
	var remotes: Node3D = Node3D.new()
	remotes.name = "RemotePlayers"
	gameplay.add_child(remotes)
	var remote: Node3D = Node3D.new()
	remote.name = "RemotePlayer_2"
	remotes.add_child(remote)
	client._network_client = network
	client._gameplay_instance = gameplay
	client._state_file_path = "user://peer_snapshot_%d.json" % Time.get_ticks_usec()
	client._write_state()
	var reader: FileAccess = FileAccess.open(client._state_file_path, FileAccess.READ)
	remote.position = Vector3(0.0, 0.0, 9.0)
	client._write_state()
	var in_flight: Dictionary = JSON.parse_string(reader.get_as_text())
	reader.close()
	var latest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(client._state_file_path))
	assert_eq(in_flight["remote_players"]["RemotePlayer_2"], [0.0, 0.0, 0.0], "an open reader retains its complete snapshot during publication")
	assert_eq(latest["remote_players"]["RemotePlayer_2"], [0.0, 0.0, 9.0], "a new reader observes published movement")
	DirAccess.remove_absolute(client._state_file_path)
	gameplay.free()
	network.free()
	client.free()


func test_multi_peer_replication_harness_passes() -> void:
	if not OS.get_environment("PROJECT0_SKIP_E2E").is_empty():
		pending("PROJECT0_SKIP_E2E set: skipping real multi-process E2E harness run")
		return

	var output: Array = []
	var exit_code: int = OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"-s", "scripts/test_multi_peer_replication.gd",
		]),
		output,
		true,
	)

	var joined_output: String = "\n".join(output)
	_save_output("multi-peer-normal", joined_output)
	assert_eq(exit_code, 0, "multi-peer replication E2E harness exits 0 — output tail:\n%s" % _tail(joined_output))
	assert_true(joined_output.contains("ALL PASS"), "multi-peer replication E2E harness prints ALL PASS — output tail:\n%s" % _tail(joined_output))


func test_readiness_survives_delayed_client_publication() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/gated_multi_peer_replication.gd",
	]), output, true)
	var joined_output: String = "\n".join(output)
	_save_output("multi-peer-delayed", joined_output)
	assert_true(joined_output.contains("READINESS_RELEASE"), "real client was released by the observer interleaving")
	assert_eq(exit_code, 0, "readiness outlives observer frames without changing movement or disconnect assertions")
	assert_true(joined_output.contains("ALL PASS"), "delayed real client completes the complete E2E contract")
	assert_false(joined_output.contains("SCRIPT ERROR:"), "missing readiness never cascades into a script exception")
	var release: Dictionary = _event(joined_output, "READINESS_RELEASE ")
	assert_gt(int(release.get("a_reads", 0)), 300, "observer remains active beyond the former frame budget")
	assert_true(release.get("a_alive", false), "delayed client remains alive at release")
	assert_lt(int(release.get("elapsed_msec", 20000)), 20000, "release stays inside the wall-clock contract")


func test_readiness_fails_closed_when_client_exits() -> void:
	_assert_readiness_failure("--stop-client-before-ready", "process_exited", "multi-peer-exited")


func test_readiness_fails_closed_at_deadline() -> void:
	_assert_readiness_failure("--never-release", "deadline", "multi-peer-deadline")


func _assert_readiness_failure(argument: String, reason: String, artifact: String) -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/gated_multi_peer_replication.gd", "--", argument,
	]), output, true)
	var joined_output: String = "\n".join(output)
	_save_output(artifact, joined_output)
	var failure: Dictionary = _event(joined_output, "PEER_OBSERVATION_FAILED ")
	assert_eq(exit_code, 1, "unready real client fails the harness")
	assert_eq(failure.get("reason", ""), reason, "failure distinguishes exit from deadline")
	assert_eq(failure.get("last_valid_state", null), {}, "no invented ready snapshot")
	assert_false(joined_output.contains("ALL PASS"), "failed readiness cannot pass")
	assert_false(joined_output.contains("SCRIPT ERROR:"), "failed readiness cannot index absent peer state")
	assert_true(joined_output.contains("PASS: owned authenticated fixture database removed"), "failed readiness runs owned teardown")
	if reason == "deadline":
		assert_gte(int(failure.get("elapsed_msec", 0)), 20000, "deadline does not depend on observer frame rate")
		assert_true(failure.get("client_alive", false), "deadline evidence distinguishes a live gated client")
	else:
		assert_false(failure.get("client_alive", true), "exit evidence identifies the stopped client")


func test_movement_survives_delayed_client_publication() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/gated_movement_observation.gd",
	]), output, true)
	var joined_output: String = "\n".join(output)
	_save_output("multi-peer-movement-delayed", joined_output)
	assert_eq(exit_code, 0, "real movement survives delayed publication without changing the movement threshold")
	assert_true(joined_output.contains("ALL PASS"), "both original movement and disconnect assertions pass")
	assert_false(joined_output.contains("SCRIPT ERROR:"), "delayed publication does not cause a script exception")
	var release: Dictionary = _event(joined_output, "MOVEMENT_PUBLICATION_RELEASE ")
	assert_gt(int(release.get("a_reads", 0)), 300, "observer keeps reading beyond a one-shot sample")
	assert_true(release.get("a_alive", false), "real observer client remains alive at publication release")
	assert_lt(int(release.get("elapsed_msec", 20000)), 20000, "publication release is bounded by wall-clock time")


func test_movement_fails_closed_without_publication() -> void:
	_assert_movement_failure("--never-release", "deadline", "multi-peer-movement-deadline")


func test_movement_fails_closed_when_observer_client_exits() -> void:
	_assert_movement_failure("--stop-observer-client", "process_exited", "multi-peer-movement-exited")


func test_movement_rejects_vector_conversion_overflow() -> void:
	_assert_movement_failure("--overflow-observation", "deadline", "multi-peer-movement-overflow")


func _assert_movement_failure(argument: String, reason: String, artifact: String) -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/gated_movement_observation.gd", "--", argument,
	]), output, true)
	var joined_output: String = "\n".join(output)
	_save_output(artifact, joined_output)
	var failure: Dictionary = _event(joined_output, "PEER_OBSERVATION_FAILED ")
	var stage: Dictionary = _event(joined_output, "MOVEMENT_STAGE_FAILED ")
	var held: Dictionary = _event(joined_output, "MOVEMENT_PUBLICATION_HELD ")
	var held_remotes: Dictionary = held.get("published", {}).get("remote_players", {})
	assert_eq(stage.get("observer", ""), "A", "failure occurred in A's movement observation, not readiness")
	assert_eq(held_remotes.size(), 1, "movement fault starts with a real ready peer baseline")
	assert_true(held_remotes.has(stage.get("expected_peer", "")), "movement failure identifies the baseline peer")
	assert_eq(joined_output.count("ERROR: FAIL:"), 1, "only the intended movement assertion fails")
	var cleanup: Dictionary = _event(joined_output, "MOVEMENT_PUBLICATION_CLEANUP ")
	assert_eq(cleanup.get("paths_checked", 0), 3, "every publication sidecar is checked after cleanup")
	assert_true(cleanup.get("removed", false), "publication sidecars are gone after failure")
	assert_eq(exit_code, 1, "missing published movement fails the harness")
	assert_eq(failure.get("reason", ""), reason, "movement failure identifies its actual boundary")
	assert_false(joined_output.contains("ALL PASS"), "failed movement never becomes success")
	assert_false(joined_output.contains("SCRIPT ERROR:"), "missing movement does not cause a script exception")
	assert_true(joined_output.contains("PASS: owned authenticated fixture database removed"), "failed movement cleans up authenticated state")
	if reason == "deadline":
		assert_gte(int(failure.get("elapsed_msec", 0)), 20000, "missing publication waits for a monotonic deadline")
		assert_true(failure.get("client_alive", false), "deadline retains live-client evidence")
		var last_state: Dictionary = failure.get("last_valid_state", {})
		if argument == "--overflow-observation":
			assert_false(_event(joined_output, "MOVEMENT_INVALID_POSITION ").is_empty(), "overflow input was applied at the observation boundary")
		else:
			assert_eq(last_state.get("remote_players", {}), held_remotes, "observer does not replace stale state with unpublished data")
		assert_false(joined_output.contains("MOVEMENT_PUBLICATION_RELEASE "), "negative control never releases valid publication")
	else:
		assert_false(failure.get("client_alive", true), "exited client fails before inventing movement")
		assert_true(joined_output.contains("PASS: owned observer client stops during movement"), "exit fault was applied after readiness")


func _save_output(artifact: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://build/validation")
	var file: FileAccess = FileAccess.open("res://build/validation/" + artifact + ".log", FileAccess.WRITE)
	assert_not_null(file, "complete subprocess evidence is retained")
	if file != null:
		file.store_string(text)
		file.close()


func _event(text: String, prefix: String) -> Dictionary:
	for line: String in text.split("\n"):
		if line.begins_with(prefix):
			var parsed: Variant = JSON.parse_string(line.substr(prefix.length()))
			if parsed is Dictionary:
				return parsed
	return {}


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var start: int = max(0, lines.size() - 40)
	return "\n".join(lines.slice(start))
