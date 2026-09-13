extends RefCounted
class_name AccountHandle
## Slice 039: the client-facing Account DTO (see
## .scratch/player-accounts/spec.md and
## docs/slices/039-accounts-characters-repository.md). Carries only
## `account_id` + `username` — NEVER the PBKDF2 salt/hash. Pure value object,
## no DB handle, no authority, per CLAUDE.md's Shared Contracts rule.

const SCHEMA_VERSION: int = 1

var schema_version: int
var account_id: String
var username: String


func _init(p_account_id: String, p_username: String) -> void:
	schema_version = SCHEMA_VERSION
	account_id = p_account_id
	username = p_username
