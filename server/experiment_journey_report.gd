extends RefCounted
class_name ExperimentJourneyReport
## Slice 1325: builds and writes the #1137 consolidated experiment report from
## observations. Evidence only: nothing here feeds gameplay authority. Missing or
## malformed observations stay null/NOT_OBSERVED and fail the report; parity is
## decided by direct comparison, with hashes kept as diagnostics.

const OBSERVED: String = "OBSERVED"
const NOT_OBSERVED: String = "NOT_OBSERVED"
const NOT_EXERCISED: String = "NOT_EXERCISED"
const MATCH: String = "MATCH"
const MISMATCH: String = "MISMATCH"

const COMMIT_SUCCESS: String = "COMMIT_SUCCESS"
const COMMIT_ROLLED_BACK: String = "COMMIT_ROLLED_BACK"
const COMMIT_NOT_ATTEMPTED: String = "COMMIT_NOT_ATTEMPTED"
const RECOVERY_PARITY_MATCH: String = "RECOVERY_PARITY_MATCH"
const RECOVERY_FAILED: String = "RECOVERY_FAILED"
const OUTCOME_PASSED: String = "PASSED"
const OUTCOME_FAILED: String = "FAILED"
const OUTCOME_OBSERVATION_FAILED: String = "OBSERVATION_FAILED"

const STAGE_JOURNEY_IDENTITY: String = "journey_identity"
const STAGE_COMMIT: String = "commit"
const STAGE_BASE_PARITY: String = "base_blueprint_parity"
const STAGE_MUTATION_PARITY: String = "mutation_records_parity"
const STAGE_ENTITY_PARITY: String = "reconstructed_entity_state_parity"
const STAGE_SECTOR_TOTALS: String = "sector_totals"
const STAGE_PLAYER_COUNTS: String = "player_counts"
const STAGE_RELOAD_EVENTS: String = "reload_events"
const STAGE_CASE_ASSERTIONS: String = "case_assertions"
const STAGE_RUNTIME_ERRORS: String = "runtime_errors"
const STAGES: PackedStringArray = [
	STAGE_JOURNEY_IDENTITY, STAGE_COMMIT, STAGE_BASE_PARITY, STAGE_MUTATION_PARITY, STAGE_ENTITY_PARITY,
	STAGE_SECTOR_TOTALS, STAGE_PLAYER_COUNTS, STAGE_RELOAD_EVENTS, STAGE_CASE_ASSERTIONS, STAGE_RUNTIME_ERRORS,
]
## Case assertions are experiment-specific, so only scenarios that list them require them.
const DEFAULT_REQUIRED_STAGES: PackedStringArray = [
	STAGE_JOURNEY_IDENTITY, STAGE_COMMIT, STAGE_BASE_PARITY, STAGE_MUTATION_PARITY, STAGE_ENTITY_PARITY,
	STAGE_SECTOR_TOTALS, STAGE_PLAYER_COUNTS, STAGE_RELOAD_EVENTS, STAGE_RUNTIME_ERRORS,
]
const PARITY_STAGES: PackedStringArray = [STAGE_BASE_PARITY, STAGE_MUTATION_PARITY, STAGE_ENTITY_PARITY]

const RELOAD_EVENT_TYPE: String = "CANON_SECTOR_RELOADED"
const FILE_PATTERN: String = "exp_1137_journey_report_%d.json"
const WRITE_OK: String = "ok"
const WRITE_EXISTS: String = "exists"
const WRITE_FAILED: String = "write_failed"


