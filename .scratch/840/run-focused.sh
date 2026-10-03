#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
label="${1:?unique label required}"
expected_head="${2:?expected head required}"
mode="${3:-green}"
[[ "$label" =~ ^[a-z0-9-]+$ && "$expected_head" =~ ^[a-f0-9]{40}$ && "$mode" =~ ^(red|green)$ ]] || exit 2
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${label}-$$"
out="$PWD/build/validation/840/$run_id"
test ! -e "$out"
mkdir -p "$out"
state=""
revision=NOT_OBSERVED
engine=NOT_OBSERVED
stage=setup
native_exit=-1
execution_complete=false
source_clean_start=false
scan_phase_log() {
  python3 - "$1" <<'PYSCAN'
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(errors='replace')
raise SystemExit(1 if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',text) else 0)
PYSCAN
}
finish() {
  trap - EXIT
  set +e
  case "$state" in "") ;; /tmp/project0-840-focused-*) rm -rf -- "$state" ;; *) state_guard_failed=true ;; esac
  cleanup=false
  [[ -z "$state" || ! -e "$state" ]] && [[ "${state_guard_failed:-false}" == false ]] && cleanup=true
  python3 - "$out" "$label" "$revision" "$expected_head" "$engine" "$stage" "$native_exit" "$execution_complete" "$source_clean_start" "$cleanup" "$mode" <<'PY'
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as E
from pathlib import Path
out,label,revision,expected,engine,stage,native_exit,complete,clean_start,cleanup,mode=sys.argv[1:]
out=Path(out);errors=[]
source_paths=['tests/unit/test_construction_contract.gd','shared/construction_contract.gd','.scratch/840/run-focused.sh','.scratch/840/validation-plan.json','.scratch/840/run-evidence-controls.py']
sources={}
for path in source_paths:
    try:
        sources[path]=hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        sources[path]='NOT_OBSERVED';errors.append('source_identity_not_observed:'+path)
if clean_start!='true': errors.append('source_not_clean_at_start')
if revision=='NOT_OBSERVED': errors.append('initial_revision_not_observed')
if revision!=expected: errors.append('unexpected_head')
def git_identity(arguments,error):
    try:
        return subprocess.check_output(['git',*arguments],text=True,stderr=subprocess.DEVNULL,timeout=10).strip()
    except (OSError,subprocess.SubprocessError,UnicodeError):
        errors.append(error);return 'NOT_OBSERVED'
final_status=git_identity(['status','--porcelain'],'source_status_not_observed')
clean_end='NOT_OBSERVED' if final_status=='NOT_OBSERVED' else not final_status
final_revision=git_identity(['rev-parse','HEAD'],'final_revision_not_observed')
if final_revision!='NOT_OBSERVED' and final_revision!=revision: errors.append('head_changed_during_run')
if clean_end is False: errors.append('source_not_clean_at_end')
try:
    initial_sources=json.loads((out/'source-start.json').read_text())
    if not isinstance(initial_sources,dict) or set(initial_sources)!=set(source_paths) or any(not isinstance(v,str) for v in initial_sources.values()):
        errors.append('invalid_source_start_container')
    elif initial_sources!=sources: errors.append('source_changed_during_run')
except (OSError,ValueError): errors.append('source_start_missing')
if cleanup!='true': errors.append('cleanup_unverified')
if complete!='true': errors.append('execution_incomplete')
if engine=='NOT_OBSERVED' or not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?\.[A-Za-z0-9_.+-]+',engine): errors.append('engine_identity_not_observed')
test_path='tests/unit/test_construction_contract.gd'
declared_cases=('test_place_request_preserves_pins_and_detaches_client_values','test_cancel_action_is_excluded_from_the_closed_verb_set','test_all_locked_verbs_are_accepted','test_nested_object_values_are_rejected','test_cross_field_container_alias_is_rejected','test_request_depth_is_bounded','test_request_node_count_is_bounded','test_request_container_count_is_bounded','test_orientation_must_be_finite_and_canonical_degrees')
red_cases=('test_orientation_must_be_finite_and_canonical_degrees',)
expected_tests=len(declared_cases)
try:
    source_cases=re.findall(r'^func (test_[A-Za-z0-9_]+)\(',Path(test_path).read_text(),re.M)
    if sorted(source_cases)!=sorted(declared_cases): errors.append('declared_test_inventory_mismatch')
