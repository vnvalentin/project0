#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
run="${1:?new run id}"; mode="${2:?red or green}"; expected="${3:-1}"; binding="${4:-prepared}"
[[ "$run" =~ ^[a-zA-Z0-9_-]+$ && "$mode" =~ ^(red|green)$ && "$expected" =~ ^[1-9][0-9]*$ && "$binding" =~ ^(prepared|delivery)$ ]] || exit 2
[[ "$binding" != delivery || "$mode" == green ]] || exit 2
result="$PWD/build/validation/950-rules/$run"
test ! -e "$result"
mkdir -p "$result"
stage=runtime_setup; import_code=NOT_OBSERVED; suite_code=NOT_OBSERVED; engine=NOT_OBSERVED
cleanup() {
  local runner_exit=$? cleanup_exit=0 evidence_exit=0
  trap - EXIT
  set +e
  rm -rf -- "$result/user-data" || cleanup_exit=$?
  python3 .scratch/950-rules/validation-evidence.py finish "$result" "$mode" "$binding" "$expected" "$stage" "$runner_exit" "$cleanup_exit" "$import_code" "$suite_code" "$engine"
  evidence_exit=$?
  exit "$evidence_exit"
}
trap cleanup EXIT
mkdir -p "$result/user-data"
export XDG_DATA_HOME="$result/user-data" DASHBOARD_RESULTS_DIR="$result/dashboard"
stage=source_start
python3 .scratch/950-rules/validation-evidence.py start "$result" "$mode" "$binding" "$expected"
stage=preflight
python3 scripts/check_validation_ownership.py --plan .scratch/950-rules/validation-plan.json --output "$result/preflight.json" > "$result/preflight.log" 2>&1
python3 .scratch/950-rules/validation-evidence.py preflight-check "$result" "$mode" "$binding" "$expected"
stage=engine_metadata
engine="$(timeout --kill-after=1s 10s godot --version)"
test -n "$engine"
stage=import
set +e
timeout --kill-after=10s 120s godot --headless --editor --path . --import --quit > "$result/import.log" 2>&1
import_code=$?
set -e
[[ "$import_code" -eq 0 ]] || exit 1
stage=import_qualification
python3 .scratch/950-rules/validation-evidence.py import-check "$result" "$mode" "$binding" "$expected"
stage=gut
set +e
timeout --kill-after=10s 120s godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_item_creation_profile.gd -gdisable_colors -gexit -gjunit_xml_file="$result/gut.xml" > "$result/gut.log" 2>&1
suite_code=$?
set -e
stage=finalize
exit 0
