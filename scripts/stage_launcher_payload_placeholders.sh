#!/usr/bin/env bash
# Stages placeholder files for native/windows_launcher/payload/.
#
# main.go declares `//go:embed payload/**`, and the real payload (the exported
# Godot client, its PCK, and the wgnetstack DLL) is a build artifact that is
# deliberately never committed. Without at least one file present the embed
# directive fails and the package cannot be compiled, so `go test ./...` cannot
# run in CI on a clean checkout.
#
# These placeholders satisfy the embed directive only. They are NOT a runnable
# client: the launcher tests exercise enrollment/config logic, not payload
# contents. `scripts/build_windows_oneclick.ps1` and the release packaging path
# both wipe and repopulate this directory with the real artifacts, so a
# placeholder can never be shipped by those paths.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

payload="native/windows_launcher/payload"

if [[ -f "${payload}/Project0.exe" && ! -f "${payload}/.placeholder" ]]; then
	echo "Real launcher payload present; leaving ${payload} untouched."
	exit 0
fi

dll="libwgnetstack_gdext.windows.template_release.x86_64.dll"
nested="${payload}/native/wgnetstack/gdext/build"

rm -rf "${payload}"
mkdir -p "${nested}"

printf 'placeholder\n' >"${payload}/.placeholder"
printf 'placeholder\n' >"${payload}/Project0.exe"
printf 'placeholder\n' >"${payload}/Project0.pck"
printf 'placeholder\n' >"${payload}/${dll}"
printf 'placeholder\n' >"${nested}/${dll}"

echo "Staged placeholder payload in ${payload}."
