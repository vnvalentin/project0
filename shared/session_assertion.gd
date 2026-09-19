extends RefCounted
class_name SessionAssertion
## Slice 059: the versioned, bounded session-assertion contract shared by the
## login authority (issuer) and the authoritative game server (validator). Pure
## value/parse logic — no Crypto, no secret key, no authority. Per CLAUDE.md's
## Shared Contracts rule this lives in shared/ so both sides interpret an
## assertion identically; the signing/verification key stays server-only in
## server/assertion_issuer.gd and server/assertion_validator.gd.
##
## A token is `<payload_b64>.<sig_b64>`: the payload is canonical JSON of the
## claims below; the signature (produced/checked server-side) covers the exact
## payload_b64 bytes.

const SCHEMA_VERSION: int = 1
const MAX_FIELD_LEN: int = 256
## Slice 074: bound on the JSON-serialized Character cosmetic carried in a
## selected-Character assertion, so a signed token can never hold an unbounded
## presentation payload.
const MAX_COSMETIC_JSON_LEN: int = 1024

const KEY_VERSION: String = "v"
const KEY_SESSION_ID: String = "sid"
const KEY_ACCOUNT_ID: String = "aid"
const KEY_CHARACTER_ID: String = "cid"
const KEY_ISSUED_AT: String = "iat"
const KEY_EXPIRES_AT: String = "exp"
const KEY_ISSUER: String = "iss"
const KEY_AUDIENCE: String = "aud"
## Slice 074: additive, backward-compatible selected-Character presentation
## snapshot (empty for account-only assertions). Signed with the identity claims.
const KEY_CHARACTER_NAME: String = "cnm"
const KEY_CHARACTER_COSMETIC: String = "cos"

const OUTCOME_OK: String = "ok"
const REASON_MALFORMED: String = "malformed"
const REASON_UNSUPPORTED_VERSION: String = "unsupported_version"
const REASON_INVALID_CLAIMS: String = "invalid_claims"
const REASON_BAD_SIGNATURE: String = "bad_signature"
const REASON_WRONG_ISSUER: String = "wrong_issuer"
const REASON_WRONG_AUDIENCE: String = "wrong_audience"
const REASON_EXPIRED: String = "expired"
const REASON_NOT_YET_VALID: String = "not_yet_valid"

const _ORDERED_KEYS: Array[String] = [
	KEY_VERSION, KEY_SESSION_ID, KEY_ACCOUNT_ID, KEY_CHARACTER_ID,
	KEY_ISSUED_AT, KEY_EXPIRES_AT, KEY_ISSUER, KEY_AUDIENCE,
]

## Slice 074: the full ordered key set signed in the canonical payload. The
## identity claims (_ORDERED_KEYS) stay required on parse; the snapshot keys
## (cnm/cos) are additive \u2014 always emitted here, but tolerated and defaulted on
## parse so older snapshot-less tokens still validate.
const _SIGNED_KEYS: Array[String] = [
	KEY_VERSION, KEY_SESSION_ID, KEY_ACCOUNT_ID, KEY_CHARACTER_ID,
	KEY_ISSUED_AT, KEY_EXPIRES_AT, KEY_ISSUER, KEY_AUDIENCE,
	KEY_CHARACTER_NAME, KEY_CHARACTER_COSMETIC,
]


## Builds the canonical JSON payload for `claims`, always emitting the signed
## keys in a fixed order so the issuer and validator sign/verify identical
## bytes. Missing keys default to empty/zero (cosmetic to {}) — callers (the
## issuer) supply the fields they have.
static func build_payload(claims: Dictionary) -> String:
	var ordered: Dictionary = {}
	for key: String in _SIGNED_KEYS:
		ordered[key] = claims.get(key, _default_for_key(key))
	return JSON.stringify(ordered)


static func _default_for_key(key: String) -> Variant:
	if key == KEY_VERSION or key == KEY_ISSUED_AT or key == KEY_EXPIRES_AT:
		return 0
	if key == KEY_CHARACTER_COSMETIC:
		return {}
	return ""


