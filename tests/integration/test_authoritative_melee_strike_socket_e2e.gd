extends GutTest
## GUT wrapper for the real two-process E2E harness
## scripts/test_authoritative_melee_strike_e2e.gd (Slice 012/013 evidence,
## cited by docs/slices/012 and 013 and FEATURE-LIST.md). The harness itself
## is not modified or renamed (DT-006 Option A) — it spawns and tears down its
## own real server process bound to 127.0.0.1:9999 and proves the melee
## ActionIntent/ActionResolution/CombatEvent RPCs over a real ENet socket
## (tests/integration/test_authoritative_melee_strike.gd already covers the
## in-process server-side state machine and hit math; this wrapper covers only
## the socket wiring evidence). This wrapper only runs it as a blocking child
## process so it appears as a testsuite in build/validation/gut.xml under
## scripts/run_gut_validation.sh.
##
## Set PROJECT0_SKIP_E2E (any non-empty value) to skip the real run (e.g. a
## sandbox with no loopback networking); the testsuite still registers so the
## hardened "every tests/**/test_*.gd present in gut.xml" gate stays green.
## Unset, the harness MUST actually execute.

func test_authoritative_melee_strike_socket_harness_passes() -> void:
	if not OS.get_environment("PROJECT0_SKIP_E2E").is_empty():
		pending("PROJECT0_SKIP_E2E set: skipping real two-process E2E harness run")
		return

	var output: Array = []
	var exit_code: int = OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"-s", "scripts/test_authoritative_melee_strike_e2e.gd",
		]),
		output,
		true,
	)

	var joined_output: String = "\n".join(output)
	assert_eq(exit_code, 0, "authoritative melee strike socket E2E harness exits 0 — output tail:\n%s" % _tail(joined_output))
	assert_true(joined_output.contains("ALL PASS"), "authoritative melee strike socket E2E harness prints ALL PASS — output tail:\n%s" % _tail(joined_output))


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var start: int = max(0, lines.size() - 40)
	return "\n".join(lines.slice(start))
