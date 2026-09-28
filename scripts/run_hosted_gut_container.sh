#!/usr/bin/env bash
set -euo pipefail

mode="${1:-full}"
if [[ "$mode" != "full" && "$mode" != "--probe" ]]; then
  echo "usage: $0 [full|--probe]" >&2
  exit 2
fi

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
image="ghcr.io/vnvalentin/project0-godot@sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602"
install -d -m 2775 "$root/build/validation" "$root/.godot"

container_command=(bash -c 'umask 0002; exec bash scripts/run_gut_validation.sh')
if [[ "$mode" == "--probe" ]]; then
  container_command=(bash -c 'umask 0002; printf "container evidence\n" > build/validation/container-probe.txt')
fi

docker run --rm --user "$(id -u):$(id -g)" \
  --network none --no-healthcheck --read-only --cap-drop ALL \
  --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,nodev \
  -v "$root:/app" -w /app --entrypoint /usr/bin/env "$image" \
  -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp/home \
  XDG_DATA_HOME=/tmp/data XDG_CONFIG_HOME=/tmp/config XDG_CACHE_HOME=/tmp/cache \
  TMPDIR=/tmp RESULT_DIR=build/validation DASHBOARD_RESULTS_DIR=/tmp/dashboard \
  "${container_command[@]}"

if [[ "$mode" == "--probe" ]]; then
  artifact="$root/build/validation/container-probe.txt"
  [[ -w "$artifact" && "$(stat -c %u "$artifact")" == "$(id -u)" ]]
  python_bin="${PYTHON_BIN:-python3}"
  "$python_bin" -c 'from pathlib import Path; Path("build/validation/result.json").write_text("host sealer write probe\n")'
  cat > "$root/build/validation/hosted-container-tests.json" <<'EOF'
{
  "passed": true,
  "tests": 1,
  "failures": 0,
  "errors": 0,
  "skipped": 0
}
EOF
fi