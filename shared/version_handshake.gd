extends RefCounted
class_name VersionHandshake
## Slice 145 (Phase 16, F-037): the pre-auth version handshake — the contract by
## which a client declares its build version and the server decides whether to
## serve it, before any login or register RPC.
##
## Pure and side-effect free: this builds the request, resolves the server-owned
## expectation from configuration, and evaluates one against the other. It never
## sends, disconnects, or touches the scene tree; the enforcement slice wires it
## into the connect lifecycle.
##
## Authority: the CLIENT declares, the SERVER decides. Comparison is exact string
## equality — there is no "is newer" ordering, because ordering invites a client
## arguing it is new enough, and the server is the only authority on what it will
## serve. See `.scratch/client-auto-update/spec.md` and
## `docs/adr/0008-windows-client-delivery-trust-and-rollback.md`.

const ClientBuildVersionScript: Script = preload("res://shared/client_build_version.gd")

const SCHEMA_VERSION: int = 1

## Server-owned build version this server will serve. Defaults to the server
## build's own client version, so a stock server accepts its matching client.
const REQUIRED_VERSION_ENV_VAR: String = "PROJECT0_REQUIRED_CLIENT_VERSION"

## HTTPS base URL of the signed update manifest, handed to an outdated client so
## it can find its patch. Server-supplied on purpose: the trust anchor is the
## signature over the manifest, not this URL, so it can move without re-releasing
## clients (ADR 0008).
const MANIFEST_BASE_URL_ENV_VAR: String = "PROJECT0_UPDATE_MANIFEST_BASE_URL"

const OUTCOME_ACCEPTED: String = "ACCEPTED"
## The client's build version is not the one this server serves.
const OUTCOME_CLIENT_OUTDATED: String = "CLIENT_OUTDATED"
## The request is structurally wrong or carries no usable version.
const OUTCOME_MALFORMED: String = "MALFORMED"
## The operator's required-version configuration is unusable. Distinct from
## CLIENT_OUTDATED so an operator fault is never reported as the player's fault.
const OUTCOME_SERVER_MISCONFIGURED: String = "SERVER_MISCONFIGURED"
## Reserved for future handshake-protocol negotiation; unreachable today, since a
## structurally wrong request is MALFORMED. Named by the accepted contract.
const OUTCOME_UNSUPPORTED: String = "UNSUPPORTED"

const _HTTPS_PREFIX: String = "https://"


## The first message a client sends after connecting, before login or register.
static func request() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"client_build_version": ClientBuildVersionScript.current(),
	}


## The server-owned build version this server will serve. Returns "" when the
## override is set but malformed, so the caller fails closed rather than serving
## a mis-configured gate.
static func resolve_required_version() -> String:
	var override: String = OS.get_environment(REQUIRED_VERSION_ENV_VAR).strip_edges()
	if override.is_empty():
		return ClientBuildVersionScript.current()
	if not ClientBuildVersionScript.is_valid(override):
		return ""
	return override


## The HTTPS base URL of the signed update manifest. A non-HTTPS value is treated
## as unset so the server can never advertise a plaintext update source.
static func resolve_manifest_base_url() -> String:
	var configured: String = OS.get_environment(MANIFEST_BASE_URL_ENV_VAR).strip_edges()
	if not configured.begins_with(_HTTPS_PREFIX):
		return ""
	return configured


## Decide one client's handshake. Fail-closed: anything not provably acceptable
## is refused. Returns {outcome, detail, required_version, manifest_base_url};
## the caller replicates the required version and manifest URL only on
## CLIENT_OUTDATED, so a rejected client knows how to patch itself.
static func evaluate(client_request: Variant, required_version: String, manifest_base_url: String) -> Dictionary:
	# Operator fault is checked first: a malformed requirement must never be
	# reported to the player as their client being outdated.
	if not ClientBuildVersionScript.is_valid(required_version):
		return _result(OUTCOME_SERVER_MISCONFIGURED, "required client build version is not configured correctly", "", "")
	if not (client_request is Dictionary):
		return _result(OUTCOME_MALFORMED, "handshake is not a Dictionary", "", "")
	var data: Dictionary = client_request
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _result(OUTCOME_MALFORMED, "unsupported handshake schema_version", "", "")
	var declared: Variant = data.get("client_build_version")
	if not ClientBuildVersionScript.is_valid(declared):
		return _result(OUTCOME_MALFORMED, "client_build_version is missing or malformed", "", "")
	if String(declared) != required_version:
		return _result(
			OUTCOME_CLIENT_OUTDATED,
			"client build version does not match the required version",
			required_version,
			manifest_base_url
		)
	return _result(OUTCOME_ACCEPTED, "", required_version, "")


static func _result(outcome: String, detail: String, required_version: String, manifest_base_url: String) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
		"required_version": required_version,
		"manifest_base_url": manifest_base_url,
	}
