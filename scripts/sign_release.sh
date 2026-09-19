#!/usr/bin/env bash
# Slice 150 (Phase 16, F-037): sign a client release.
#
# Produces the two files the client fetches alongside the pack:
#   manifest.json  - required version, pack digest, size, and download URL
#   manifest.sig   - detached RSA signature over manifest.json's exact bytes
#
# Run this OFFLINE on the machine holding the private key. The key must never
# reach the enrollment host, this repository, or CI: the signature exists to
# survive those being compromised.
#
# Usage:
#   scripts/sign_release.sh <version> <path/to/Project0.pck> <base-url> [out-dir]
#
# Example:
#   scripts/sign_release.sh 0.7.0 dist/Project0.pck https://project0.valentin.vip/patches
#
# The private key path comes from PROJECT0_SIGNING_KEY (default:
# ~/project0-signing/project0-release-private.pem) so the path never has to be
# typed, and is never echoed.

set -euo pipefail

SIGNING_KEY="${PROJECT0_SIGNING_KEY:-${HOME}/project0-signing/project0-release-private.pem}"

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
	printf 'usage: %s <version> <pck-path> <base-url> [out-dir]\n' "$0" >&2
	exit 2
fi

VERSION="$1"
PCK_PATH="$2"
BASE_URL="${3%/}"
OUT_DIR="${4:-$(dirname "${PCK_PATH}")}"

# Same rule as ClientBuildVersion.is_valid; a release must never be published
# under a version the client's gate would refuse to parse.
if ! printf '%s' "${VERSION}" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
	printf 'sign: refusing malformed version: %s\n' "${VERSION}" >&2
	exit 1
fi
if [ ! -f "${PCK_PATH}" ]; then
	printf 'sign: pack not found: %s\n' "${PCK_PATH}" >&2
	exit 1
fi
if [ ! -f "${SIGNING_KEY}" ]; then
	printf 'sign: signing key not found: %s\n' "${SIGNING_KEY}" >&2
	printf 'sign: set PROJECT0_SIGNING_KEY or place the key at the default path.\n' >&2
	exit 1
fi
# TLS is not the trust anchor, but the client refuses a plaintext source outright.
case "${BASE_URL}" in
	https://*) ;;
	*) printf 'sign: base url must be https: %s\n' "${BASE_URL}" >&2; exit 1 ;;
esac

mkdir -p "${OUT_DIR}"
MANIFEST="${OUT_DIR}/manifest.json"
SIGNATURE="${OUT_DIR}/manifest.sig"

SHA256="$(openssl dgst -sha256 -r "${PCK_PATH}" | awk '{print $1}')"
SIZE="$(wc -c <"${PCK_PATH}" | tr -d '[:space:]')"

# Written compactly and signed byte-for-byte as emitted. The client verifies the
# bytes it received before parsing them, so this file must never be reformatted
# or re-serialized after signing.
printf '{"schema_version":1,"required_client_version":"%s","pck_sha256":"%s","pck_url":"%s/%s/Project0.pck","size_bytes":%s}' \
	"${VERSION}" "${SHA256}" "${BASE_URL}" "${VERSION}" "${SIZE}" >"${MANIFEST}"

openssl dgst -sha256 -sign "${SIGNING_KEY}" -out "${SIGNATURE}" "${MANIFEST}"

printf 'signed release %s\n' "${VERSION}"
printf '  pack      %s (%s bytes)\n' "${PCK_PATH}" "${SIZE}"
printf '  sha256    %s\n' "${SHA256}"
printf '  manifest  %s\n' "${MANIFEST}"
printf '  signature %s\n' "${SIGNATURE}"
printf '\nPublish to %s/%s/ :\n' "${BASE_URL}" "${VERSION}"
printf '  %s -> %s/manifest.json\n' "${MANIFEST}" "${BASE_URL}"
printf '  %s -> %s/manifest.sig\n' "${SIGNATURE}" "${BASE_URL}"
printf '  %s -> %s/%s/Project0.pck\n' "${PCK_PATH}" "${BASE_URL}" "${VERSION}"
