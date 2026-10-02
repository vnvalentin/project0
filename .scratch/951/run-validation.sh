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
fixture_dir="$(mktemp -d /tmp/project0-951.XXXXXX)"
export XDG_DATA_HOME="$fixture_dir/xdg"
export DASHBOARD_RESULTS_DIR="$result_dir/dashboard"
mkdir -p "$XDG_DATA_HOME" "$DASHBOARD_RESULTS_DIR"
revision="$(git rev-parse HEAD)"
engine="$(godot --version)"
code=1
stage=preparation
finish() {
  trap - EXIT
  set +e
  case "$fixture_dir" in /tmp/project0-951.*) rm -rf -- "$fixture_dir" ;; *) exit 2;; esac
  cleanup=false
  test ! -e "$fixture_dir" && cleanup=true
  python3 - "$result_dir" "$revision" "$engine" "$code" "$stage" "$cleanup" "$mode" "$label" <<'PY'
from pathlib import Path
import hashlib,json,re,sys,xml.etree.ElementTree as ET
directory,revision,engine,code,stage,cleanup,mode,label=sys.argv[1:]
p=Path(directory);errors=[]
expected={'tests/integration/test_workshop_station_authority.gd'} if mode=='focused' else {str(t) for root in ['tests/unit','tests/integration'] for t in Path(root).rglob('test_*.gd')}
suites=[]
try:suites=[s.attrib for s in ET.parse(p/'gut.xml').iter('testsuite')]
except (OSError,ET.ParseError):errors.append('missing_or_invalid_junit')
if {s.get('name') for s in suites}!=expected or len(suites)!=len(expected):errors.append('selected_script_coverage_incomplete')
for s in suites:
 try:
  if int(s.get('tests',0))<=0 or any(int(s.get(k,0)) for k in ['failures','errors','skipped']):errors.append('suite_not_passing')
 except ValueError:errors.append('invalid_junit_counts')
markers=[]
for name in ['import.log','gut.log','full-runner.log']:
 log=p/name
 if log.is_file():
  for n,line in enumerate(log.read_text(errors='replace').splitlines(),1):
   if re.search(r'SCRIPT ERROR|Parse Error|Compile Error',line,re.I):markers.append({'file':name,'line':n,'message':line[:400]})
if markers:errors.append('godot_script_failure')
if cleanup!='true':errors.append('cleanup_not_verified')
if int(code)!=0:errors.append('engine_or_preparation_exit_nonzero')
sources={}
for name in ['server/admitted_player_state.gd','server/workshop_station_contract.gd','server/workshop_character_sensor.gd','server/workshop_station_volume.gd','server/workshop_station_authority.gd','tests/integration/test_workshop_station_authority.gd','.scratch/951/run-validation.sh']:
 f=Path(name)
 if f.is_file():sources[name]=hashlib.sha256(f.read_bytes()).hexdigest()
record={'schema_version':1,'issue':951,'host':'192.168.1.254','revision':revision,'engine':engine,'mode':mode,'stage':stage,'command':'bash .scratch/951/run-validation.sh '+label+' '+mode,'exit_code':int(code),'evidence_exit_code':1 if errors else 0,'status':'failed' if errors else 'passed','evidence_errors':errors,'script_failure_markers':markers,'expected_scripts':sorted(expected),'suites':suites,'cleanup_verified':cleanup=='true','isolated_xdg':True,'isolated_dashboard_results':True,'artifact_directory':directory,'source_sha256':sources,'runtime_acceptance':'bounded station authority component only; full workshop NOT_OBSERVED'}
(p/'result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
raise SystemExit(1 if errors else 0)
PY
  result=$?
  [[ "$code" -eq 0 ]] || exit "$code"
  exit "$result"
}
trap finish EXIT
set +e
timeout --kill-after=15s 120s godot --headless --import > "$result_dir/import.log" 2>&1
code=$?
set -e
[[ "$code" -eq 0 ]] || exit "$code"
if python3 - "$result_dir/import.log" <<'PY'
from pathlib import Path
import re,sys
raise SystemExit(0 if re.search(r'SCRIPT ERROR|Parse Error|Compile Error',Path(sys.argv[1]).read_text(errors='replace'),re.I) else 1)
PY
then
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
