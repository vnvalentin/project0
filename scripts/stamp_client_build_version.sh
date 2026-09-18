#!/usr/bin/env bash
# Slice 144 (Phase 16, F-037): stamp the client build version into the in-pack
# contract `shared/client_build_version.gd` so the exported Project0.pck carries
# the exact released version.
#
# Usage:
#   scripts/stamp_client_build_version.sh <version>
#
# Deterministic and idempotent: stamping the same version twice produces a
# byte-identical file. Fail-closed: a malformed version is refused with a
# non-zero exit and the contract file is left untouched, so a release can never
# bake a decorated or partial version into the pack.
#
# Called by scripts/export_windows_client.sh, which restores the original file
# afterward so an export never leaves the working tree re-versioned.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

TARGET="shared/client_build_version.gd"

if [ "$#" -ne 1 ]; then
	printf 'usage: %s <version>\n' "$0" >&2
	exit 2
fi

VERSION="$1"

# Same rule as ClientBuildVersion.is_valid: MAJOR.MINOR.PATCH, digits only, no
# redundant leading zeros. Keep the two in lockstep.
if ! printf '%s' "${VERSION}" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
	printf 'stamp: refusing malformed client build version: %s\n' "${VERSION}" >&2
	exit 1
fi

if [ ! -f "${TARGET}" ]; then
	printf 'stamp: missing contract file: %s\n' "${TARGET}" >&2
	exit 1
fi

# Prefix-only guard and a substitution bounded by the closing quote, so the line
# is rewritten without assuming LF (a Windows checkout has CRLF, and anchoring on
# `"$` silently fails there) and whatever line ending exists is preserved.
if ! grep -q '^const CLIENT_BUILD_VERSION: String = "' "${TARGET}"; then
	printf 'stamp: %s does not contain the expected CLIENT_BUILD_VERSION assignment\n' "${TARGET}" >&2
	exit 1
fi

tmp="$(mktemp)"
sed "s/^const CLIENT_BUILD_VERSION: String = \"[^\"]*\"/const CLIENT_BUILD_VERSION: String = \"${VERSION}\"/" \
	"${TARGET}" >"${tmp}"
mv "${tmp}" "${TARGET}"

printf 'stamp: client build version = %s\n' "${VERSION}"
