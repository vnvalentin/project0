extends RefCounted
class_name ClientBuildVersion
## Slice 144 (Phase 16, F-037): the packaged client's own build version — the
## authoritative identity the server-owned pre-auth version gate compares against.
##
## GENERATED VALUE: `CLIENT_BUILD_VERSION` is rewritten by
## `scripts/stamp_client_build_version.sh` (invoked from
## `scripts/export_windows_client.sh`) immediately before the Godot export, so the
## released `Project0.pck` carries the exact released version. It is checked in at
## the current default so source runs and the test suite are stable.
##
## The version lives INSIDE the pack on purpose: the Phase 16 integrity model
## signs a manifest binding a version to that pack's SHA-256, so a version an
## attacker could edit without invalidating the pack hash would be useless to the
## gate. Executable/product metadata stays informational only. See
## `.scratch/client-auto-update/spec.md` and
## `docs/adr/0008-windows-client-delivery-trust-and-rollback.md`.
##
## This is a delivery/build identity. It is unrelated to the data-contract
## `schema_version` / `tuning_version` fields used elsewhere in `shared/`.

## Stamped at export time. Keep the literal on one line: the stamp script
## rewrites exactly this assignment.
const CLIENT_BUILD_VERSION: String = "0.6.0"

const _PART_COUNT: int = 3


## The running client's build version.
static func current() -> String:
	return CLIENT_BUILD_VERSION


## Fail-closed `MAJOR.MINOR.PATCH` validation. Accepts only three dot-separated
## runs of digits with no sign, prefix, suffix, whitespace, or redundant leading
## zero, so a malformed or decorated version can never be stamped into a release
## or presented as an identity.
static func is_valid(version: Variant) -> bool:
	if not (version is String):
		return false
	var parts: PackedStringArray = (version as String).split(".", true)
	if parts.size() != _PART_COUNT:
		return false
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
		# `is_valid_int` accepts a sign; the identity must be plain digits.
		if part.length() > 1 and part.begins_with("0"):
			return false
		if not part.to_int() >= 0 or part.begins_with("-") or part.begins_with("+"):
			return false
	return true