except (OSError,UnicodeError): errors.append('test_inventory_not_observed')
counts={'tests':0,'failures':0,'errors':0,'skips':0}
failed_cases=[]
try:
    xml=E.parse(out/'gut.xml').getroot()
    cases=xml.findall('.//testcase')
    suites=xml.findall('.//testsuite')
    counts={'tests':len(cases),'failures':len(xml.findall('.//failure')),'errors':len(xml.findall('.//error')),'skips':len(xml.findall('.//skipped'))}
    if len(suites)!=1 or suites[0].get('name')!=test_path: errors.append('test_suite_identity_mismatch')
    if sorted(c.get('name','') for c in cases)!=sorted(declared_cases): errors.append('test_case_identity_mismatch')
    if any(c.get('classname')!=test_path for c in cases): errors.append('test_class_identity_mismatch')
    failed_cases=[c.get('name','') for c in cases if c.findall('.//failure') or c.findall('.//error')]
    for case in cases:
        wanted_status='fail' if case.get('name','') in failed_cases else 'pass'
        if case.get('status')!=wanted_status: errors.append('test_case_status_mismatch')
        if not re.fullmatch(r'[1-9][0-9]*',case.get('assertions','')): errors.append('test_assertions_not_observed')
    if len(xml.findall('.//failure'))!=sum(len(c.findall('.//failure')) for c in cases): errors.append('unattributed_failure')
except (OSError,E.ParseError): errors.append('missing_or_invalid_gut_xml')
if expected_tests<=0 or counts['tests']!=expected_tests: errors.append('test_inventory_mismatch')
if counts['errors'] or counts['skips']: errors.append('gut_errors_or_skips')
for name in ['import.log','gut.log']:
    p=out/name
    try:
        if not p.is_file(): errors.append('missing_log:'+name)
        elif re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',p.read_text(errors='replace')): errors.append('script_error:'+name)
    except OSError: errors.append('log_not_observed:'+name)
if mode=='green':
    if int(native_exit)!=0 or counts['failures']!=0: errors.append('green_not_observed')
else:
  if int(native_exit)!=1 or failed_cases!=list(red_cases) or counts['failures']!=len(red_cases): errors.append('red_not_observed')
report={'schema_version':1,'issue':840,'host':'192.168.1.254','revision':revision,'final_revision':final_revision,'expected_head':expected,'engine':engine,'command':'bash .scratch/840/run-focused.sh '+label+' '+expected+' '+mode,'mode':mode,'stage':stage,'native_exit_code':int(native_exit),'status':'passed' if not errors else 'failed','expected_tests':expected_tests,**counts,'source_clean_start':clean_start=='true','source_clean_end':clean_end,'source_sha256':sources,'cleanup_verified':cleanup=='true','errors':errors,'action_validation':'NOT_OBSERVED','persistence':'NOT_OBSERVED','windows_runtime':'NOT_OBSERVED','result_retention':'OBSERVED'}
try:
    (out/'focused-result.json').write_text(json.dumps(report,indent=2)+'\n')
except OSError:
    report['status']='failed';report['result_retention']='NOT_OBSERVED';report['errors'].append('result_retention_not_observed')
    print(json.dumps(report));raise SystemExit(1)
print(json.dumps({k:report[k] for k in ['status','mode','stage','tests','failures','native_exit_code','cleanup_verified','errors']}))
raise SystemExit(0 if not errors else 1)
PY
  exit "$?"
}
trap finish EXIT
stage=initial_identity
if initial_revision="$(timeout --kill-after=1s 10s git rev-parse HEAD 2>/dev/null)"; then
  [[ "$initial_revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
  revision="$initial_revision"
else
  exit 1
fi
stage=source_guard
[[ "$revision" == "$expected_head" ]]
if initial_status="$(timeout --kill-after=1s 10s git status --porcelain 2>/dev/null)"; then
  [[ -z "$initial_status" ]] || exit 1
else
  exit 1
fi
source_clean_start=true
state="$(mktemp -d /tmp/project0-840-focused-XXXXXX)"
export XDG_DATA_HOME="$state/data"
export DASHBOARD_RESULTS_DIR="$out/dashboard"
mkdir -p "$XDG_DATA_HOME" "$DASHBOARD_RESULTS_DIR"
python3 - "$out/source-start.json" <<'PY'
import hashlib,json,sys
from pathlib import Path
paths=['tests/unit/test_construction_contract.gd','shared/construction_contract.gd','.scratch/840/run-focused.sh','.scratch/840/validation-plan.json','.scratch/840/run-evidence-controls.py']
Path(sys.argv[1]).write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() if Path(p).is_file() else 'NOT_PRESENT' for p in paths},indent=2)+'\n')
PY
stage=ownership
python3 scripts/check_validation_ownership.py --plan .scratch/840/validation-plan.json --output "$out/plan-ownership.json" > "$out/preflight.log" 2>&1
stage=engine_identity
if observed_engine="$(timeout --kill-after=1s 10s /usr/local/bin/godot --version 2>/dev/null)"; then
  [[ "$observed_engine" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?\.[A-Za-z0-9_.+-]+$ ]] || exit 1
  engine="$observed_engine"
else
  exit 1
fi
stage=import
timeout --kill-after=10s 90s /usr/local/bin/godot --headless --path . --import > "$out/import.log" 2>&1
scan_phase_log "$out/import.log"
stage=gut
set +e
timeout --kill-after=10s 90s /usr/local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_construction_contract.gd -gdisable_colors -gexit -gjunit_xml_file="$out/gut.xml" > "$out/gut.log" 2>&1
native_exit=$?
set -e
execution_complete=true
