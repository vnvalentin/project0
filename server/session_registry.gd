extends RefCounted
class_name SessionRegistry
## Slice 040: server-only in-memory peer-to-session binding (see
## .scratch/player-accounts/handoff-040-account-auth-session.md and
## docs/slices/040-account-auth-session.md). Per CLAUDE.md's Runtime Ownership
## rule, sessions are never persisted and never appear in `shared/`/`client/` —
## a session exists only for the lifetime of one live ENet peer connection.
## Reconnect always finds no session and must fully re-authenticate.
##
## Keyed by peer_id (int), never by account_id, so a peer's session is trivial
## to clear in full on disconnect (server/server_main.gd's peer_disconnected
## handler) without touching any other connected peer's state.

var _sessions_by_peer_id: Dictionary = {}


## Public seam. Binds a fresh opaque CSPRNG session token to `peer_id`,
## replacing any prior session that peer held (there should never be one,
## since the auth dispatch rejects a second register/login as
## ALREADY_AUTHENTICATED before calling this). Returns the token.
func bind(peer_id: int, account_id: String, username: String) -> String:
	var token: String = _generate_token()
	_sessions_by_peer_id[peer_id] = {
		"session_token": token,
		"account_id": account_id,
		"username": username,
		"authenticated_at": Time.get_unix_time_from_system(),
	}
	return token


## Public seam. True while `peer_id` holds a bound session.
func is_authenticated(peer_id: int) -> bool:
	return _sessions_by_peer_id.has(peer_id)


## Public seam. Returns the bound session Dictionary for `peer_id`
## ({session_token, account_id, username, authenticated_at}), or an empty
## Dictionary if the peer holds no session.
func get_session(peer_id: int) -> Dictionary:
	return _sessions_by_peer_id.get(peer_id, {})


## Public seam. Clears any session bound to `peer_id`. Called on peer
## disconnect; a no-op (not an error) if the peer held no session.
func clear(peer_id: int) -> void:
	_sessions_by_peer_id.erase(peer_id)


func _generate_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(32).hex_encode()
