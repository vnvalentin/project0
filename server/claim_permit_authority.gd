extends RefCounted
class_name ClaimPermitAuthority
## Server-only explicit plot permissions; #850 and ADR0014.
## Callers supply authenticated Character identity and trusted plot provisioning.
## This component does not establish a physical Area3D interaction or a plot's
## existence in Canon. No method is a client RPC endpoint.

const ENTER: int = 1
const CONTAINER: int = 2
const BUILD: int = 4
const MODIFY: int = 8
const TRANSFER: int = 16
const ADMINISTER_PERMITS: int = 32
const ALL_PERMISSIONS: int = 63
const MAX_ID_LENGTH: int = 128
const MAX_INTERACTIONS: int = 256
const MAX_REVISION: int = 1073741824
const MAX_MEMBERSHIPS: int = 64

var _store: SqliteStore
var _interactions: Dictionary = {}


func _init(store: SqliteStore) -> void:
	_store = store


func ensure_schema() -> Dictionary:
	var statements: Array[String] = [
		"CREATE TABLE IF NOT EXISTS plot_claims (plot_id TEXT PRIMARY KEY, owner_character_id TEXT NOT NULL, claim_revision INTEGER NOT NULL CHECK(claim_revision > 0), registration_operation_id TEXT NOT NULL);",
		"CREATE TABLE IF NOT EXISTS plot_permits (plot_id TEXT NOT NULL REFERENCES plot_claims(plot_id), subject_kind TEXT NOT NULL, subject_id TEXT NOT NULL, subject_role TEXT NOT NULL, permission_bits INTEGER NOT NULL, PRIMARY KEY(plot_id, subject_kind, subject_id, subject_role));",
		"CREATE TABLE IF NOT EXISTS permission_member_revisions (character_id TEXT PRIMARY KEY, membership_revision INTEGER NOT NULL, operation_id TEXT NOT NULL);",
		"CREATE TABLE IF NOT EXISTS permission_memberships (character_id TEXT NOT NULL REFERENCES permission_member_revisions(character_id), subject_kind TEXT NOT NULL, subject_id TEXT NOT NULL, subject_role TEXT NOT NULL, PRIMARY KEY(character_id, subject_kind, subject_id, subject_role));",
	]
	for statement: String in statements:
		var result: Dictionary = _store.query(statement)
		if result.outcome != "ok":
			return _result(String(result.outcome))
	return _result("ok")


## Trusted server provisioning, never a player ownership assertion.
func register_claim(plot_id: Variant, owner_character_id: Variant, operation_id: Variant) -> Dictionary:
	if not _valid_id(plot_id) or not _valid_id(owner_character_id) or not _valid_id(operation_id):
		return _result("invalid_request")
	var observed: Dictionary = get_claim(plot_id)
	if observed.outcome == "ok":
		if observed.claim.owner_character_id == owner_character_id and observed.claim.registration_operation_id == operation_id:
			return _result("duplicate_rejected")
		return _result("claim_conflict")
	if observed.outcome != "not_found":
		return observed
	var transaction: Dictionary = _store.transaction(func() -> bool:
		return _store.query_with_bindings(
			"INSERT INTO plot_claims (plot_id, owner_character_id, claim_revision, registration_operation_id) VALUES (?, ?, 1, ?);",
			[plot_id, owner_character_id, operation_id]
		).outcome == "ok"
	)
	return _result(String(transaction.outcome))


func get_claim(plot_id: Variant) -> Dictionary:
	if not _valid_id(plot_id):
		return _result("invalid_request")
	var query: Dictionary = _store.query_with_bindings(
		"SELECT plot_id, owner_character_id, claim_revision, registration_operation_id FROM plot_claims WHERE plot_id = ?;", [plot_id]
	)
	if query.outcome != "ok":
		return _result(String(query.outcome))
	if query.rows.is_empty():
		return _result("not_found")
	var claim: Dictionary = query.rows[0]
	if not _valid_id(claim.owner_character_id) or not (claim.claim_revision is int) or claim.claim_revision <= 0:
		return _result("invalid_persisted_state")
	return {"outcome": "ok", "claim": claim.duplicate(true)}


## The returned handle is retained by server interaction state, not client input.
func begin_interaction(actor_character_id: Variant, plot_id: Variant, required_bits: Variant) -> Dictionary:
	if not _valid_id(actor_character_id) or not _valid_id(plot_id) or not _valid_bits(required_bits):
		return _result("invalid_request")
	var observed: Dictionary = _permission_snapshot(actor_character_id, plot_id)
	if observed.outcome != "ok":
		return observed
	if (observed.permission_bits & required_bits) != required_bits:
		return _result("permission_denied")
	if _interactions.size() >= MAX_INTERACTIONS:
		return _result("interaction_limit")
	var interaction_id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	_interactions[interaction_id] = {
		"actor_character_id": actor_character_id, "plot_id": plot_id,
		"required_bits": required_bits, "claim_revision": observed.claim_revision,
		"membership_revision": observed.membership_revision,
	}
	return {"outcome": "ok", "interaction_id": interaction_id}


static func _valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_ID_LENGTH and value.strip_edges() == value


