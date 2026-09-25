extends GutTest
## GUT wrapper for the real two-process E2E harness
## scripts/test_prediction_reconciliation.gd (Slice 005 evidence, cited by
## docs/slices/005-prediction-reconciliation.md and FEATURE-LIST.md). The
## harness itself is not modified or renamed (DT-006 Option A) — it spawns
## and tears down its own real server process on a private loopback port. This
## wrapper only runs it as a blocking child process so it appears as a
## testsuite in build/validation/gut.xml under scripts/run_gut_validation.sh.
##
## Set PROJECT0_SKIP_E2E (any non-empty value) to skip the real run (e.g. a
## sandbox with no loopback networking); the testsuite still registers so the
## hardened "every tests/**/test_*.gd present in gut.xml" gate stays green.
## Unset, the harness MUST actually execute.

func test_prediction_reconciliation_harness_passes() -> void:
	if not OS.get_environment("PROJECT0_SKIP_E2E").is_empty():
		pending("PROJECT0_SKIP_E2E set: skipping real two-process E2E harness run")
		return

	var result: Dictionary = _execute_harness(OS.get_executable_path(), ProjectSettings.globalize_path("res://"))
	var joined_output: String = result["output"]
	assert_eq(result["exit_code"], 0, "prediction/reconciliation E2E harness exits 0 — output tail:\n%s" % _tail(joined_output))
	assert_true(joined_output.contains("ALL PASS"), "prediction/reconciliation E2E harness prints ALL PASS — output tail:\n%s" % _tail(joined_output))


func test_concurrent_prediction_harnesses_are_isolated() -> void:
	if not OS.get_environment("PROJECT0_SKIP_E2E").is_empty():
		pending("PROJECT0_SKIP_E2E set: skipping concurrent E2E harness run")
		return
	var executable: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var threads: Array[Thread] = []
	for run_index: int in range(2):
		var thread: Thread = Thread.new()
		var error: Error = thread.start(_execute_harness.bind(executable, project_path))
		assert_eq(error, OK, "concurrent harness %d starts" % run_index)
		if error == OK:
			threads.append(thread)
	for thread: Thread in threads:
		var result: Dictionary = thread.wait_to_finish()
		var output: String = result["output"]
		assert_eq(result["exit_code"], 0, "isolated overlapping harness exits 0:\n%s" % _tail(output))
		assert_true(output.contains("ALL PASS"), "overlapping harness proves every assertion")
		assert_false(output.contains("Server listening on 127.0.0.1:9999"), "harness does not share default game port")
		assert_false(output.contains("internal port 8097"), "harness does not share default operator port")


func _execute_harness(executable: String, project_path: String) -> Dictionary:
	var output: Array = []
	var exit_code: int = OS.execute(executable, PackedStringArray([
		"--headless", "--path", project_path, "-s", "scripts/test_prediction_reconciliation.gd",
	]), output, true)
	return {"exit_code": exit_code, "output": "\n".join(output)}


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var start: int = max(0, lines.size() - 40)
	return "\n".join(lines.slice(start))
