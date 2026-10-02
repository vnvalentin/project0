extends RefCounted
## #1347: conservative direct-statement observation, not native affected rows.
## Never retain SQL or bindings. Unsupported observation never changes execution.

const OPERATIONS: PackedStringArray = ["insert", "replace", "update", "delete"]
const WINDOWS: PackedStringArray = ["attempted", "committed", "rolled_back", "failed"]

var _window_id: int = 0
var _connection_id: int = 0
var _active: bool = false
var _counts: Dictionary = {}
var _tables: Dictionary = {}
var _reasons: Array[String] = []
var _history: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _target: RegEx = RegEx.create_from_string("(?i)^(INSERT(?:\\s+OR\\s+(?:ROLLBACK|ABORT|REPLACE|FAIL|IGNORE))?\\s+INTO|REPLACE\\s+INTO|UPDATE(?:\\s+OR\\s+(?:ROLLBACK|ABORT|REPLACE|FAIL|IGNORE))?|DELETE\\s+FROM)\\s+([A-Za-z_][A-Za-z0-9_]*)(?=\\s|\\(|$)")


func start(connection_id: int, tables: Array[String], reasons: Array[String]) -> Dictionary:
	if _active:
		_history.append(_snapshot())
	_window_id += 1
	_connection_id = connection_id
	_active = true
	_counts = _empty_counts()
	_tables = {}
	for table: String in tables:
		_tables[table] = _empty_counts()
	_reasons.clear()
	for reason: String in reasons:
		if not _reasons.has(reason):
			_reasons.append(reason)
	_pending.clear()
	return report()


func invalidate(reason: String) -> void:
	if _active and not _reasons.has(reason):
		_reasons.append(reason)


func report() -> Dictionary:
	var result: Dictionary = _snapshot()
	result["previous_windows"] = _history.duplicate(true)
	return result


func observe(sql: String, succeeded: bool, in_transaction: bool) -> void:
	if not _active:
		return
	var statement: String = _single_statement(sql)
	if statement.is_empty():
		invalidate("unsupported_or_multiple_statements")
		return
	var match_result: RegExMatch = _target.search(statement)
	if match_result == null:
		if RegEx.create_from_string("(?i)^SELECT\\s+").search(statement) != null:
			return
		if RegEx.create_from_string("(?i)^PRAGMA\\s+(?:user_version|foreign_keys|journal_mode)$").search(statement) != null:
			return
		invalidate("unsupported_statement")
		return
	var operation: String = match_result.get_string(1).split(" ")[0].to_lower()
	# Whitespace may be tabs/newlines. Classify using the first keyword alone.
	if operation.begins_with("insert"):
		operation = "insert"
	elif operation.begins_with("replace"):
		operation = "replace"
	elif operation.begins_with("update"):
		operation = "update"
	else:
		operation = "delete"
	var table: String = match_result.get_string(2).to_lower()
	_increment("attempted", operation, table)
	if not succeeded:
		_increment("failed", operation, table)
	elif in_transaction:
		_pending.append({"operation": operation, "table": table})
	else:
		_increment("committed", operation, table)


func finish_transaction(disposition: String) -> void:
	if disposition != "committed" and disposition != "rolled_back":
		invalidate("transaction_disposition_not_observed")
	else:
		for statement: Dictionary in _pending:
			_increment(disposition, statement["operation"], statement["table"])
	_pending.clear()


func _increment(window: String, operation: String, table: String) -> void:
	if not _tables.has(table):
		_tables[table] = _empty_counts()
	_counts[window][operation] += 1
	_tables[table][window][operation] += 1


func _snapshot() -> Dictionary:
	var observed: bool = _active and _reasons.is_empty()
	return {
		"scope": "direct_single_statements_through_this_store",
		"window_id": _window_id, "connection_id": _connection_id,
		"observation_status": "OBSERVED" if observed else "NOT_OBSERVED",
		"reasons": _reasons.duplicate() if _active else ["window_not_started"],
		"native_row_effects": "NOT_OBSERVED",
		"totals": _counts.duplicate(true) if observed else "NOT_OBSERVED",
		"by_table": _tables.duplicate(true) if observed else "NOT_OBSERVED",
		"partial_counts": {"totals": _counts.duplicate(true), "by_table": _tables.duplicate(true)},
	}


func _empty_counts() -> Dictionary:
	var counts: Dictionary = {}
	for window: String in WINDOWS:
		counts[window] = {}
		for operation: String in OPERATIONS:
			counts[window][operation] = 0
	return counts


## Bound statement splitting without interpreting full SQLite grammar. Quoted
## identifiers/comments/CTEs remain unsupported. Semicolons inside SQL string
## literals are safe; doubled single quotes follow SQLite string escaping.
func _single_statement(sql: String) -> String:
	var result: String = ""
	var quoted: bool = false
	var terminated: bool = false
	var index: int = 0
	while index < sql.length():
		var character: String = sql[index]
		if quoted:
			if character == "'":
				if index + 1 < sql.length() and sql[index + 1] == "'":
					index += 2
					continue
				quoted = false
			index += 1
			continue
		if character == "'":
			if terminated:
				return ""
			quoted = true
			result += "?"
		elif character == ";":
			if terminated:
				return ""
			terminated = true
		elif character in ["\"", "`", "["]:
			return ""
		elif index + 1 < sql.length() and sql.substr(index, 2) in ["--", "/*"]:
			return ""
		elif terminated and not character.strip_edges().is_empty():
			return ""
		elif not terminated:
			result += character
		index += 1
	return "" if quoted else result.strip_edges()
