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
	assert_eq(exit_code, 0, "multi-peer replication E2E harness exits 0 — output tail:\n%s" % _tail(joined_output))
	assert_true(joined_output.contains("ALL PASS"), "multi-peer replication E2E harness prints ALL PASS — output tail:\n%s" % _tail(joined_output))


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var start: int = max(0, lines.size() - 40)
	return "\n".join(lines.slice(start))
