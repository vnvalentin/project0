#!/usr/bin/env bash
# Builds the complete Windows client deliverable on Linux (Slice 103).
#
# This is the CI-reproducible counterpart to scripts/build_current_deployment.ps1,
# which only ever ran on a Windows workstation with a hand-built DLL. Everything
# here cross-compiles, so a Linux runner can produce the shipped artifacts:
#
#   1. wgnetstack Go bridge  -> Windows static c-archive (mingw-w64)
#   2. wgnetstack GDExtension -> Windows DLL (scons + mingw-w64 g++)
#   3. Godot client          -> Windows .exe + .pck (export templates)
#   4. WAN launcher          -> Windows .exe with the above embedded (GOOS=windows)
#   5. Portable ZIP + deployment-manifest.json with SHA256s
#
# Host prerequisites (see docs/slices/103-linux-client-package-build.md):
#   godot 4.3 + 4.3.stable export templates, go >= 1.23, scons,
#   x86_64-w64-mingw32-gcc, x86_64-w64-mingw32-g++, zip, git
#
# Usage: scripts/package_client_linux.sh [version]

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo="$(pwd)"

VERSION="${1:-${PROJECT0_CLIENT_VERSION:-0.12.0}}"
OUT_DIR="${PROJECT0_PACKAGE_DIR:-dist/current}"
# Pinned to the revision the shipped Windows DLL was built against (Slice 035).
GODOT_CPP_REF="${PROJECT0_GODOT_CPP_REF:-d5cc777a89d899665fb61f1650ef0dc0cf6488c4}"

DLL_NAME="libwgnetstack_gdext.windows.template_release.x86_64.dll"
GDEXT_DIR="native/wgnetstack/gdext"
STAGE="build/client-package/stage"
PAYLOAD="native/windows_launcher/payload"
SCONS_JOBS="${SCONS_JOBS:-$(nproc 2>/dev/null || echo 2)}"
VERSION_CONTRACT="shared/client_build_version.gd"
VERSION_CONTRACT_BACKUP="$(mktemp)"

restore_version_contract() {
	mv -f "${VERSION_CONTRACT_BACKUP}" "${VERSION_CONTRACT}"
}
trap restore_version_contract EXIT

log() { printf '\n== %s\n' "$*"; }

require_tool() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "ERROR: required tool '$1' not found. $2" >&2
		exit 1
	}
}

log "Checking cross-build toolchain"
require_tool godot "Install Godot 4.3 plus the 4.3.stable export templates."
require_tool go "Install Go >= 1.23."
require_tool scons "Install with 'pip install scons' or 'apt-get install scons'."
# The host-side GDExtension and its cgo archive need a NATIVE toolchain, not
# just the mingw cross-compilers.
require_tool gcc "Install build-essential (native gcc is needed for the Linux host build)."
require_tool g++ "Install build-essential (native g++ is needed for the Linux host build)."
require_tool x86_64-w64-mingw32-gcc "Install mingw-w64."
require_tool x86_64-w64-mingw32-g++ "Install g++-mingw-w64-x86-64."
require_tool zip "Install zip."
require_tool git "Install git."

# Godot resolves export templates under $HOME. GitHub Actions overrides HOME for
# container jobs, which hides templates that the image installed under another
# user's home, so link them into place instead of assuming a fixed location.
ensure_export_templates() {
	local version="4.3.stable"
	local target="${HOME}/.local/share/godot/export_templates/${version}"
	[[ -d "${target}" ]] && { echo "  export templates: ${target}"; return 0; }
	local candidate
	for candidate in \
		"/root/.local/share/godot/export_templates/${version}" \
		"/usr/local/share/godot/export_templates/${version}" \
		"/usr/share/godot/export_templates/${version}"; do
		if [[ -d "${candidate}" ]]; then
			mkdir -p "$(dirname "${target}")"
			ln -sfn "${candidate}" "${target}"
			echo "  export templates linked from ${candidate}"
			return 0
		fi
	done
	echo "ERROR: Godot ${version} export templates not found under \$HOME (${HOME}) or any known image location." >&2
	exit 1
}
ensure_export_templates

log "Preparing godot-cpp at ${GODOT_CPP_REF}"
if [[ ! -d "${GDEXT_DIR}/godot-cpp/.git" ]]; then
	rm -rf "${GDEXT_DIR}/godot-cpp"
	git clone --quiet --branch 4.3 https://github.com/godotengine/godot-cpp.git "${GDEXT_DIR}/godot-cpp"
fi
git -C "${GDEXT_DIR}/godot-cpp" fetch --quiet origin
git -C "${GDEXT_DIR}/godot-cpp" checkout --quiet "${GODOT_CPP_REF}"

