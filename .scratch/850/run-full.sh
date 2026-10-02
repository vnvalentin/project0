#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
run="${1:?new run id required}"
case "$run" in *[!a-zA-Z0-9_-]*|'') exit 2;; esac
result="$PWD/build/validation/850/$run"
test ! -e "$result" && test ! -L "$result"
mkdir -p "$result"
owned_state="$result/user-data"
result_file="$result/result.json"
stage=setup
cleanup() {
  local runner_exit=$? cleanup_exit=0 evidence_exit=0
  trap - EXIT
  set +e
  rm -rf -- "$owned_state" || cleanup_exit=$?
  python3 .scratch/850/validation-evidence.py finalize "$result_file" full "$owned_state" "$runner_exit" "$cleanup_exit" "$stage"
  evidence_exit=$?
  exit "$evidence_exit"
}
trap cleanup EXIT
mkdir -p "$owned_state" "$result/observations"
export XDG_DATA_HOME="$owned_state"
export DASHBOARD_RESULTS_DIR="$result/dashboard"
export PROJECT0_PERMISSION_EVIDENCE_DIR="$result/observations"
stage=source_start
python3 .scratch/850/validation-evidence.py start "$result_file" full
stage=preflight
python3 scripts/check_validation_ownership.py --plan .scratch/850/full-validation-plan.json --output "$result/preflight.json" > "$result/preflight.log"
stage=import
set +e
timeout --kill-after=15s 900s godot --headless --editor --path . --import --quit > "$result/import.log" 2>&1
import_exit=$?
set -e
[[ "$import_exit" == 0 ]] || exit 1
python3 - "$result/import.log" <<'PYSCAN'
import re,sys
from pathlib import Path
log=Path(sys.argv[1]).read_text(errors='replace')
raise SystemExit(1 if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',log) else 0)
PYSCAN
stage=full
set +e
RESULT_DIR="$result" GUT_TIMEOUT_SECONDS=900 bash scripts/run_gut_validation.sh > "$result/full-runner.log" 2>&1
suite_exit=$?
bash scripts/check_record_sync.sh > "$result/record-sync.log" 2>&1
record_exit=$?
set -e
stage=collection
python3 .scratch/850/validation-evidence.py collect "$result_file" full "$run" 1 green "$import_exit,$suite_exit,$record_exit" "$owned_state"
