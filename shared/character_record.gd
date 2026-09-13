extends RefCounted
class_name CharacterRecord
## Slice 039: pure, versioned, bounded, fail-closed value contracts for the
## Account/Character domain (see .scratch/player-accounts/spec.md
## Implementation Slice 1 and docs/slices/039-accounts-characters-repository.md).
## Matches CLAUDE.md's Shared Contracts rule: no DB handle, no secrets, no
## authority. `AccountHandle` never carries salt/hash material — only
## `account_id` + `username`. Rejection reasons are bounded String constants in
## the SectorBlueprintSchema/CombatContracts OUTCOME_* style so they serialize
## directly for telemetry/RPC without a separate lookup step.
##
## `vessel_seam` deliberately carries no Phase 12 values — it is a
## forward-compatible, nullable placeholder column only (see CLAUDE.md's
## "Current Reality And Target Contract").

const SCHEMA_VERSION: int = 1

## Auth rejection reasons (spec ticket 04 / handoff scope).
const REJECT_UNSUPPORTED_VERSION: String = "UNSUPPORTED_VERSION"
const REJECT_MALFORMED: String = "MALFORMED"
const REJECT_BAD_CREDENTIALS: String = "BAD_CREDENTIALS"
const REJECT_USERNAME_TAKEN: String = "USERNAME_TAKEN"
const REJECT_ACCOUNT_LOCKED: String = "ACCOUNT_LOCKED"
const REJECT_ALREADY_AUTHENTICATED: String = "ALREADY_AUTHENTICATED"

## Character rejection reasons (spec ticket 05 / handoff scope).
const REJECT_NAME_TAKEN: String = "NAME_TAKEN"
const REJECT_NAME_INVALID: String = "NAME_INVALID"
const REJECT_CHARACTER_CAP_REACHED: String = "CHARACTER_CAP_REACHED"
const REJECT_NOT_OWNER: String = "NOT_OWNER"
const REJECT_NO_SUCH_CHARACTER: String = "NO_SUCH_CHARACTER"
const REJECT_ALREADY_DELETED: String = "ALREADY_DELETED"

## `display_name` bounds (spec ticket 05 / handoff scope).
const DISPLAY_NAME_MIN_LENGTH: int = 3
const DISPLAY_NAME_MAX_LENGTH: int = 20
const _DISPLAY_NAME_CHARSET_PATTERN: String = "^[A-Za-z0-9 _-]+$"

## The maximum number of live (non-deleted) Characters one Account may own.
const MAX_CHARACTERS_PER_ACCOUNT: int = 5

static var _charset_regex: RegEx = null


## Public seam. Validates a requested `display_name` against length, charset,
## and spacing rules. Returns true only for a name this contract accepts;
## uniqueness/cap checks are the repository's job (they require DB state this
## pure contract does not have). Fails closed: anything not explicitly
## permitted is rejected.
static func is_valid_display_name(display_name: Variant) -> bool:
	if not (display_name is String):
		return false
	var name: String = display_name
	if name.length() < DISPLAY_NAME_MIN_LENGTH or name.length() > DISPLAY_NAME_MAX_LENGTH:
		return false
	if name.begins_with(" ") or name.ends_with(" ") or name.contains("  "):
		return false
	if _get_charset_regex().search(name) == null:
		return false
	return true


static func _get_charset_regex() -> RegEx:
	if _charset_regex == null:
		_charset_regex = RegEx.new()
		_charset_regex.compile(_DISPLAY_NAME_CHARSET_PATTERN)
	return _charset_regex


var schema_version: int
var character_id: String
var account_id: String
var display_name: String
var cosmetic: Dictionary
var created_at: int
var last_played_at: int
var deleted: bool
var vessel_seam: Variant


func _init(
	p_character_id: String,
	p_account_id: String,
	p_display_name: String,
	p_cosmetic: Dictionary,
	p_created_at: int,
	p_last_played_at: int,
	p_deleted: bool = false,
	p_vessel_seam: Variant = null
) -> void:
	schema_version = SCHEMA_VERSION
	character_id = p_character_id
	account_id = p_account_id
	display_name = p_display_name
	cosmetic = p_cosmetic
	created_at = p_created_at
	last_played_at = p_last_played_at
	deleted = p_deleted
	vessel_seam = p_vessel_seam