log "Building wgnetstack Windows c-archive"
make -C native/wgnetstack cgoarchive-windows

log "Building wgnetstack GDExtension Windows DLL"
(cd "${GDEXT_DIR}" && scons -j"${SCONS_JOBS}" platform=windows target=template_release use_mingw=yes)
dll_built="${GDEXT_DIR}/build/${DLL_NAME}"
[[ -f "${dll_built}" ]] || { echo "ERROR: GDExtension DLL not produced at ${dll_built}" >&2; exit 1; }

# Godot runs this export ON Linux, and addons/wgnetstack/wgnetstack.gdextension
# maps linux.editor.x86_64 to the template_debug .so. Godot loads the HOST
# platform's library before it will export any preset, so without this the
# Windows export aborts with "configuration errors". Building it here is what
# makes the package reproducible on a clean runner.
log "Building wgnetstack Linux c-archive (export host)"
make -C native/wgnetstack cgoarchive

log "Building wgnetstack GDExtension Linux .so (export host)"
(cd "${GDEXT_DIR}" && scons -j"${SCONS_JOBS}" platform=linux target=template_debug)
host_so="${GDEXT_DIR}/build/libwgnetstack_gdext.linux.template_debug.x86_64.so"
[[ -f "${host_so}" ]] || { echo "ERROR: host GDExtension not produced at ${host_so}" >&2; exit 1; }

log "Exporting Godot Windows client"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
scripts/stamp_client_build_version.sh "${VERSION}"
godot --headless --import >/dev/null 2>&1 || true
# The headless export emits GDExtension load warnings for the Windows-only DLL
# and can exit nonzero while still writing complete artifacts, so the artifacts
# themselves are the pass/fail signal rather than the exit code.
export_status=0
godot --headless --path . --export-release "Windows Desktop" "${STAGE}/Project0.exe" || export_status=$?
for required in Project0.exe Project0.pck; do
	[[ -s "${STAGE}/${required}" ]] || {
		echo "ERROR: Godot export did not produce ${required} (exit ${export_status})" >&2
		exit 1
	}
done
if [[ "${export_status}" -ne 0 ]]; then
	echo "WARNING: godot export exited ${export_status} but produced complete artifacts."
fi
cp "${dll_built}" "${STAGE}/${DLL_NAME}"

log "Building WAN launcher for Windows"
rm -rf "${PAYLOAD}"
mkdir -p "${PAYLOAD}/native/wgnetstack/gdext/build"
cp "${STAGE}/Project0.exe" "${STAGE}/Project0.pck" "${STAGE}/${DLL_NAME}" "${PAYLOAD}/"
cp "${STAGE}/${DLL_NAME}" "${PAYLOAD}/native/wgnetstack/gdext/build/"

mkdir -p "${OUT_DIR}"
launcher_out="${repo}/${OUT_DIR}/Project0-WAN-${VERSION}.exe"
(cd native/windows_launcher && GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-H=windowsgui" -o "${launcher_out}" .)
[[ -s "${launcher_out}" ]] || { echo "ERROR: launcher build produced no output" >&2; exit 1; }

log "Packaging portable ZIP"
package_name="Project0-client-windows-x64-${VERSION}"
zip_path="${repo}/${OUT_DIR}/${package_name}.zip"
rm -f "${zip_path}"
(cd "${STAGE}" && zip -q -r -X "${zip_path}" .)

log "Writing deployment manifest"
manifest="${OUT_DIR}/deployment-manifest.json"
source_commit="$(git -C "${repo}" rev-parse --short HEAD)"
tree_dirty=false
[[ -n "$(git -C "${repo}" status --porcelain)" ]] && tree_dirty=true

{
	printf '{\n'
	printf '  "version": "%s",\n' "${VERSION}"
	printf '  "built_at_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '  "source_commit": "%s",\n' "${source_commit}"
	printf '  "source_tree_dirty": %s,\n' "${tree_dirty}"
	printf '  "godot_export_exit_code": %s,\n' "${export_status}"
	printf '  "godot_cpp_ref": "%s",\n' "${GODOT_CPP_REF}"
	printf '  "artifacts": [\n'
	first=true
	for artifact in "${zip_path}" "${launcher_out}"; do
		[[ "${first}" == true ]] || printf ',\n'
		first=false
		printf '    { "name": "%s", "bytes": %s, "sha256": "%s" }' \
			"$(basename "${artifact}")" \
			"$(stat -c %s "${artifact}")" \
			"$(sha256sum "${artifact}" | cut -d' ' -f1)"
	done
	printf '\n  ]\n}\n'
} >"${manifest}"

log "Client package ready in ${OUT_DIR}"
ls -l "${OUT_DIR}"