static func _valid_bits(value: Variant) -> bool:
	return value is int and value > 0 and (value & ~ALL_PERMISSIONS) == 0


static func _result(outcome: String) -> Dictionary:
	return {"outcome": outcome}


## Trusted upstream membership projection. This is never a player command.
func update_memberships(character_id: Variant, memberships: Variant, expected_revision: Variant, operation_id: Variant) -> Dictionary:
	if not _valid_id(character_id) or not _valid_id(operation_id) or not _valid_revision(expected_revision):
		return _result("invalid_request")
	if not (memberships is Array) or memberships.size() > MAX_MEMBERSHIPS:
		return _result("invalid_request")
	var seen: Dictionary = {}
	var party_count: int = 0
	for subject: Variant in memberships:
		if not _valid_subject(subject) or subject.kind == "character":
			return _result("invalid_request")
		var key: String = _subject_key(subject.kind, subject.id, subject.role)
		if seen.has(key):
			return _result("invalid_request")
		seen[key] = true
		if subject.kind == "party":
			party_count += 1
	if party_count > 1:
		return _result("invalid_request")
	var decision: Dictionary = _result("ok")
	var transaction: Dictionary = _store.transaction(func() -> bool:
		var current: Dictionary = _membership_revision(character_id)
		if current.outcome != "ok":
			decision.outcome = current.outcome
			return false
		if current.revision != expected_revision or current.revision >= MAX_REVISION:
			decision.outcome = "revision_mismatch"
			return false
		var revision_write: Dictionary
		if current.revision == 0:
			revision_write = _store.query_with_bindings("INSERT INTO permission_member_revisions (character_id, membership_revision, operation_id) VALUES (?, ?, ?);", [character_id, 1, operation_id])
		else:
			revision_write = _store.query_with_bindings("UPDATE permission_member_revisions SET membership_revision = ?, operation_id = ? WHERE character_id = ?;", [current.revision + 1, operation_id, character_id])
		if revision_write.outcome != "ok":
			return false
		if _store.query_with_bindings("DELETE FROM permission_memberships WHERE character_id = ?;", [character_id]).outcome != "ok":
			return false
		for subject: Dictionary in memberships:
			if _store.query_with_bindings("INSERT INTO permission_memberships (character_id, subject_kind, subject_id, subject_role) VALUES (?, ?, ?, ?);", [character_id, subject.kind, subject.id, subject.role]).outcome != "ok":
				return false
		return true
	)
	return decision if decision.outcome != "ok" else _result(String(transaction.outcome))


## Actor identity is supplied by authenticated server dispatch, never the intent.
func apply_permit(actor_character_id: Variant, intent: Variant) -> Dictionary:
	var fields: PackedStringArray = ["schema_version", "operation_id", "plot_id", "expected_revision", "action", "subject", "permission_bits"]
	if not _valid_id(actor_character_id) or not _exact_fields(intent, fields):
		return _result("invalid_request")
	if not (intent.schema_version is int) or intent.schema_version != 1 or intent.action != "grant":
		return _result("invalid_request")
	if not _valid_id(intent.operation_id) or not _valid_id(intent.plot_id) or not _valid_revision(intent.expected_revision):
		return _result("invalid_request")
	if not _valid_subject(intent.subject) or not _valid_bits(intent.permission_bits):
		return _result("invalid_request")
	var decision: Dictionary = _result("ok")
	var transaction: Dictionary = _store.transaction(func() -> bool:
		var current: Dictionary = _permission_snapshot(actor_character_id, intent.plot_id)
		if current.outcome != "ok":
			decision.outcome = current.outcome
			return false
		if current.claim_revision != intent.expected_revision or current.claim_revision >= MAX_REVISION:
			decision.outcome = "revision_mismatch"
			return false
		if (current.permission_bits & ADMINISTER_PERMITS) == 0 or (current.permission_bits & intent.permission_bits) != intent.permission_bits:
			decision.outcome = "permission_denied"
			return false
		var subject: Dictionary = intent.subject
		var existing: Dictionary = _store.query_with_bindings("SELECT permission_bits FROM plot_permits WHERE plot_id = ? AND subject_kind = ? AND subject_id = ? AND subject_role = ?;", [intent.plot_id, subject.kind, subject.id, subject.role])
		if existing.outcome != "ok":
			return false
		var grant_write: Dictionary
		if existing.rows.is_empty():
			grant_write = _store.query_with_bindings("INSERT INTO plot_permits (plot_id, subject_kind, subject_id, subject_role, permission_bits) VALUES (?, ?, ?, ?, ?);", [intent.plot_id, subject.kind, subject.id, subject.role, intent.permission_bits])
		else:
			grant_write = _store.query_with_bindings("UPDATE plot_permits SET permission_bits = ? WHERE plot_id = ? AND subject_kind = ? AND subject_id = ? AND subject_role = ?;", [intent.permission_bits, intent.plot_id, subject.kind, subject.id, subject.role])
		if grant_write.outcome != "ok":
			return false
		return _store.query_with_bindings("UPDATE plot_claims SET claim_revision = ? WHERE plot_id = ?;", [current.claim_revision + 1, intent.plot_id]).outcome == "ok"
	)
	return decision if decision.outcome != "ok" else _result(String(transaction.outcome))