static func build(input: Dictionary) -> Dictionary:
	var scenario: Dictionary = input.get("scenario", {})
	var required: Array = Array(scenario.get("required_stages", DEFAULT_REQUIRED_STAGES))
	if not required.has(STAGE_RUNTIME_ERRORS):
		required.append(STAGE_RUNTIME_ERRORS)
	var sector: Dictionary = input.get("sector", {})
	var sector_id: String = String(sector.get("sector_id", ""))
	var status: Dictionary = {}

	var raw_journeys: Array = input.get("journeys", []) if input.get("journeys") is Array else []
	var entries: Array = []
	for raw: Variant in raw_journeys:
		entries.append(_journey_entry(raw, sector_id))
	status[STAGE_JOURNEY_IDENTITY] = _identity_status(entries)

	var commit: Dictionary = input.get("commit", {}) if input.get("commit") is Dictionary else {}
	var commit_outcome: String = OUTCOME_OBSERVATION_FAILED
	if commit.get("status") == OBSERVED and String(commit.get("outcome", "")) in [COMMIT_SUCCESS, COMMIT_ROLLED_BACK, COMMIT_NOT_ATTEMPTED]:
		commit_outcome = commit["outcome"]
		status[STAGE_COMMIT] = MATCH if commit_outcome == String(scenario.get("expected_commit", "")) else MISMATCH
	else:
		status[STAGE_COMMIT] = NOT_OBSERVED

	var snapshot: Dictionary = input.get("snapshot", {}) if input.get("snapshot") is Dictionary else {}
	var expected: Dictionary = snapshot.get("expected", {}) if snapshot.get("expected") is Dictionary else {}
	var actual: Dictionary = snapshot.get("actual", {}) if snapshot.get("actual") is Dictionary else {}
	var comparison: Dictionary = {
		STAGE_BASE_PARITY: _compare_base(expected.get("base_json"), actual.get("base_json")),
		STAGE_MUTATION_PARITY: _compare_mutations(expected.get("mutations"), actual.get("mutations")),
		STAGE_ENTITY_PARITY: _compare_entities(expected.get("entities"), actual.get("entities")),
	}
	for stage: String in PARITY_STAGES:
		comparison[stage]["evidence"] = snapshot.get("evidence", {}).get(stage, null) if snapshot.get("evidence") is Dictionary else null
		status[stage] = comparison[stage]["status"]

	var sector_totals: Dictionary = {
		"sector_id": sector_id,
		"generation_count": _count(sector.get("generation_count")),
		"canon_write_count": _count(sector.get("canon_write_count")),
	}
	sector_totals["observation_status"] = OBSERVED if sector_totals["generation_count"] != null and sector_totals["canon_write_count"] != null else NOT_OBSERVED
	status[STAGE_SECTOR_TOTALS] = _zero_status([sector_totals])
	status[STAGE_PLAYER_COUNTS] = _zero_status(entries) if entries.size() == 2 else NOT_OBSERVED
	status[STAGE_RELOAD_EVENTS] = _reload_status(entries)

	var case_assertions: Variant = input.get("case_assertions")
	status[STAGE_CASE_ASSERTIONS] = _case_status(case_assertions)

	var runtime_errors: Variant = input.get("runtime_errors")
	status[STAGE_RUNTIME_ERRORS] = NOT_OBSERVED if not runtime_errors is Array else (MATCH if (runtime_errors as Array).is_empty() else MISMATCH)

	for stage: String in STAGES:
		if not required.has(stage):
			status[stage] = NOT_EXERCISED
	for stage: String in PARITY_STAGES:
		comparison[stage]["status"] = status[stage]
		if status[stage] == NOT_EXERCISED:
			comparison[stage]["exact_match"] = false

	var first_failing: Variant = null
	var any_unobserved: bool = false
	for stage: String in STAGES:
		if status[stage] == NOT_EXERCISED or status[stage] == MATCH:
			continue
		if first_failing == null:
			first_failing = stage
		if status[stage] == NOT_OBSERVED:
			any_unobserved = true

	var outcome: String = OUTCOME_PASSED
	if first_failing != null:
		outcome = OUTCOME_OBSERVATION_FAILED if any_unobserved else OUTCOME_FAILED
	return {
		"experiment_id": input.get("experiment_id"),
		"timestamp_ms": int(input.get("timestamp_ms", 0)),
		"scenario": scenario.duplicate(true),
		"commit_outcome": commit_outcome,
		"recovery_outcome": _recovery_outcome(status),
		"sector_totals": sector_totals,
		"journey_entries": entries,
		"snapshot_comparison": comparison,
		"stage_status": status,
		"first_failing_stage": first_failing,
		"case_assertions": (case_assertions as Array).duplicate(true) if case_assertions is Array else null,
		"observations": input.get("observations"),
		"runtime_errors": (runtime_errors as Array).duplicate(true) if runtime_errors is Array else null,
		"outcome": outcome,
		"passed": first_failing == null,
	}


