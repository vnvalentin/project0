#!/usr/bin/env bash
# Builds the portable Windows 64-bit client package (Slice 006).
#
# Exports the "Windows Desktop" preset in export_presets.cfg (client runtime
# files only, see that preset's [preset.0.files] list) and zips the export
# output directory into a versioned, portable archive. Requires the Godot
# 4.3 Windows export templates to be installed
# (~/.local/share/godot/export_templates/4.3.stable/); without them the
# `godot --export-release` step fails and no ZIP is produced — this script
# does not fall back to faking a package.
#
# Usage:
#   scripts/export_windows_client.sh [version]
#
# version defaults to $PROJECT0_CLIENT_VERSION or 0.6.0 if unset. No
# gameplay, source, or server files are touched; this only packages the
# existing client runtime named in export_presets.cfg.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:-${PROJECT0_CLIENT_VERSION:-0.6.0}}"
STAGE_DIR="dist/windows"
PACKAGE_NAME="Project0-client-windows-x64-${VERSION}"
PACKAGE_DIR="dist/${PACKAGE_NAME}"
ZIP_PATH="dist/${PACKAGE_NAME}.zip"

rm -rf "${STAGE_DIR}" "${PACKAGE_DIR}" "${ZIP_PATH}"
mkdir -p "${STAGE_DIR}"

# Slice 144: stamp the version INTO the pack before exporting, so the running
# client can report its own build version to the server-owned pre-auth gate
# instead of the version existing only in this package's name. Restored on exit
# so an export never leaves the working tree re-versioned.
VERSION_CONTRACT="shared/client_build_version.gd"
VERSION_CONTRACT_BACKUP="$(mktemp)"
cp "${VERSION_CONTRACT}" "${VERSION_CONTRACT_BACKUP}"
SERVER_EXTENSION_STAGE="$(mktemp -d)"
SERVER_SQLITE_EXTENSION="addons/godot-sqlite/gdsqlite.gdextension"
EDITOR_EXTENSION_CACHE=".godot/extension_list.cfg"
restore_version_contract() {
	mv -f "${VERSION_CONTRACT_BACKUP}" "${VERSION_CONTRACT}"
	if [ -f "${SERVER_EXTENSION_STAGE}/gdsqlite.gdextension" ]; then
		mv -f "${SERVER_EXTENSION_STAGE}/gdsqlite.gdextension" "${SERVER_SQLITE_EXTENSION}"
	fi
	if [ -f "${SERVER_EXTENSION_STAGE}/extension_list.cfg" ]; then
		mv -f "${SERVER_EXTENSION_STAGE}/extension_list.cfg" "${EDITOR_EXTENSION_CACHE}"
	fi
	rmdir "${SERVER_EXTENSION_STAGE}" 2>/dev/null || true
}
trap restore_version_contract EXIT
scripts/stamp_client_build_version.sh "${VERSION}"

# DT-015: Godot regenerates .godot/extension_list.cfg from every .gdextension
# declaration it sees, even when both paths are excluded from the export filter.
# Hide the server-only declaration and its generated cache for this client export;
# the trap restores both before this script exits.
mv "${SERVER_SQLITE_EXTENSION}" "${SERVER_EXTENSION_STAGE}/gdsqlite.gdextension"
if [ -f "${EDITOR_EXTENSION_CACHE}" ]; then
	mv "${EDITOR_EXTENSION_CACHE}" "${SERVER_EXTENSION_STAGE}/extension_list.cfg"
fi

echo "Exporting Windows Desktop preset (version ${VERSION})..."
godot --headless --path . --export-release "Windows Desktop" "${STAGE_DIR}/Project0.exe"

mv "${STAGE_DIR}" "${PACKAGE_DIR}"

echo "Packaging portable ZIP..."
if command -v zip >/dev/null 2>&1; then
	(cd dist && zip -r -X "$(basename "${ZIP_PATH}")" "${PACKAGE_NAME}")
else
	(cd dist && python3 -m zipfile -c "$(basename "${ZIP_PATH}")" "${PACKAGE_NAME}")
fi

echo "Done: ${ZIP_PATH}"
