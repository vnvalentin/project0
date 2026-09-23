extends GutTest

const JitPresentationAckTrackerScript: Script = preload("res://server/jit_presentation_ack_tracker.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")


func test_only_exact_accepted_peer_acknowledgement_promotes_pending_trace() -> void:
	var tracker: Object = JitPresentationAckTrackerScript.new()
	var commit: Dictionary = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-0-0"),
		"canon_db_commit",
	)
	var issued: Dictionary = tracker.issue(7, commit)
	assert_false(issued.is_empty())
	assert_ne(issued["span_id"], tracker.issue(8, commit)["span_id"], "each peer receives a unique span")

	var raw_event: Dictionary = _raw_event(issued)
	assert_true(tracker.match_pending(8, raw_event).is_empty(), "another peer cannot claim the span")
	var forged: Dictionary = raw_event.duplicate(true)
	forged["payload"]["span_id"] = "forged"
	assert_true(tracker.match_pending(7, forged).is_empty(), "a forged span cannot be promoted")

	var matched: Dictionary = tracker.match_pending(7, raw_event)
	assert_eq(matched, issued, "the exact peer acknowledgement matches server-owned state")
	assert_eq(tracker.confirm_persisted(7, matched), issued, "persistence promotes the matched trace")
	assert_true(tracker.match_pending(7, raw_event).is_empty(), "a duplicate acknowledgement is ignored")


func test_missing_acknowledgement_never_promotes_a_trace() -> void:
	var tracker: Object = JitPresentationAckTrackerScript.new()
	var commit: Dictionary = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-0-0"),
		"canon_db_commit",
	)
	tracker.issue(7, commit)
	assert_true(tracker.match_pending(7, {"event_type": "unrelated", "payload": {}}).is_empty())


func test_pending_acknowledgements_are_bounded_per_peer() -> void:
	var tracker: Object = JitPresentationAckTrackerScript.new()
	var first: Dictionary = {}
	var last: Dictionary = {}
	for index: int in range(JitPresentationAckTrackerScript.MAX_PENDING_PER_PEER + 1):
		var commit: Dictionary = JitTraceContextScript.child(
			JitTraceContextScript.root(7, "sector-%d" % index),
			"canon_db_commit",
		)
		var issued: Dictionary = tracker.issue(7, commit)
		if index == 0:
			first = issued
		last = issued
	assert_true(tracker.match_pending(7, _raw_event(first)).is_empty(), "the oldest pending span is evicted")
	assert_eq(tracker.match_pending(7, _raw_event(last)), last, "the newest pending span remains")


func test_verified_batch_drops_forged_ack_and_promotes_only_after_persistence() -> void:
	var tracker: Object = JitPresentationAckTrackerScript.new()
	var commit: Dictionary = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-0-0"),
		"canon_db_commit",
	)
	var issued: Dictionary = tracker.issue(7, commit)
	var forged: Dictionary = _raw_event(issued)
	forged["payload"]["span_id"] = "forged"
	assert_true(tracker.verified_events(7, [forged]).is_empty(), "forged telemetry is not persisted")
	var verified: Array[Dictionary] = tracker.verified_events(7, [_raw_event(issued)])
	assert_eq(verified.size(), 1)
	assert_eq(tracker.match_pending(7, verified[0]), issued, "verification alone does not consume pending state")
	assert_eq(tracker.confirm_accepted(7, verified), [issued], "accepted persistence promotes the trace")
	assert_true(tracker.confirm_accepted(7, verified).is_empty(), "accepted replay cannot promote twice")


func test_verified_batch_drops_forged_server_authored_trace_events() -> void:
	var tracker: Object = JitPresentationAckTrackerScript.new()
	var forged_reentry: Dictionary = {
		"event_type": "canon_reentry",
		"schema_version": 1,
		"payload": {"trace_id": "forged"},
	}
	var ordinary_client_event: Dictionary = {
		"event_type": "client_frame_health",
		"schema_version": 1,
		"payload": {},
	}
	assert_eq(
		tracker.verified_events(7, [forged_reentry, ordinary_client_event]),
		[ordinary_client_event],
		"server-owned trace events cannot enter through the client telemetry path",
	)


func _raw_event(trace: Dictionary) -> Dictionary:
	var payload: Dictionary = trace.duplicate(true)
	payload.erase("event_type")
	return {"event_type": "client_presentation_ack", "schema_version": 1, "payload": payload}