## Parses and bounds-checks a canonical payload string. Returns
## { "outcome": OUTCOME_OK, "claims": Dictionary } with normalized typed values,
## or { "outcome": REASON_* } (no claims) fail-closed. Does NOT check the
## signature, issuer, audience, or time window — those are the validator's job.
static func parse_payload(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"outcome": REASON_MALFORMED}
	var raw: Dictionary = parsed
	for key: String in _ORDERED_KEYS:
		if not raw.has(key):
			return {"outcome": REASON_MALFORMED}

	var version_value: Variant = raw[KEY_VERSION]
	if not _is_number(version_value) or int(version_value) != SCHEMA_VERSION:
		return {"outcome": REASON_UNSUPPORTED_VERSION}

	var session_id: Variant = raw[KEY_SESSION_ID]
	var account_id: Variant = raw[KEY_ACCOUNT_ID]
	var character_id: Variant = raw[KEY_CHARACTER_ID]
	var issuer: Variant = raw[KEY_ISSUER]
	var audience: Variant = raw[KEY_AUDIENCE]
	if not _is_bounded_nonempty(session_id) or not _is_bounded_nonempty(account_id):
		return {"outcome": REASON_INVALID_CLAIMS}
	if not _is_bounded_nonempty(issuer) or not _is_bounded_nonempty(audience):
		return {"outcome": REASON_INVALID_CLAIMS}
	# character_id may be empty (account-only assertion) but still bounded.
	if not (character_id is String) or (character_id as String).length() > MAX_FIELD_LEN:
		return {"outcome": REASON_INVALID_CLAIMS}

	var issued_at: Variant = raw[KEY_ISSUED_AT]
	var expires_at: Variant = raw[KEY_EXPIRES_AT]
	if not _is_number(issued_at) or not _is_number(expires_at):
		return {"outcome": REASON_INVALID_CLAIMS}
	var iat: int = int(issued_at)
	var exp: int = int(expires_at)
	if iat < 0 or exp <= iat:
		return {"outcome": REASON_INVALID_CLAIMS}

	# Slice 074: additive Character snapshot — tolerated-and-defaulted for older
	# snapshot-less tokens, bounded when present. name may be empty (account-only).
	var character_name: Variant = raw.get(KEY_CHARACTER_NAME, "")
	if not (character_name is String) or (character_name as String).length() > MAX_FIELD_LEN:
		return {"outcome": REASON_INVALID_CLAIMS}
	var character_cosmetic: Variant = raw.get(KEY_CHARACTER_COSMETIC, {})
	if not (character_cosmetic is Dictionary) or JSON.stringify(character_cosmetic).length() > MAX_COSMETIC_JSON_LEN:
		return {"outcome": REASON_INVALID_CLAIMS}

	return {
		"outcome": OUTCOME_OK,
		"claims": {
			KEY_VERSION: SCHEMA_VERSION,
			KEY_SESSION_ID: String(session_id),
			KEY_ACCOUNT_ID: String(account_id),
			KEY_CHARACTER_ID: String(character_id),
			KEY_ISSUED_AT: iat,
			KEY_EXPIRES_AT: exp,
			KEY_ISSUER: String(issuer),
			KEY_AUDIENCE: String(audience),
			KEY_CHARACTER_NAME: String(character_name),
			KEY_CHARACTER_COSMETIC: character_cosmetic,
		},
	}


## Assembles a token from its two base64 parts.
static func encode_token(payload_b64: String, sig_b64: String) -> String:
	return "%s.%s" % [payload_b64, sig_b64]


## Splits a token into its payload and signature parts. Returns
## { "outcome": OUTCOME_OK, "payload_b64": String, "sig_b64": String } or
## { "outcome": REASON_MALFORMED } when the shape is wrong.
static func split_token(token: String) -> Dictionary:
	var parts: PackedStringArray = token.split(".", false)
	if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
		return {"outcome": REASON_MALFORMED}
	return {"outcome": OUTCOME_OK, "payload_b64": parts[0], "sig_b64": parts[1]}


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_bounded_nonempty(value: Variant) -> bool:
	return value is String and not (value as String).is_empty() and (value as String).length() <= MAX_FIELD_LEN
