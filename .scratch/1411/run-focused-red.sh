#!/usr/bin/env bash
set -euo pipefail

expected_mode="${1:-red}"
if [[ "$expected_mode" != "red" && "$expected_mode" != "green" ]]; then
  printf 'usage: %s [red|green]\n' "$0" >&2
  exit 2
fi

exec 9>/tmp/project0-m4-01a0fcfa-validation.lock
flock -n 9

run_id="$(date -u +%Y%m%dT%H%M%S%N)"
evidence_root="${PROJECT0_VALIDATION_RESULTS_ROOT:-build/validation}"
mkdir -p "$evidence_root"
report_dir="$evidence_root/m4-1411-red-$run_id"
mkdir -p "$report_dir"
state_root="$(mktemp -d /tmp/project0-1411-red.XXXXXX)"
prepared_root="$state_root/prepared"
preparation_report="$report_dir/preparation-summary.json"
cleanup() {
  result=$?
  trap - EXIT
  if [[ -f "$preparation_report" ]]; then
    custody="$(python3 - "$preparation_report" <<'PY'
import json, sys
try:
    report = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    print("unknown")
else:
    safe = (report.get("configuration_custody_lost") is False
            and report.get("configuration_restored") is True
            and report.get("source_custody_qualified") is True)
    print("restored" if safe else "retain")
PY
)"
    if [[ "$custody" != "restored" ]]; then
      printf 'VALIDATION BLOCKED: preparation custody unqualified; retained %s\n' "$state_root" >&2
      exit 1
    fi
  elif [[ -e "$prepared_root" ]]; then
    printf 'VALIDATION BLOCKED: preparation report missing; retained %s\n' "$state_root" >&2
    exit 1
  fi
  rm -rf -- "$state_root" || result=1
  exit "$result"
}
trap cleanup EXIT

export XDG_DATA_HOME="$state_root/data"
export XDG_CONFIG_HOME="$state_root/config"
export XDG_CACHE_HOME="$state_root/cache"
export PROJECT0_TEST_STATE_DIR="$state_root/runtime"
export DASHBOARD_RESULTS_DIR="$state_root/dashboard"
export LANG="${LANG:-C.UTF-8}"

revision="$(git rev-parse --verify HEAD)"
login_pid="$(docker inspect --format '{{.State.Pid}}' project0-login-server)"
game_pid="$(docker inspect --format '{{.State.Pid}}' project0-game-server)"
[[ "$login_pid" =~ ^[1-9][0-9]*$ && "$game_pid" =~ ^[1-9][0-9]*$ ]]
login_cgroup="$(cat "/proc/$login_pid/cgroup")"
game_cgroup="$(cat "/proc/$game_pid/cgroup")"

sudo_args=(--preserve-env=PATH,LANG,XDG_DATA_HOME,XDG_CONFIG_HOME,XDG_CACHE_HOME,PROJECT0_TEST_STATE_DIR,DASHBOARD_RESULTS_DIR)
monitor_args=(
  --root "$PWD"
  --expected-revision "$revision"
  --timeout-seconds 300
  --require-root
  --reject-unowned-godot
  --run-as-sudo-caller
  --allowed-cgroup "$login_cgroup"
  --allowed-cgroup "$game_cgroup"
  --preserve-env XDG_DATA_HOME
  --preserve-env XDG_CONFIG_HOME
  --preserve-env XDG_CACHE_HOME
  --preserve-env PROJECT0_TEST_STATE_DIR
  --preserve-env DASHBOARD_RESULTS_DIR
)
godot_bin="$(command -v godot)"
[[ -n "$godot_bin" ]]

sudo -n "${sudo_args[@]}" /data/code/project0/.venv-enrollment/bin/python \
  scripts/run_validation_monitor.py "${monitor_args[@]}" \
  --report "$report_dir/import-review-validation.json" \
  -- /data/code/project0/.venv-enrollment/bin/python scripts/prepare_godot_project.py \
  --source-root "$PWD" --prepared-root "$prepared_root" --godot "$godot_bin" \
  --source-revision "$revision" --timeout-seconds 300 --report "$preparation_report"
python3 - "$preparation_report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
assert report.get("status") == "passed"
assert report.get("configuration_restored") is True
assert report.get("source_custody_qualified") is True
assert report.get("configuration_custody_lost") is False
PY

set +e
sudo -n "${sudo_args[@]}" /data/code/project0/.venv-enrollment/bin/python \
  scripts/run_validation_monitor.py "${monitor_args[@]}" \
  --report "$report_dir/focused-review-validation.json" \
  -- "$godot_bin" --headless --path "$prepared_root" -s addons/gut/gut_cmdln.gd \
  -gconfig= -gtest=res://tests/integration/test_canon_repository.gd,res://tests/integration/test_server_checkpoint_recovery.gd \
  "-gjunit_xml_file=$report_dir/gut.xml" -gdisable_colors -gexit
red_status=$?
set -e

python3 - "$report_dir/gut.xml" "$report_dir/focused-review-validation.json" "$red_status" "$report_dir" "$expected_mode" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
report = json.loads(open(sys.argv[2], encoding="utf-8").read())
cases = list(root.iter("testcase"))
mode = sys.argv[5]
expected = {
  "test_checkpoint_metadata_matches_existing_canon_read",
  "test_checkpoint_metadata_refreshes_schema_only_change_after_reopen",
  "test_checkpoint_metadata_refreshes_equivalent_reordered_json",
  "test_checkpoint_metadata_refreshes_after_geometry_change",
  "test_checkpoint_metadata_does_not_outlive_missing_canon",
  "test_checkpoint_metadata_uses_canon_created_after_initial_miss",
  "test_checkpoint_metadata_preserves_empty_not_open_and_query_failed_results",
  "test_checkpoint_metadata_handles_valid_oversized_blueprint",
}
by_name = {case.get("name"): case for case in cases}
assert int(sys.argv[3]) == (1 if mode == "red" else 0), f"unexpected GUT exit for {mode} run"
assert len(cases) == 15 and set(by_name) == expected | {
  "test_first_write_and_restart_recovery",
  "test_same_blueprint_is_idempotent",
  "test_conflicting_blueprint_cannot_replace_canon",
  "test_invalid_blueprint_is_rejected_before_storage",
  "test_hostile_sector_id_is_stored_as_data",
  "test_checkpoint_metadata_flows_through_shared_and_dedicated_canon_to_recovery",
  "test_checkpoint_persists_empty_metadata_fallback_when_canon_is_closed",
}, "only the selected Canon repository tests must run"
for name, case in by_name.items():
  if name in expected and mode == "red":
    assert case.find("failure") is not None, f"expected public-seam RED: {name}"
    assert case.find("error") is None, f"parse/runtime error is not RED: {name}"
  else:
    assert case.find("failure") is None and case.find("error") is None, f"test did not pass: {name}"
assert report["forced_recovery"] is False and report["cleanup"]["owned_processes_stopped"]
assert report["source_unchanged"] and not report["errors"]
print(json.dumps({"expected_" + mode: True, "tests": sorted(expected),
                  "monitor_cleanup": report["cleanup"]["owned_processes_stopped"],
                  "evidence_dir": sys.argv[4]}))
PY