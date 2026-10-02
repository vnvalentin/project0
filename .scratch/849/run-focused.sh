#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
label="${1:?run label required}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 2
mode="${2:-focused}"
[[ "$mode" == focused || "$mode" == full ]] || exit 2
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${label}-$$"
result_dir="build/validation/849/${run_id}"
test ! -e "$result_dir"
mkdir -p "$result_dir"
fixture_dir="$(mktemp -d "/tmp/project0-849-${label}.XXXXXX")"
export XDG_DATA_HOME="$fixture_dir/xdg"
export DASHBOARD_RESULTS_DIR="$PWD/$result_dir/dashboard"
export PROJECT0_ANCHOR_EVIDENCE_DIR="$PWD/$result_dir/statement-observations"
mkdir -p "$XDG_DATA_HOME" "$DASHBOARD_RESULTS_DIR" "$PROJECT0_ANCHOR_EVIDENCE_DIR"
engine_version="$(/usr/local/bin/godot --version)"
revision="$(git rev-parse HEAD)"
exit_code=1
stage=import
finish() {
  trap - EXIT
  set +e
  case "$fixture_dir" in /tmp/project0-849-*) rm -rf -- "$fixture_dir" ;; *) exit 2 ;; esac
  cleanup=false
  test ! -e "$fixture_dir" && cleanup=true
  python3 - "$result_dir" "$run_id" "$revision" "$engine_version" "$exit_code" "$stage" "$cleanup" "$mode" <<'PY'
import hashlib,json,sys,xml.etree.ElementTree as ET
from pathlib import Path
result_dir,run_id,revision,engine,code,stage,cleanup,mode=sys.argv[1:]
selected='tests/integration/test_interior_anchor_repository.gd'
expected={'tests/unit/test_interior_anchor_contract.gd',selected} if mode=='focused' else {str(p) for root in ['tests/unit','tests/integration'] for p in Path(root).rglob('test_*.gd')}
errors=[]
xml=Path(result_dir)/('focused.xml' if mode=='focused' else 'gut.xml')
suites=[]
if xml.is_file():
    try: suites=[s.attrib for s in ET.parse(xml).iter('testsuite')]
    except ET.ParseError: errors.append('malformed_junit')
else: errors.append('missing_junit')
if {suite.get('name') for suite in suites} != expected or len(suites)!=len(expected):
    errors.append('selected_script_coverage_incomplete')
for suite in suites:
    try:
        if int(suite.get('tests','0'))<=0 or any(int(suite.get(key,'0')) for key in ['failures','errors','skipped']):
            errors.append('selected_suite_not_passing')
    except ValueError: errors.append('invalid_junit_counts')
if cleanup!='true': errors.append('cleanup_not_verified')
if int(code)!=0: errors.append('engine_exit_nonzero')
for log_name in ['import.log', 'focused.log' if mode=='focused' else 'gut.log']:
    log_path=Path(result_dir)/log_name
    if log_path.is_file() and any(marker in log_path.read_text(errors='replace') for marker in ['SCRIPT ERROR','Parse Error','Compile Error']):
        errors.append('script_error:'+log_name)
observations={}
for scenario in ["registration","resolution","reopen","replay-conflict","cell-rollback","rollback-reopen","missing-exterior","destroyed-exterior","separate-store","canon-read-failure","malformed-forged","corrupt-record","corrupt-reopen"]:
    path=Path(result_dir)/"statement-observations"/(scenario+".json")
    try:
        entry=json.loads(path.read_text())
        observation=entry["observation"]
        if entry["scenario"]!=scenario or observation["observation_status"]!="OBSERVED" or observation["native_row_effects"]!="NOT_OBSERVED": errors.append("invalid_observation:"+scenario)
        observations[scenario]=str(path)
    except (OSError,ValueError,KeyError,TypeError): errors.append("missing_or_invalid_observation:"+scenario)
passed=not errors
sources={}
for source in ['shared/interior_anchor_contract.gd','server/interior_anchor_repository.gd',selected,'tests/unit/test_interior_anchor_contract.gd','.scratch/849/run-focused.sh']:
    path=Path(source)
    if path.is_file(): sources[source]=hashlib.sha256(path.read_bytes()).hexdigest()
record={'schema_version':1,'issue':849,'run_id':run_id,'host':'192.168.1.254','revision':revision,'engine':engine,'exit_code':int(code),'stage':stage,'cleanup_verified':cleanup=='true','status':'passed' if passed else 'failed','evidence_exit_code':0 if passed else 1,'evidence_errors':errors,'command':('timeout --kill-after=15s 180s /usr/local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_interior_anchor -gjunit_xml_file='+str(xml)+' -gdisable_colors -gexit') if mode=='focused' else 'scripts/run_gut_validation.sh','mode':mode,'isolated_xdg':True,'isolated_dashboard_results':True,'suites':suites,'statement_observations':observations,'source_sha256':sources,'runtime_acceptance':'supporting Linux SQLite anchor component only'}
(Path(result_dir)/('focused-result.json' if mode=='focused' else 'full-result.json')).write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
raise SystemExit(0 if passed else 1)
PY
  evidence_exit=$?
  [[ "$exit_code" -eq 0 ]] || exit "$exit_code"
  exit "$evidence_exit"
}
trap finish EXIT
set +e
timeout --kill-after=15s 60s /usr/local/bin/godot --headless --import > "$result_dir/import.log" 2>&1
exit_code=$?
set -e
[[ "$exit_code" -eq 0 ]] || exit "$exit_code"
stage="${mode}-gut"
set +e
if [[ "$mode" == focused ]]; then
  timeout --kill-after=15s 180s /usr/local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_interior_anchor -gjunit_xml_file="$result_dir/focused.xml" -gdisable_colors -gexit > "$result_dir/focused.log" 2>&1
else
  GODOT_BIN=/usr/local/bin/godot RESULT_DIR="$result_dir" GUT_TIMEOUT_SECONDS=900 scripts/run_gut_validation.sh > "$result_dir/full-runner.log" 2>&1
fi
exit_code=$?
set -e
exit "$exit_code"
