extends SceneTree

const StoreScript: Script = preload("res://server/sqlite_store.gd")
const AuthorityScript: Script = preload("res://server/claim_permit_authority.gd")
const DatabaseName: String = "claim-permit-process-recovery.db"
const ResultRoot: String = "res://build/validation/850/process-recovery/"
const PlotId: String = "plot-process-recovery"
const OwnerId: String = "owner-process-recovery"
const MemberId: String = "member-process-recovery"
const VisitorId: String = "visitor-process-recovery"
const PartyId: String = "party-process-recovery"
const PermissionBits: int = 4

var _store: SqliteStore
var _phase: String
var _state_path: String
var _report_path: String
var _errors: Array[String] = []
var _checks: Dictionary = {}
var _details: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 3:
		quit(2)
		return
	_phase = arguments[0]
	_state_path = arguments[1]
	_report_path = arguments[2]
	var result_root: String = ProjectSettings.globalize_path(ResultRoot)
	_check(_phase in ["prepare", "recover"], "valid_phase")
	_check(_state_path.begins_with(result_root) and _state_path.ends_with("/expected.json"), "owned_expected_state_path")
	_check(_report_path.begins_with(result_root) and _report_path.ends_with("/%s.json" % _phase), "owned_phase_report_path")
	var xdg_data_home: String = OS.get_environment("XDG_DATA_HOME")
	_check(xdg_data_home.begins_with("/tmp/project0-850-recovery-"), "isolated_xdg_data_home")
	_check(ProjectSettings.globalize_path("user://").begins_with(xdg_data_home + "/"), "isolated_user_data_path")
	if not _errors.is_empty():
		_finish()
		return

	var expected: Dictionary = {}
	if _phase == "recover":
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(_state_path))
		_check(loaded is Dictionary and loaded.has_all(["schema_version", "plot_id", "owner_character_id", "member_character_id", "visitor_character_id", "permit_intent", "permit_result"]), "expected_state_valid")
		if _errors.is_empty():
			expected = loaded

	var database_exists: bool = FileAccess.file_exists("user://" + DatabaseName)
	_check(database_exists == (_phase == "recover"), "isolated_database_precondition")
	if not _errors.is_empty():
		_finish()
		return

	_store = StoreScript.new()
	var opened: Dictionary = _store.open(DatabaseName)
	_check(opened.get("outcome", "") == "ok", "database_opened")
	if _errors.is_empty():
		var authority: RefCounted = AuthorityScript.new(_store)
		_check(authority.ensure_schema().outcome == "ok", "authority_schema_ready")
		if _errors.is_empty():
			if _phase == "prepare":
				_prepare(authority)
			else:
				_recover(authority, expected)
	_finish()


func _prepare(authority: RefCounted) -> void:
	var claim: Dictionary = authority.register_claim(PlotId, OwnerId, "provision-process-recovery")
	if not _check(claim.get("outcome", "") == "ok", "claim_registered"):
		return
	var membership: Dictionary = authority.update_memberships(
		MemberId,
		[{"kind": "party", "id": PartyId, "role": ""}],
		0,
		"membership-process-recovery"
	)
	if not _check(membership.get("outcome", "") == "ok", "membership_projection_written"):
		return
	var intent: Dictionary = {
		"schema_version": 1,
		"operation_id": "permit-process-recovery",
		"plot_id": PlotId,
		"expected_revision": 1,
		"action": "grant",
		"subject": {"kind": "party", "id": PartyId, "role": ""},
		"permission_bits": PermissionBits,
	}
	var permit: Dictionary = authority.apply_permit(OwnerId, intent)
	if not _check(permit.get("outcome", "") == "ok", "permit_committed"):
		return
	var state: Dictionary = {
		"schema_version": 1,
		"plot_id": PlotId,
		"owner_character_id": OwnerId,
		"member_character_id": MemberId,
		"visitor_character_id": VisitorId,
		"permit_intent": intent,
		"permit_result": permit,
	}
	_check(_write_json(_state_path, state), "expected_state_retained")
	_details["claim_revision_after_permit"] = permit.get("revision", -1)
	_details["permit_operation_id"] = permit.get("operation_id", "")


