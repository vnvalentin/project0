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
