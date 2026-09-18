#!/usr/bin/env bash
set -euo pipefail

# Publish the CI-built Windows launcher and portable ZIP beside the signed
# updater artifacts. The enrollment container serves this directory read-only.

VERSION="${1:-}"
SOURCE_DIR="${2:-dist/current}"
PATCHES_DIR="${PROJECT0_PATCHES_DIR:-/var/lib/project0/patches}"

if [[ ! "${VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
	echo "publish: refusing malformed version: ${VERSION}" >&2
	exit 2
fi

launcher="${SOURCE_DIR}/Project0-WAN-${VERSION}.exe"
launcher_archive="${SOURCE_DIR}/Project0-WAN-${VERSION}.zip"
archive="${SOURCE_DIR}/Project0-client-windows-x64-${VERSION}.zip"
manifest="${SOURCE_DIR}/deployment-manifest.json"
for artifact in "${launcher}" "${launcher_archive}" "${archive}" "${manifest}"; do
	[[ -s "${artifact}" ]] || {
		echo "publish: missing artifact: ${artifact}" >&2
		exit 1
	}
done

download_dir="${PATCHES_DIR}/downloads/${VERSION}"
sudo -n install -d -m 0755 "${download_dir}"
sudo -n install -m 0644 "${launcher}" "${download_dir}/"
sudo -n install -m 0644 "${launcher_archive}" "${download_dir}/"
sudo -n install -m 0644 "${archive}" "${download_dir}/"
sudo -n install -m 0644 "${manifest}" "${download_dir}/"

tmp_page="$(mktemp)"
trap 'rm -f "${tmp_page}"' EXIT
cat >"${tmp_page}" <<EOF
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Project0 downloads</title></head>
<body>
<main>
<h1>Project0 downloads</h1>
<p>Windows client ${VERSION}</p>
<ul>
<li><a href="${VERSION}/Project0-WAN-${VERSION}.exe">Download Windows launcher</a></li>
<li><a href="${VERSION}/Project0-WAN-${VERSION}.zip">Download launcher ZIP</a></li>
<li><a href="${VERSION}/Project0-client-windows-x64-${VERSION}.zip">Download portable client ZIP</a></li>
</ul>
</main>
</body>
</html>
EOF
sudo -n install -m 0644 "${tmp_page}" "${PATCHES_DIR}/downloads/index.html"
echo "publish: client downloads available under ${PATCHES_DIR}/downloads/${VERSION}"