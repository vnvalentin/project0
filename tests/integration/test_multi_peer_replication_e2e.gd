extends GutTest
## GUT wrapper for the real three-process E2E harness
## scripts/test_multi_peer_replication.gd (Slice 007 evidence, cited by
## docs/slices/007-multi-peer-player-replication.md and FEATURE-LIST.md). The
## harness spawns and tears down an owned server plus two real client
## processes on isolated loopback ports, with disjoint state and listening
## ownership proven before client startup. This wrapper runs it as a child
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


func test_selected_port_collision_fails_before_clients_start() -> void:
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/occupied_multi_peer_port.gd", "--", "--occupy-selected-port",
	]), output, true)
	var text: String = "\n".join(output)
	_save_output("multi-peer-1339-selected-port-collision", text)
	var failure: Dictionary = _event(text, "HARNESS_STARTUP_FAILED ")
	var probe: Dictionary = _event(text, "HARNESS_COLLISION_PROBE ")
	assert_eq(exit_code, 1, "lost port allocation fails the owned harness")
	assert_eq(failure.get("reason", ""), "process_exited", "failed server startup is observed before client admission")
	assert_gt(int(failure.get("game_port", 0)), 0, "startup diagnostic identifies the selected port")
	assert_false(probe.get("clients_started", true), "neither client starts without owned listening proof")
	assert_eq(int(probe.get("packets", -1)), 0, "selected foreign listener receives no client traffic")
	assert_false(text.contains("ALL PASS"), "failed startup cannot pass")
	assert_false(text.contains("SCRIPT ERROR:"), "startup rejection does not cascade into script errors")
	assert_true(text.contains("PASS: owned authenticated fixture database removed"), "failed startup cleans up authenticated state")


func test_parallel_timeout_removes_owned_descendants_and_state() -> void:
	await _assert_contained_timeout(false)


func test_parallel_timeout_finds_unregistered_owned_sessions() -> void:
	await _assert_contained_timeout(true)


func test_containment_finds_owned_members_after_leader_exit() -> void:
	var path: String = "user://multi_peer_orphan_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var helper: String = ProjectSettings.globalize_path("res://tests/fixtures/contained_multi_peer.py")
	var process_id: int = OS.create_process("/usr/bin/python3", PackedStringArray([
		helper, "run", ProjectSettings.globalize_path(path), path.get_file(),
		"/usr/bin/python3", helper, "orphan", ProjectSettings.globalize_path(path), path.get_file(),
	]))
	assert_gt(process_id, 0, "native session-leader control starts")
	var deadline: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and (not FileAccess.file_exists(path) or OS.is_process_running(process_id)):
		await get_tree().process_frame
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var report: Dictionary = parsed if parsed is Dictionary else {}
	var descendant: int = int(report.get("descendant", -1))
	assert_eq(report.get("phase", ""), "orphan", "leader publishes its real native descendant before exit")
	assert_false(OS.is_process_running(process_id), "native group leader exited before cleanup")
	assert_true(_contained_descendant_is_alive(path, descendant), "owned group retains a live member after leader exit")
	var cleanup: Dictionary = _stop_contained_harness(path, process_id)
	assert_true(cleanup.get("passed", false), "cleanup succeeds without a live leader or registered child")
	assert_eq(int(cleanup.get("remaining", -1)), 0, "no owned native session members remain")
	assert_false(_contained_descendant_is_alive(path, descendant), "orphaned owned member is stopped")
	assert_false(FileAccess.file_exists(path + ".group.json"), "completed containment lease is removed")
	if FileAccess.file_exists(path):
		assert_eq(DirAccess.remove_absolute(path), OK, "owned orphan control report is removed")


