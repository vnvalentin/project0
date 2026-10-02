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

var _store: SqliteStore
var _interactions: Dictionary = {}


func _init(store: SqliteStore) -> void:
	_store = store


func ensure_schema() -> Dictionary:
	return _store.query("""
		CREATE TABLE IF NOT EXISTS plot_claims (
			plot_id TEXT PRIMARY KEY,
			owner_character_id TEXT NOT NULL,
			claim_revision INTEGER NOT NULL CHECK(claim_revision > 0),
			registration_operation_id TEXT NOT NULL
		);
	""")


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
	var observed: Dictionary = get_claim(plot_id)
	if observed.outcome != "ok":
		return observed
	if observed.claim.owner_character_id != actor_character_id:
		return _result("permission_denied")
	if _interactions.size() >= MAX_INTERACTIONS:
		return _result("interaction_limit")
	var interaction_id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	_interactions[interaction_id] = {
		"actor_character_id": actor_character_id, "plot_id": plot_id,
		"required_bits": required_bits, "claim_revision": observed.claim.claim_revision,
	}
	return {"outcome": "ok", "interaction_id": interaction_id}


static func _valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_ID_LENGTH and value.strip_edges() == value


static func _valid_bits(value: Variant) -> bool:
	return value is int and value > 0 and (value & ~ALL_PERMISSIONS) == 0


static func _result(outcome: String) -> Dictionary:
	return {"outcome": outcome}
