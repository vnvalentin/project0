#!/usr/bin/env bash
set -euo pipefail

exec 9>/tmp/project0-m4-01a0fcfa-validation.lock
flock -n 9

run_id="$(date -u +%Y%m%dT%H%M%S%N)"
evidence_root="${PROJECT0_VALIDATION_RESULTS_ROOT:-build/validation}"
mkdir -p "$evidence_root"
report_dir="$evidence_root/m4-1411-red-$run_id"
mkdir -p "$report_dir"
state_root="$(mktemp -d /tmp/project0-1411-red.XXXXXX)"
cleanup() {
  result=$?
  trap - EXIT
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
monitor="/data/code/project0/.venv-enrollment/bin/python scripts/run_validation_monitor.py"

sudo -n "${sudo_args[@]}" /data/code/project0/.venv-enrollment/bin/python \
  scripts/run_validation_monitor.py "${monitor_args[@]}" \
  --report "$report_dir/import-review-validation.json" \
  -- godot --headless --import

set +e
sudo -n "${sudo_args[@]}" /data/code/project0/.venv-enrollment/bin/python \
  scripts/run_validation_monitor.py "${monitor_args[@]}" \
  --report "$report_dir/focused-review-validation.json" \
  -- godot --headless -s addons/gut/gut_cmdln.gd \
  -gselect=test_checkpoint_metadata_matches_existing_canon_read \
  "-gjunit_xml_file=$report_dir/gut.xml" -gdisable_colors -gexit
red_status=$?
set -e

python3 - "$report_dir/gut.xml" "$report_dir/focused-review-validation.json" "$red_status" "$report_dir" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
report = json.loads(open(sys.argv[2], encoding="utf-8").read())
cases = [case for case in root.iter("testcase")
         if case.get("name") == "test_checkpoint_metadata_matches_existing_canon_read"]
assert int(sys.argv[3]) == 1, "expected the unchanged implementation to fail the new assertion"
assert len(cases) == 1 and cases[0].find("failure") is not None, "the named public-seam test must fail"
assert cases[0].find("error") is None, "parse/runtime errors are not the expected RED"
assert report["forced_recovery"] is False and report["cleanup"]["owned_processes_stopped"]
assert report["source_unchanged"] and not report["errors"]
print(json.dumps({"expected_red": True, "test": cases[0].get("name"),
                  "monitor_cleanup": report["cleanup"]["owned_processes_stopped"],
                  "evidence_dir": sys.argv[4]}))
PY