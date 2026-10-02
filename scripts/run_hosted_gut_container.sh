#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )); then
  echo "usage: $0 [full|--probe]" >&2
  exit 2
fi
mode="${1:-full}"
if [[ "$mode" != "full" && "$mode" != "--probe" ]]; then
  echo "usage: $0 [full|--probe]" >&2
  exit 2
fi

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# The source mount may have no usable Git metadata inside the image. Qualify
# identity on the host and pass only that value through the empty environment.
source_revision="$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || true)"
if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "VALIDATION GATE ERROR: hosted GUT requires a full host checkout HEAD." >&2
  exit 2
fi
if [[ ${M4_SOURCE_REVISION+x} && "$M4_SOURCE_REVISION" != "$source_revision" ]]; then
  echo "VALIDATION GATE ERROR: supplied M4 source revision differs from host checkout HEAD." >&2
  exit 2
fi
image="ghcr.io/vnvalentin/project0-godot@sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602"
install -d -m 2775 "$root/build/validation/runtime" "$root/.godot" "$root/logs/experiments"
container="project0-hosted-gut-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}-${GITHUB_JOB:-local}"
label="${PROJECT0_HOSTED_GUT_TEST_ID:-$container}"
if docker container inspect "$container" >/dev/null 2>&1; then
  echo "owned container already exists: $container" >&2
  exit 1
fi
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

container_command=(bash -c 'umask 0002; exec bash scripts/run_gut_validation.sh')
if [[ "$mode" == "--probe" ]]; then
  container_command=(bash -c 'if printf "unexpected write\n" > scripts/.hosted-write-probe 2>/dev/null; then exit 42; fi; umask 0002; printf "container evidence\n" > build/validation/container-probe.txt')
  if [[ "${PROJECT0_HOSTED_GUT_PROBE_FAIL:-0}" == "1" ]]; then
    container_command=(bash -c 'umask 0002; printf "failed container evidence\n" > build/validation/container-probe.txt; exit 23')
  fi
fi

set +e
docker run --rm --name "$container" --label "project0.hosted-gut=$label" \
  --user "$(id -u):$(id -g)" \
  --network none --no-healthcheck --read-only --cap-drop ALL \
  --security-opt no-new-privileges --tmpfs /tmp:rw,nosuid,nodev \
  -v "$root:/app:ro" -v "$root/.godot:/app/.godot" \
  -v "$root/build/validation:/app/build/validation" \
  -v "$root/logs/experiments:/app/logs/experiments" \
  -w /app --entrypoint /usr/bin/env "$image" \
  -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp/home \
  XDG_DATA_HOME=/tmp/data XDG_CONFIG_HOME=/tmp/config XDG_CACHE_HOME=/tmp/cache \
  TMPDIR=/tmp RESULT_DIR=build/validation DASHBOARD_RESULTS_DIR=/tmp/dashboard \
  PROJECT0_TEST_STATE_DIR=build/validation/runtime M4_SOURCE_REVISION="$source_revision" \
  "${container_command[@]}"
container_status=$?
set -e

if [[ "$mode" == "--probe" ]]; then
  artifact="$root/build/validation/container-probe.txt"
  probe_passed=false
  if [[ "$container_status" -eq 0 && -w "$artifact" \
        && "$(stat -c %u "$artifact")" == "$(id -u)" \
        && "$(stat -c %g "$artifact")" == "$(id -g)" ]]; then
    python_bin="${PYTHON_BIN:-python3}"
    "$python_bin" -c 'from pathlib import Path; Path("build/validation/result.json").write_text("host sealer write probe\n")'
    probe_passed=true
  fi
  cat > "$root/build/validation/hosted-container-tests.json" <<'EOF'
{
  "passed": PROBE_PASSED,
  "tests": 1,
  "failures": PROBE_FAILURES,
  "errors": 0,
  "skipped": 0
}
EOF
  if [[ "$probe_passed" == true ]]; then
    sed -i 's/PROBE_PASSED/true/; s/PROBE_FAILURES/0/' "$root/build/validation/hosted-container-tests.json"
  else
    sed -i 's/PROBE_PASSED/false/; s/PROBE_FAILURES/1/' "$root/build/validation/hosted-container-tests.json"
    if [[ "$container_status" -eq 0 ]]; then
      container_status=1
    fi
    exit "$container_status"
  fi
elif [[ "$container_status" -ne 0 ]]; then
  exit "$container_status"
fi