## Writes the report under `directory` (res://, user:// or absolute). Never
## overwrites an existing report; a failed write cannot alter the report.
static func write(report: Dictionary, directory: String) -> Dictionary:
	var absolute: String = ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(absolute)
	var path: String = "%s/%s" % [absolute, FILE_PATTERN % int(report.get("timestamp_ms", 0))]
	if FileAccess.file_exists(path):
		return {"outcome": WRITE_EXISTS, "path": path}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"outcome": WRITE_FAILED, "path": path}
	file.store_string(JSON.stringify(report, "\t", false))
	file.close()
	return {"outcome": WRITE_OK, "path": path}


static func is_uuid_v5(value: String) -> bool:
	return RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").search(value) != null


static func _journey_entry(raw: Variant, sector_id: String) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var journey_id: String = String(source.get("journey_id", ""))
	var generation: Variant = _count(source.get("generation_count"))
	var writes: Variant = _count(source.get("canon_write_count"))
	var events_raw: Variant = source.get("reload_events")
	var events: Array = (events_raw as Array).duplicate(true) if events_raw is Array else []
	return {
		"journey_id": journey_id,
		"journey_id_valid": is_uuid_v5(journey_id),
		"player_guid": String(source.get("player_guid", "")),
		"generation_count": generation,
		"canon_write_count": writes,
		"observation_status": OBSERVED if generation != null and writes != null else NOT_OBSERVED,
		"reload_events": events,
		"reload_events_status": OBSERVED if events_raw is Array else NOT_OBSERVED,
		"reload_event_valid": _valid_reload(events, journey_id, sector_id),
	}


static func _count(value: Variant) -> Variant:
	if value is int and value >= 0:
		return value
	if value is float and is_finite(value) and value >= 0.0 and value == floorf(value):
		return int(value)
	return null


static func _identity_status(entries: Array) -> String:
	if entries.size() != 2:
		return NOT_OBSERVED if entries.size() < 2 else MISMATCH
	for entry: Dictionary in entries:
		if String(entry["journey_id"]).is_empty() or String(entry["player_guid"]).is_empty():
			return NOT_OBSERVED
		if not entry["journey_id_valid"]:
			return MISMATCH
	if entries[0]["journey_id"] == entries[1]["journey_id"] or entries[0]["player_guid"] == entries[1]["player_guid"]:
		return MISMATCH
	return MATCH


static func _zero_status(records: Array) -> String:
	for record: Dictionary in records:
		if record["observation_status"] != OBSERVED:
			return NOT_OBSERVED
	for record: Dictionary in records:
		if record["generation_count"] != 0 or record["canon_write_count"] != 0:
			return MISMATCH
	return MATCH


static func _reload_status(entries: Array) -> String:
	if entries.size() != 2:
		return NOT_OBSERVED
	for entry: Dictionary in entries:
		if entry["reload_events_status"] != OBSERVED:
			return NOT_OBSERVED
	for entry: Dictionary in entries:
		if not entry["reload_event_valid"]:
			return MISMATCH
	return MATCH


static func _valid_reload(events: Array, journey_id: String, sector_id: String) -> bool:
	if events.size() != 1 or not events[0] is Dictionary:
		return false
	var event: Dictionary = events[0]
	return (
		event.get("event_type") == RELOAD_EVENT_TYPE
		and not journey_id.is_empty()
		and String(event.get("journey_id", "")) == journey_id
		and String(event.get("sector_id", "")) == sector_id
		and not String(event.get("spatial_guid", "")).is_empty()
	)


