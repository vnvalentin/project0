#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
label="${1:?unique run label required}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 2
mode="${2:-focused}"
[[ "$mode" == focused || "$mode" == full ]] || exit 2
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${label}-$$"
result_dir="$PWD/build/validation/951/$run_id"
test ! -e "$result_dir"
mkdir -p "$result_dir"
fixture_dir=""
code=1
stage=source_start
engine=NOT_OBSERVED
finish() {
  trap - EXIT
  set +e
  cleanup=false
  case "$fixture_dir" in
    "") cleanup=true ;;
    /tmp/project0-951.*)
      rm -rf -- "$fixture_dir"
      [[ "$?" -eq 0 && ! -e "$fixture_dir" ]] && cleanup=true
      ;;
  esac
  python3 .scratch/951/validation-evidence.py finish "$result_dir" "$mode" "$label" "$code" "$stage" "$cleanup" "$engine"
  evidence_exit=$?
  exit "$evidence_exit"
}
trap finish EXIT
python3 .scratch/951/validation-evidence.py start "$result_dir" "$mode"
stage=setup
fixture_dir="$(mktemp -d /tmp/project0-951.XXXXXX)"
export XDG_DATA_HOME="$fixture_dir/xdg"
export DASHBOARD_RESULTS_DIR="$result_dir/dashboard"
mkdir -p "$XDG_DATA_HOME" "$DASHBOARD_RESULTS_DIR"
plan=.scratch/951/validation-plan.json
[[ "$mode" == full ]] && plan=.scratch/951/full-validation-plan.json
stage=preflight
python3 scripts/check_validation_ownership.py --plan "$plan" --output "$result_dir/preflight.json" > "$result_dir/preflight.log" 2>&1
stage=preparation
engine="$(timeout --kill-after=1s 10s godot --version)"
set +e
timeout --kill-after=15s 120s godot --headless --import > "$result_dir/import.log" 2>&1
code=$?
set -e
[[ "$code" -eq 0 ]] || exit "$code"
if python3 - "$result_dir/import.log" <<'PY'
from pathlib import Path
import re,sys
raise SystemExit(1 if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',Path(sys.argv[1]).read_text(errors='replace'),re.I) else 0)
PY
then
  :
else
  code=1
  exit 1
fi
stage="$mode-gut"
set +e
if [[ "$mode" == focused ]]; then
  timeout --kill-after=15s 180s godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/integration/test_workshop_station_authority.gd -gjunit_xml_file="$result_dir/gut.xml" -gdisable_colors -gexit > "$result_dir/gut.log" 2>&1
else
  RESULT_DIR="$result_dir" GUT_TIMEOUT_SECONDS=900 scripts/run_gut_validation.sh > "$result_dir/full-runner.log" 2>&1
fi
code=$?
set -e
exit "$code"
