extends RefCounted
class_name LoginRuntime
## Slice 068: server-only builder for the login authority's service graph, so the
## in-process game server (server/server_main.gd) and the standalone login
## process (server/login_server_main.gd) wire AuthService + CharacterService +
## LoginGateway (+ the Slice 059/060 assertion issuer/validator) identically from
## one source of truth. Server-only per CLAUDE.md: shared/ and client/ never
## construct it.
##
## It does NOT own the SQLite store or the account schema — the caller opens the
## store and ensures the schema first (matching each entrypoint's fail-closed
## boot order), then hands the repository here.

const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const LoginGatewayScript: Script = preload("res://server/login_gateway.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")

## Slice 060: session-assertion issuer/audience identifiers. The login authority
## issues under ASSERTION_ISSUER_ID; the game server accepts only that issuer and
## the ASSERTION_AUDIENCE it serves. Shared here so both entrypoints agree.
const ASSERTION_ISSUER_ID: String = "project0-login"
const ASSERTION_AUDIENCE: String = "project0-game"

## Slice 071: reported source of the resolved assertion secret (never the value).
const SECRET_SOURCE_CONFIGURED: String = "configured"
const SECRET_SOURCE_EPHEMERAL: String = "ephemeral"


## Resolves the shared HMAC secret (hex) for the assertion issuer/validator from
## PROJECT0_ASSERTION_SECRET. When unset, returns an ephemeral per-boot key. Logs
## only the source (never the secret) so a missing shared secret is observable.
## In-process, issuer and validator share one secret; a login-service split keeps
## the same configured secret on both sides (see Slice 071's assertion.env).
static func resolve_assertion_secret() -> String:
	var details: Dictionary = resolve_assertion_secret_details(OS.get_environment("PROJECT0_ASSERTION_SECRET"))
	if details["source"] == SECRET_SOURCE_EPHEMERAL:
		print("PROJECT0_ASSERTION_SECRET not set; using an ephemeral per-boot assertion key (dev only). The game and login processes will NOT share a secret until both load /etc/project0/assertion.env.")
	else:
		print("PROJECT0_ASSERTION_SECRET configured; using the shared assertion key.")
	return details["secret"]


## Pure resolver (no environment/logging) so it is deterministically testable.
## Returns { "secret": hex String, "source": SECRET_SOURCE_CONFIGURED | _EPHEMERAL }.
## A configured value is trimmed and passed through; an empty/whitespace value
## yields a fresh 32-byte key — it never returns a short or malformed secret.
static func resolve_assertion_secret_details(raw: String) -> Dictionary:
	var trimmed: String = raw.strip_edges()
	if trimmed.is_empty():
		return {"secret": Crypto.new().generate_random_bytes(32).hex_encode(), "source": SECRET_SOURCE_EPHEMERAL}
	return {"secret": trimmed, "source": SECRET_SOURCE_CONFIGURED}


## Builds the login service graph from an already-open account repository, adds
## the service nodes under `parent`, wires the assertion seams, and returns the
## handles: { "auth": AuthService, "characters": CharacterService,
## "gateway": LoginGateway }. AuthService/CharacterService are Nodes because
## register/login are coroutines that await get_tree().process_frame while PBKDF2
## runs off-thread — so `parent` must be inside the SceneTree. Slice 076:
## `account_authority` false builds an assertion-only gateway (the game server in
## a split deployment) that refuses register/login/Character-CRUD.
static func build_services(account_repository: Object, parent: Node, assertion_secret: String, issuer_id: String = ASSERTION_ISSUER_ID, audience: String = ASSERTION_AUDIENCE, account_authority: bool = true) -> Dictionary:
	var auth: Node = AuthServiceScript.new(account_repository)
	auth.name = "AuthService"
	parent.add_child(auth)

	var characters: Node = CharacterServiceScript.new(account_repository, auth.get_session_registry())
	characters.name = "CharacterService"
	parent.add_child(characters)

	var gateway: Node = LoginGatewayScript.new(auth, characters)
	gateway.name = "LoginGateway"
	parent.add_child(gateway)

	var issuer: Object = AssertionIssuerScript.new(assertion_secret, issuer_id, audience)
	var validator: Object = AssertionValidatorScript.new(assertion_secret, issuer_id, audience)
	gateway.set_assertion_seams(issuer, validator)
	gateway.set_account_authority_enabled(account_authority)

	return {"auth": auth, "characters": characters, "gateway": gateway}


## Slice 085: builds the game server's assertion-only login graph. It constructs
## NO AuthService — the game process holds no register/login/PBKDF2 code path and
## can never act as an accounts authority. A standalone SessionRegistry backs the
## CharacterService and the gateway; the gateway accepts only the assertion path
## (establish a session from a validated token, resolve the selected Character
## from the signed snapshot). Accounts live solely on the login process
## (build_services above). Returns { "characters", "gateway", "sessions" }.
static func build_assertion_only_services(account_repository: Object, parent: Node, assertion_secret: String, issuer_id: String = ASSERTION_ISSUER_ID, audience: String = ASSERTION_AUDIENCE) -> Dictionary:
	var sessions: Object = SessionRegistryScript.new()

	var characters: Node = CharacterServiceScript.new(account_repository, sessions)
	characters.name = "CharacterService"
	parent.add_child(characters)

	var gateway: Node = LoginGatewayScript.new(null, characters, sessions)
	gateway.name = "LoginGateway"
	parent.add_child(gateway)

	var issuer: Object = AssertionIssuerScript.new(assertion_secret, issuer_id, audience)
	var validator: Object = AssertionValidatorScript.new(assertion_secret, issuer_id, audience)
	gateway.set_assertion_seams(issuer, validator)

	return {"characters": characters, "gateway": gateway, "sessions": sessions}