static func _case_status(assertions: Variant) -> String:
	if not assertions is Array or (assertions as Array).is_empty():
		return NOT_OBSERVED
	for assertion: Variant in assertions:
		if not assertion is Dictionary or not (assertion as Dictionary).get("passed") is bool:
			return NOT_OBSERVED
	for assertion: Dictionary in assertions:
		if not assertion["passed"]:
			return MISMATCH
	return MATCH


static func _recovery_outcome(status: Dictionary) -> String:
	var exercised: bool = false
	var unobserved: bool = false
	var mismatch: bool = false
	for stage: String in PARITY_STAGES:
		if status[stage] == NOT_EXERCISED:
			continue
		exercised = true
		unobserved = unobserved or status[stage] == NOT_OBSERVED
		mismatch = mismatch or status[stage] == MISMATCH
	if not exercised:
		return NOT_EXERCISED
	if unobserved:
		return OUTCOME_OBSERVATION_FAILED
	return RECOVERY_FAILED if mismatch else RECOVERY_PARITY_MATCH


static func _sha1(value: Variant) -> Variant:
	if value == null:
		return null
	var text: String = value if value is String else JSON.stringify(value, "", true)
	return text.sha1_text()


static func _compare_base(expected: Variant, actual: Variant) -> Dictionary:
	var observed: bool = expected is String and actual is String
	var exact: bool = observed and expected == actual
	return {
		"exact_match": exact,
		"status": (MATCH if exact else MISMATCH) if observed else NOT_OBSERVED,
		"expected_sha1": _sha1(expected) if expected is String else null,
		"actual_sha1": _sha1(actual) if actual is String else null,
	}


static func _compare_mutations(expected: Variant, actual: Variant) -> Dictionary:
	var observed: bool = expected is Array and actual is Array
	var exact: bool = observed and (expected as Array).size() == (actual as Array).size()
	if exact:
		for index: int in range((expected as Array).size()):
			if JSON.stringify(expected[index], "", true) != JSON.stringify(actual[index], "", true):
				exact = false
				break
	return {
		"exact_match": exact,
		"status": (MATCH if exact else MISMATCH) if observed else NOT_OBSERVED,
		"mutation_count": {"expected": (expected as Array).size() if expected is Array else null, "actual": (actual as Array).size() if actual is Array else null},
		"expected_sequence_sha1": _sha1(expected) if expected is Array else null,
		"actual_sequence_sha1": _sha1(actual) if actual is Array else null,
	}


static func _compare_entities(expected: Variant, actual: Variant) -> Dictionary:
	var observed: bool = expected is Dictionary and actual is Dictionary
	var diffs: Array = []
	if observed:
		var guids: Array = (expected as Dictionary).keys()
		for guid: Variant in (actual as Dictionary).keys():
			if not guids.has(guid):
				guids.append(guid)
		guids.sort()
		for guid: Variant in guids:
			var want: Variant = expected.get(guid)
			var got: Variant = actual.get(guid)
			if not want is Dictionary or not got is Dictionary:
				diffs.append({"guid": guid, "field": null, "expected": want != null, "actual": got != null})
				continue
			var fields: Array = (want as Dictionary).keys()
			for field: Variant in (got as Dictionary).keys():
				if not fields.has(field):
					fields.append(field)
			fields.sort()
			for field: Variant in fields:
				if JSON.stringify(want.get(field), "", true) != JSON.stringify(got.get(field), "", true):
					diffs.append({"guid": guid, "field": field, "expected": want.get(field), "actual": got.get(field)})
	var exact: bool = observed and diffs.is_empty()
	return {
		"exact_match": exact,
		"status": (MATCH if exact else MISMATCH) if observed else NOT_OBSERVED,
		"expected_state_hash": _sha1(expected) if expected is Dictionary else null,
		"actual_state_hash": _sha1(actual) if actual is Dictionary else null,
		"entity_diffs": diffs,
	}