func _membership_revision(character_id: String) -> Dictionary:
	var query: Dictionary = _store.query_with_bindings("SELECT membership_revision FROM permission_member_revisions WHERE character_id = ?;", [character_id])
	if query.outcome != "ok":
		return _result(String(query.outcome))
	if query.rows.is_empty():
		return {"outcome": "ok", "revision": 0}
	var revision: Variant = query.rows[0].membership_revision
	if not _valid_revision(revision) or revision == 0:
		return _result("invalid_persisted_state")
	return {"outcome": "ok", "revision": revision}


func _permission_snapshot(actor_character_id: String, plot_id: String) -> Dictionary:
	var observed: Dictionary = get_claim(plot_id)
	if observed.outcome != "ok":
		return observed
	var membership: Dictionary = _membership_revision(actor_character_id)
	if membership.outcome != "ok":
		return membership
	var members: Dictionary = _store.query_with_bindings("SELECT subject_kind, subject_id, subject_role FROM permission_memberships WHERE character_id = ?;", [actor_character_id])
	var grants: Dictionary = _store.query_with_bindings("SELECT subject_kind, subject_id, subject_role, permission_bits FROM plot_permits WHERE plot_id = ?;", [plot_id])
	if members.outcome != "ok" or grants.outcome != "ok":
		return _result("query_failed")
	var eligible: Dictionary = {_subject_key("character", actor_character_id, ""): true}
	for member: Dictionary in members.rows:
		if not _valid_subject({"kind": member.subject_kind, "id": member.subject_id, "role": member.subject_role}) or member.subject_kind == "character":
			return _result("invalid_persisted_state")
		eligible[_subject_key(member.subject_kind, member.subject_id, member.subject_role)] = true
	var bits: int = ALL_PERMISSIONS if observed.claim.owner_character_id == actor_character_id else 0
	for grant: Dictionary in grants.rows:
		if not _valid_bits(grant.permission_bits) or not _valid_subject({"kind": grant.subject_kind, "id": grant.subject_id, "role": grant.subject_role}):
			return _result("invalid_persisted_state")
		if eligible.has(_subject_key(grant.subject_kind, grant.subject_id, grant.subject_role)):
			bits |= grant.permission_bits
	return {"outcome": "ok", "permission_bits": bits, "claim_revision": observed.claim.claim_revision, "membership_revision": membership.revision}


static func _valid_subject(subject: Variant) -> bool:
	if not _exact_fields(subject, ["kind", "id", "role"]) or not _valid_id(subject.id) or not (subject.role is String):
		return false
	if subject.kind == "faction_role":
		return _valid_id(subject.role)
	return subject.kind in ["character", "party"] and subject.role == ""


static func _subject_key(kind: String, subject_id: String, role: String) -> String:
	return JSON.stringify([kind, subject_id, role])


static func _valid_revision(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_REVISION


static func _exact_fields(value: Variant, fields: PackedStringArray) -> bool:
	if not (value is Dictionary) or value.size() != fields.size():
		return false
	for key: Variant in value:
		if not (key is String) or not fields.has(key):
			return false
	return true


## The action writer must use this same store, synchronously, without nested
## transactions. Authenticated actor identity and the handle come from server
## interaction state. Grant and membership reads share the write transaction.
func commit_interaction(actor_character_id: Variant, interaction_id: Variant, write_body: Callable) -> Dictionary:
	if not _valid_id(actor_character_id) or not _valid_id(interaction_id) or not write_body.is_valid():
		return _result("invalid_request")
	if not _interactions.has(interaction_id):
		return _result("interaction_not_found")
	var initial: Dictionary = _interactions[interaction_id]
	if initial.actor_character_id != actor_character_id:
		return _result("interaction_actor_mismatch")
	_interactions.erase(interaction_id)
	var decision: Dictionary = _result("ok")
	var transaction: Dictionary = _store.transaction(func() -> bool:
		var current: Dictionary = _permission_snapshot(actor_character_id, initial.plot_id)
		if current.outcome != "ok":
			decision.outcome = current.outcome
			return false
		if current.claim_revision != initial.claim_revision or current.membership_revision != initial.membership_revision:
			decision.outcome = "stale_authority"
			return false
		if (current.permission_bits & initial.required_bits) != initial.required_bits:
			decision.outcome = "permission_denied"
			return false
		var written: Variant = write_body.call()
		return written is bool and written
	)
	return decision if decision.outcome != "ok" else _result(String(transaction.outcome))


## Explicit teardown for disconnect/cancel paths; no persistent write.
func cancel_interaction(actor_character_id: Variant, interaction_id: Variant) -> Dictionary:
	if not _valid_id(actor_character_id) or not _valid_id(interaction_id):
		return _result("invalid_request")
	if not _interactions.has(interaction_id):
		return _result("interaction_not_found")
	if _interactions[interaction_id].actor_character_id != actor_character_id:
		return _result("interaction_actor_mismatch")
	_interactions.erase(interaction_id)
	return _result("ok")
