#!/usr/bin/env bash
set -euo pipefail
label="${1:?stage required}"
expected="${2:?test count required}"
mode="${3:-green}"
[[ "$label" =~ ^[a-z0-9-]+$ && "$expected" =~ ^[1-9][0-9]*$ && "$mode" =~ ^(red|green)$ ]] || exit 2
cd "$(dirname "$0")/../.."
root="$PWD/build/validation/850"
mkdir -p "$root"
result_file="$root/$label-result.json"
test ! -e "$result_file" && test ! -L "$result_file"
owned_state=""
stage=setup
cleanup() {
  local runner_exit=$? cleanup_exit=0 evidence_exit=0
  trap - EXIT
  set +e
  [[ -z "$owned_state" ]] || rm -rf -- "$owned_state" || cleanup_exit=$?
  python3 .scratch/850/validation-evidence.py finalize "$result_file" focused "${owned_state:-$root/not-created-$label}" "$runner_exit" "$cleanup_exit" "$stage"
  evidence_exit=$?
  exit "$evidence_exit"
}
trap cleanup EXIT
owned_state="$(mktemp -d "$root/state-$label.XXXXXX")"
export XDG_DATA_HOME="$owned_state/data"
export DASHBOARD_RESULTS_DIR="$owned_state/dashboard"
export PROJECT0_PERMISSION_EVIDENCE_DIR="$root/$label-observations"
for suffix in .xml .log -observations -result.json.source-start.json; do test ! -e "$root/$label$suffix" && test ! -L "$root/$label$suffix"; done
mkdir -p "$PROJECT0_PERMISSION_EVIDENCE_DIR"
stage=source_start
python3 .scratch/850/validation-evidence.py start "$result_file" focused
stage=preflight
python3 scripts/check_validation_ownership.py --plan .scratch/850/validation-plan.json --output "$root/$label-preflight.json" > "$root/$label-preflight.log"
stage=focused
set +e
timeout --kill-after=5s 90s godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/integration/test_claim_permit_authority.gd -gdisable_colors -gexit -gjunit_xml_file="$root/$label.xml" > "$root/$label.log" 2>&1
result=$?
set -e
stage=collection
python3 .scratch/850/validation-evidence.py collect "$result_file" focused "$label" "$expected" "$mode" "$result" "$owned_state"
