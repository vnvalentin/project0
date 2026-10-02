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
revision="$(git rev-parse HEAD)"
engine=NOT_OBSERVED
stage=setup
native_exit=-1
execution_complete=false
source_clean_start=false
finish() {
  trap - EXIT
  set +e
  case "$state" in "") ;; /tmp/project0-840-focused-*) rm -rf -- "$state" ;; *) exit 2 ;; esac
  cleanup=false
  [[ -z "$state" || ! -e "$state" ]] && cleanup=true
  python3 - "$out" "$label" "$revision" "$expected_head" "$engine" "$stage" "$native_exit" "$execution_complete" "$source_clean_start" "$cleanup" "$mode" <<'PY'
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as E
from pathlib import Path
out,label,revision,expected,engine,stage,native_exit,complete,clean_start,cleanup,mode=sys.argv[1:]
out=Path(out);errors=[]
source_paths=['tests/unit/test_construction_contract.gd','shared/construction_contract.gd','.scratch/840/run-focused.sh','.scratch/840/validation-plan.json']
sources={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() if Path(p).is_file() else 'NOT_PRESENT' for p in source_paths}
if clean_start!='true': errors.append('source_not_clean_at_start')
if revision!=expected: errors.append('unexpected_head')
try:
    clean_end=not subprocess.check_output(['git','status','--porcelain'],text=True).strip()
    if subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()!=revision: errors.append('head_changed_during_run')
except subprocess.CalledProcessError:
    clean_end=False;errors.append('git_source_check_failed')
if not clean_end: errors.append('source_not_clean_at_end')
try:
    if json.loads((out/'source-start.json').read_text())!=sources: errors.append('source_changed_during_run')
except (OSError,ValueError): errors.append('source_start_missing')
if cleanup!='true': errors.append('cleanup_unverified')
if complete!='true': errors.append('execution_incomplete')
expected_tests=len(re.findall(r'^func test_',Path('tests/unit/test_construction_contract.gd').read_text(),re.M))
counts={'tests':0,'failures':0,'errors':0,'skips':0}
try:
    xml=E.parse(out/'gut.xml').getroot()
    counts={'tests':len(xml.findall('.//testcase')),'failures':len(xml.findall('.//failure')),'errors':len(xml.findall('.//error')),'skips':len(xml.findall('.//skipped'))}
except (OSError,E.ParseError): errors.append('missing_or_invalid_gut_xml')
if expected_tests<=0 or counts['tests']!=expected_tests: errors.append('test_inventory_mismatch')
if counts['errors'] or counts['skips']: errors.append('gut_errors_or_skips')
for name in ['import.log','gut.log']:
    p=out/name
    if not p.is_file(): errors.append('missing_log:'+name)
    elif re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',p.read_text(errors='replace')): errors.append('script_error:'+name)
if mode=='green':
    if int(native_exit)!=0 or counts['failures']!=0: errors.append('green_not_observed')
else:
    if int(native_exit)==0 or counts['failures']<=0: errors.append('red_not_observed')
report={'schema_version':1,'issue':840,'host':'192.168.1.254','revision':revision,'expected_head':expected,'engine':engine,'command':'bash .scratch/840/run-focused.sh '+label+' '+expected+' '+mode,'mode':mode,'stage':stage,'native_exit_code':int(native_exit),'status':'passed' if not errors else 'failed','expected_tests':expected_tests,**counts,'source_clean_start':clean_start=='true','source_clean_end':clean_end,'source_sha256':sources,'cleanup_verified':cleanup=='true','errors':errors,'action_validation':'NOT_OBSERVED','persistence':'NOT_OBSERVED','windows_runtime':'NOT_OBSERVED'}
(out/'focused-result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','mode','stage','tests','failures','native_exit_code','cleanup_verified','errors']}))
raise SystemExit(0 if not errors else 1)
PY
  exit "$?"
}
trap finish EXIT
stage=source_guard
[[ "$revision" == "$expected_head" ]]
[[ -z "$(git status --porcelain)" ]]
source_clean_start=true
state="$(mktemp -d /tmp/project0-840-focused-XXXXXX)"
export XDG_DATA_HOME="$state/data"
export DASHBOARD_RESULTS_DIR="$out/dashboard"
mkdir -p "$XDG_DATA_HOME" "$DASHBOARD_RESULTS_DIR"
python3 - "$out/source-start.json" <<'PY'
import hashlib,json,sys
from pathlib import Path
paths=['tests/unit/test_construction_contract.gd','shared/construction_contract.gd','.scratch/840/run-focused.sh','.scratch/840/validation-plan.json']
Path(sys.argv[1]).write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() if Path(p).is_file() else 'NOT_PRESENT' for p in paths},indent=2)+'\n')
PY
stage=ownership
python3 scripts/check_validation_ownership.py --plan .scratch/840/validation-plan.json --output "$out/plan-ownership.json" > "$out/preflight.log" 2>&1
stage=import
engine="$(/usr/local/bin/godot --version)"
timeout --kill-after=10s 90s /usr/local/bin/godot --headless --path . --import > "$out/import.log" 2>&1
! rg -q 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$out/import.log"
stage=gut
set +e
timeout --kill-after=10s 90s /usr/local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_construction_contract.gd -gdisable_colors -gexit -gjunit_xml_file="$out/gut.xml" > "$out/gut.log" 2>&1
native_exit=$?
set -e
execution_complete=true
