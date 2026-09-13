extends Node
class_name AuthService
## Slice 040: server-only account authentication and session dispatch (see
## .scratch/player-accounts/handoff-040-account-auth-session.md and
## docs/slices/040-account-auth-session.md). Wraps the Slice 039
## AccountCharacterRepository (consumed unmodified), the Slice 040
## PasswordHasher (pure core, consumed for its synchronous hash_password/
## verify_password functions), and the Slice 040 SessionRegistry (in-memory,
## never persisted). server/server_main.gd owns exactly one instance of this
## node and forwards register/login RPC calls to it, mirroring how it forwards
## movement/action intents to each peer's ServerPlayerState.
##
## Threading: hash_password/verify_password are pure and synchronous
## (server/password_hasher.gd), but PBKDF2 is deliberately slow. Running it on
## the main thread would stall the authoritative simulation tick for every
## connected peer while one register/login is processed. Both register() and
## login() below run their PasswordHasher call on a WorkerThreadPool task and
## `await` its completion via a process_frame poll loop — the calling
## coroutine suspends (so server_main.gd's dispatch returns immediately) but
## nothing blocks the main thread while the worker thread hashes.

const PasswordHasherScript: Script = preload("res://server/password_hasher.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const CharacterRecordScript: Script = preload("res://shared/character_record.gd")
const AccountHandleScript: Script = preload("res://shared/account_handle.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")

## Outcome/reason strings returned to server_main.gd for the auth_result RPC.
## OUTCOME_OK reuses AccountCharacterRepository's own "ok" so callers can treat
## every rejection uniformly as a CharacterRecord.REJECT_* String.
const OUTCOME_OK: String = "ok"

var _repository: AccountCharacterRepository = null
var _sessions: SessionRegistry = SessionRegistryScript.new()


## Public seam. Must be called once after the caller opens a SqliteStore and
## the repository's ensure_schema() has already succeeded — this class never
## opens the store or creates the schema itself (server_main.gd's boot
## sequence owns that fail-closed step, matching the hub-fixture pattern).
func _init(repository: AccountCharacterRepository) -> void:
	_repository = repository


## Public seam. True while `peer_id` holds a bound session — server_main.gd's
## disconnect handler and any future session-gated RPC consult this instead of
## reaching into the SessionRegistry directly.
func is_authenticated(peer_id: int) -> bool:
	return _sessions.is_authenticated(peer_id)


## Public seam. Clears `peer_id`'s session, if any. Called from
## server_main.gd's existing _on_peer_disconnected handler.
func clear_session(peer_id: int) -> void:
	_sessions.clear(peer_id)


## Public seam. Registers a new Account for `peer_id` and auto-authenticates
## it on success (binds a session immediately — no separate login step is
## required after registering). Returns:
##   {"outcome": OUTCOME_OK, "account_id": String, "username": String}
##   {"outcome": CharacterRecord.REJECT_MALFORMED, "detail": String}
##   {"outcome": CharacterRecord.REJECT_USERNAME_TAKEN, "detail": String}
##   {"outcome": CharacterRecord.REJECT_ALREADY_AUTHENTICATED, "detail": String}
func register(peer_id: int, username: String, password: String) -> Dictionary:
	if _sessions.is_authenticated(peer_id):
		return _reject(CharacterRecordScript.REJECT_ALREADY_AUTHENTICATED, "Peer %d already holds a session." % peer_id)

	var malformed: String = _validate_credentials(username, password)
	if not malformed.is_empty():
		return _reject(CharacterRecordScript.REJECT_MALFORMED, malformed)

	var hashed: Dictionary = await _hash_off_thread(password, PasswordHasherScript.DEFAULT_ITERATIONS)

	var create_result: Dictionary = _repository.create_account(username, hashed["salt"], hashed["hash"], hashed["iterations"])
	if create_result["outcome"] != OUTCOME_OK:
		return _reject(create_result["outcome"], create_result.get("detail", ""))

	var account: AccountHandle = create_result["account"]
	_sessions.bind(peer_id, account.account_id, account.username)
	return {
		"outcome": OUTCOME_OK,
		"account_id": account.account_id,
		"username": account.username,
	}


## Public seam. Verifies `username`/`password` against the stored PBKDF2
## record and, on match, binds a session for `peer_id`. Unknown username and
## wrong password both return the identical BAD_CREDENTIALS reason (no user
## enumeration). Returns the same result shape as register().
func login(peer_id: int, username: String, password: String) -> Dictionary:
	if _sessions.is_authenticated(peer_id):
		return _reject(CharacterRecordScript.REJECT_ALREADY_AUTHENTICATED, "Peer %d already holds a session." % peer_id)

	var malformed: String = _validate_credentials(username, password)
	if not malformed.is_empty():
		return _reject(CharacterRecordScript.REJECT_MALFORMED, malformed)

	var lookup: Dictionary = _repository.find_account_by_username(username)
	if lookup["outcome"] != OUTCOME_OK:
		# Unknown user: still pay the hashing cost against a fixed dummy record
		# so an attacker cannot distinguish "unknown user" from "wrong password"
		# by response latency, matching the no-enumeration requirement beyond
		# just the returned reason string.
		await _hash_off_thread(password, PasswordHasherScript.DEFAULT_ITERATIONS)
		return _reject(CharacterRecordScript.REJECT_BAD_CREDENTIALS, "Unknown username or wrong password.")

	var verified: bool = await _verify_off_thread(password, lookup["pbkdf2_salt"], lookup["pbkdf2_hash"], lookup["pbkdf2_iterations"])
	if not verified:
		return _reject(CharacterRecordScript.REJECT_BAD_CREDENTIALS, "Unknown username or wrong password.")

	_sessions.bind(peer_id, lookup["account_id"], lookup["username"])
	return {
		"outcome": OUTCOME_OK,
		"account_id": lookup["account_id"],
		"username": lookup["username"],
	}


func _validate_credentials(username: Variant, password: Variant) -> String:
	if not (username is String) or (username as String).is_empty():
		return "username must be a non-empty string."
	if not (password is String) or (password as String).is_empty():
		return "password must be a non-empty string."
	return ""


## Runs PasswordHasher.hash_password on a WorkerThreadPool task so the slow
## PBKDF2 derivation never blocks the main thread / authoritative tick, then
## awaits its completion via a process_frame poll loop (this coroutine
## suspends; the caller's own await already made this an async call).
func _hash_off_thread(password: String, iterations: int) -> Dictionary:
	var output: Array = [{}]
	var task_id: int = WorkerThreadPool.add_task(func() -> void:
		output[0] = PasswordHasherScript.hash_password(password, iterations)
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	return output[0]


## Runs PasswordHasher.verify_password on a WorkerThreadPool task, mirroring
## _hash_off_thread's polling pattern, so a login attempt's constant-time
## verification also never blocks the main thread.
func _verify_off_thread(password: String, salt_hex: String, hash_hex: String, iterations: int) -> bool:
	var output: Array = [false]
	var task_id: int = WorkerThreadPool.add_task(func() -> void:
		output[0] = PasswordHasherScript.verify_password(password, salt_hex, hash_hex, iterations)
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	return output[0]


func _reject(outcome: String, detail: String) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
	}