func _assert_contained_timeout(omit_registration: bool) -> void:
	var path: String = "user://multi_peer_timeout_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var process_id: int = _start_contained_harness(path, true, omit_registration)
	assert_gt(process_id, 0, "timeout probe starts an owned orchestrator")
	var deadline: int = Time.get_ticks_msec() + 10000
	var report: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				report = parsed
		if report.get("phase", "") == "held":
			break
		await get_tree().process_frame
	assert_eq(report.get("phase", ""), "held", "timeout is injected with actual owned server and clients alive")
	var cleanup: Dictionary = _stop_contained_harness(path, process_id)
	assert_true(cleanup.get("passed", false), "forced timeout cleanup proves process-group ownership and completion")
	assert_gte(int(cleanup.get("processes_terminated", 0)), 4, "timeout terminates the actual orchestrator, server and two clients")
	await get_tree().process_frame
	for child_id: int in report.get("probe_children", []):
		assert_false(child_id > 0 and OS.is_process_running(child_id), "timeout leaves no owned descendant running")
	for state_path: String in report.get("paths", []):
		assert_false(FileAccess.file_exists(state_path), "timeout removes owned published state")
		assert_false(FileAccess.file_exists(state_path + ".pending"), "timeout removes pending publication state")
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		assert_false(FileAccess.file_exists(str(report.get("database", "")) + suffix), "timeout removes the owned authenticated database and sidecars")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_concurrent_harnesses_use_disjoint_endpoints_and_state() -> void:
	var identity: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var paths: Array[String] = ["user://multi_peer_parallel_%s_a.json" % identity, "user://multi_peer_parallel_%s_b.json" % identity]
	var processes: Array[int] = []
	for path: String in paths:
		assert_false(FileAccess.file_exists(path), "owned concurrent report starts absent")
		processes.append(_start_contained_harness(path, false))
		assert_gt(processes[-1], 0, "independent harness process starts")
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		var finished: bool = true
		for process_id: int in processes:
			finished = finished and (process_id <= 0 or not OS.is_process_running(process_id))
		if finished:
			break
		await get_tree().process_frame
	var reports: Array[Dictionary] = []
	for index: int in range(processes.size()):
		var process_id: int = processes[index]
		assert_false(process_id > 0 and OS.is_process_running(process_id), "concurrent harness terminates within its orchestration deadline")
		assert_true(_stop_contained_harness(paths[index], process_id).get("passed", false), "concurrent process group and remaining owned state are cleaned up")
	for path: String in paths:
		var report: Dictionary = {}
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				report = parsed
		reports.append(report)
		assert_eq(report.get("failures", -1), 0, "each harness completes its unchanged replication journey")
		assert_true(report.get("paths_removed", false), "each harness removes only its own state")
		for candidate: String in [path, path + ".pending"]:
			if FileAccess.file_exists(candidate):
				assert_eq(DirAccess.remove_absolute(candidate), OK, "owned concurrent report is removed")
	if reports[0].is_empty() or reports[1].is_empty():
		return
	assert_ne(reports[0]["identity"], reports[1]["identity"], "simultaneous harness identities are disjoint")
	assert_ne(reports[0]["state_a"], reports[1]["state_a"], "client A state cannot be read or removed by another harness")
	assert_ne(reports[0]["state_b"], reports[1]["state_b"], "client B state cannot be read or removed by another harness")
	assert_ne(reports[0]["endpoints"]["game_port"], reports[1]["endpoints"]["game_port"], "simultaneous game endpoints are distinct")
	assert_ne(reports[0]["endpoints"]["control_port"], reports[1]["endpoints"]["control_port"], "simultaneous control endpoints are distinct")


func _start_contained_harness(report_path: String, held: bool, omit_registration: bool = false) -> int:
	var arguments: PackedStringArray = [
		ProjectSettings.globalize_path("res://tests/fixtures/contained_multi_peer.py"), "run",
		ProjectSettings.globalize_path(report_path), report_path.get_file(), OS.get_executable_path(),
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/occupied_multi_peer_port.gd", "--", "--report-file=%s" % ProjectSettings.globalize_path(report_path),
	]
	if held:
		arguments.append("--hold-owned-processes")
	if omit_registration:
		arguments.append("--omit-client-registration")
	return OS.create_process("/usr/bin/python3", arguments)


func _stop_contained_harness(report_path: String, process_id: int) -> Dictionary:
	if process_id <= 0:
		return {"passed": false}
	var output: Array = []
	var code: int = OS.execute("/usr/bin/python3", PackedStringArray([
		ProjectSettings.globalize_path("res://tests/fixtures/contained_multi_peer.py"), "stop",
		ProjectSettings.globalize_path(report_path), report_path.get_file(), str(process_id),
	]), output, true)
	var result: Dictionary = _event("\n".join(output), "CONTAINED_CLEANUP ")
	result["passed"] = code == 0 and result.get("passed", false)
	return result


func _contained_descendant_is_alive(report_path: String, descendant: int) -> bool:
	var output: Array = []
	var code: int = OS.execute("/usr/bin/python3", PackedStringArray([
		ProjectSettings.globalize_path("res://tests/fixtures/contained_multi_peer.py"), "inspect",
		ProjectSettings.globalize_path(report_path), report_path.get_file(), str(descendant),
	]), output, true)
	var result: Dictionary = _event("\n".join(output), "CONTAINED_OBSERVATION ")
	assert_eq(code, 0, "native descendant observation has verified custody")
	assert_true(result.get("observed", false), "native process observation is available")
	return result.get("alive", false)


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
