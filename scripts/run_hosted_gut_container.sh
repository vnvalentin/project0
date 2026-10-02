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
base_image="ghcr.io/vnvalentin/project0-godot@sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602"
image="project0-gut-validation:local"
install -d -m 2775 "$root/build/validation/runtime" "$root/.godot" "$root/logs/experiments"
container="project0-hosted-gut-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}-${GITHUB_JOB:-local}"
label="${PROJECT0_HOSTED_GUT_TEST_ID:-$container}"
if docker container inspect "$container" >/dev/null 2>&1; then
  echo "owned container already exists: $container" >&2
  exit 1
fi

# Build context contains only the validation recipe. No source checkout or
# private host state is sent to the builder; the caller owns the shared lock.
record_image_failure() {
  local build_code="$1"
  local attempted="${2:-true}"
  local python_bin="${PYTHON_BIN:-python3}"
  local summary="$root/build/validation/validation-summary.json"
  if ! "$python_bin" - "$summary" "$build_code" "$source_revision" "$attempted" >/dev/null 2>&1 <<'PYREPORT'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": 1, "runner": "GUT", "status": "failed", "stage": "validation-image",
    "dependency": "validation-image-python-git", "exit_code": int(sys.argv[2]),
    "image_build_exit_code": int(sys.argv[2]) if sys.argv[4] == "true" else "NOT_OBSERVED",
    "image_build_attempted": sys.argv[4] == "true", "source_revision": sys.argv[3],
    "scripts_ran": 0, "gut_execution": "NOT_OBSERVED",
}, indent=2) + "\n")
PYREPORT
  then
    # Fixed fallback requires no host interpreter and cannot report success.
    cat > "$summary" <<'FALLBACK'
{"schema_version":1,"runner":"GUT","status":"failed","stage":"validation-image","dependency":"validation-image-python-git","exit_code":1,"image_build_exit_code":"NOT_OBSERVED","reporter":"unavailable","scripts_ran":0,"gut_execution":"NOT_OBSERVED"}
FALLBACK
  fi
}
validation_context_qualified() (
  [[ ! -L "$root/deploy" && ! -L "$root/deploy/validation" ]] || exit 1
  shopt -s nullglob dotglob
  entries=("$root/deploy/validation"/*)
  [[ ${#entries[@]} -eq 1 && "${entries[0]}" == "$root/deploy/validation/Dockerfile" \
     && -f "${entries[0]}" && ! -L "${entries[0]}" ]]
)
if ! validation_context_qualified; then
  record_image_failure 2 false
  echo "VALIDATION GATE ERROR: validation build context is not the single owned recipe." >&2
  exit 2
fi
if docker build --build-arg "GODOT_IMAGE=$base_image" --tag "$image" \
    "$root/deploy/validation" >/dev/null 2>&1; then
  :
else
  build_status=$?
  record_image_failure "$build_status"
  echo "VALIDATION GATE ERROR: validation image dependencies could not be built." >&2
  exit "$build_status"
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
