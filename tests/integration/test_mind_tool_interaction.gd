extends GutTest
## M0.4 public-seam contract tests: a client submits a physical interaction
## intent, never a reasoning-stat solution claim or an outcome.

const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")


func test_lock_pick_intent_contains_solution_and_physical_context_only() -> void:
	var intent: Dictionary = InteractionScript.build_intent(
		"sector-0-0",
		"structure-gate-1",
		InteractionScript.VERB_LOCK_PICK,
		0,
		Vector3(0.0, 0.0, -1.0),
		1
	)
	var parsed: Dictionary = InteractionScript.parse_intent(intent)
	assert_eq(parsed["outcome"], InteractionScript.OUTCOME_OK)
	assert_eq(parsed["intent"]["verb"], InteractionScript.VERB_LOCK_PICK)
	assert_false(parsed["intent"].has("reasoning_stat"), "the solution intent has no reasoning gate")
	assert_false(parsed["intent"].has("success"), "the client cannot submit an outcome")


func test_interrupt_intent_is_an_accepted_physical_verb() -> void:
	var intent: Dictionary = InteractionScript.build_intent(
		"sector-0-0",
		"structure-gate-1",
		InteractionScript.VERB_INTERRUPT,
		0,
		Vector3.FORWARD,
		1
	)
	assert_eq(InteractionScript.parse_intent(intent)["outcome"], InteractionScript.OUTCOME_OK)


func test_reasoning_stat_and_outcome_fields_are_rejected() -> void:
	var forged: Dictionary = InteractionScript.build_intent(
		"sector-0-0",
		"structure-gate-1",
		InteractionScript.VERB_LOCK_PICK,
		0,
		Vector3.FORWARD,
		1
	)
	forged["reasoning_stat"] = 999
	assert_eq(InteractionScript.parse_intent(forged)["outcome"], InteractionScript.OUTCOME_INVALID)

	var outcome_forgery: Dictionary = forged.duplicate()
	outcome_forgery.erase("reasoning_stat")
	outcome_forgery["success"] = true
	assert_eq(InteractionScript.parse_intent(outcome_forgery)["outcome"], InteractionScript.OUTCOME_INVALID)