func _recover(authority: RefCounted, expected: Dictionary) -> void:
	var claim: Dictionary = authority.get_claim(expected.plot_id)
	var claim_record: Dictionary = claim.get("claim", {})
	_check(claim.get("outcome", "") == "ok", "claim_recovered")
	_check(claim_record.get("owner_character_id", "") == expected.owner_character_id, "owner_recovered")
	_check(claim_record.get("claim_revision", -1) == expected.permit_result.get("revision", -2), "claim_revision_recovered")
	var member: Dictionary = authority.begin_interaction(expected.member_character_id, expected.plot_id, PermissionBits)
	_check(member.get("outcome", "") == "ok", "member_permission_recovered")
	if member.get("outcome", "") == "ok":
		authority.cancel_interaction(expected.member_character_id, member.interaction_id)
	var visitor: Dictionary = authority.begin_interaction(expected.visitor_character_id, expected.plot_id, PermissionBits)
	_check(visitor.get("outcome", "") == "permission_denied", "unauthorized_visitor_still_denied")
	var observation_start: Dictionary = _store.start_dml_observation()
	_check(observation_start.get("observation_status", "") == "OBSERVED", "replay_observation_started")
	var replay: Dictionary = authority.apply_permit(expected.owner_character_id, expected.permit_intent)
	_check(replay.get("outcome", "") == "duplicate_rejected", "permit_receipt_replayed")
	_check(replay.get("original_result", {}) == expected.permit_result, "original_permit_result_preserved")
	var observation: Dictionary = _store.dml_statement_counters()
	_details["observation"] = observation
	_check(_zero_dml(observation), "receipt_replay_zero_dml")
	_details["claim_revision"] = claim_record.get("claim_revision", -1)
	_details["member_outcome"] = member.get("outcome", "")
	_details["visitor_outcome"] = visitor.get("outcome", "")
	_details["receipt_replay_outcome"] = replay.get("outcome", "")
	_details["native_row_effects"] = observation.get("native_row_effects", "NOT_OBSERVED")


func _zero_dml(observation: Dictionary) -> bool:
	if observation.get("observation_status", "") != "OBSERVED" or observation.get("native_row_effects", "") != "NOT_OBSERVED":
		return false
	var totals: Variant = observation.get("totals")
	if not _zero_windows(totals):
		return false
	var tables: Variant = observation.get("by_table")
	if not tables is Dictionary:
		return false
	for counts: Variant in tables.values():
		if not _zero_windows(counts):
			return false
	return true


func _zero_windows(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["attempted", "committed", "rolled_back", "failed"]):
		return false
	for window: String in ["attempted", "committed", "rolled_back", "failed"]:
		var counts: Variant = value[window]
		if not counts is Dictionary or not counts.has_all(["insert", "replace", "update", "delete"]):
			return false
		for operation: String in ["insert", "replace", "update", "delete"]:
			if not counts[operation] is int or counts[operation] != 0:
				return false
	return true


func _check(condition: bool, name: String) -> bool:
	_checks[name] = condition
	if not condition:
		_errors.append(name)
	return condition


func _write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	var result: Error = file.get_error()
	file.close()
	return result == OK


func _finish() -> void:
	if _store != null and _store.is_open():
		_store.close()
	var passed: bool = _errors.is_empty()
	var report: Dictionary = {
		"schema_version": 1,
		"issue": 850,
		"phase": _phase,
		"process_id": OS.get_process_id(),
		"status": "passed" if passed else "failed",
		"checks": _checks,
		"errors": _errors,
		"details": _details,
		"native_row_effects": "NOT_OBSERVED",
	}
	if not _write_json(_report_path, report):
		push_error("process recovery phase report could not be retained")
		quit(1)
		return
	quit(0 if passed else 1)