#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
run="${1:?new run id}"; mode="${2:?red or green}"
[[ "$run" =~ ^[a-zA-Z0-9_-]+$ && "$mode" =~ ^(red|green)$ ]] || exit 2
result="$PWD/build/validation/950-rules/$run"
test ! -e "$result"
mkdir -p "$result/user-data"
export XDG_DATA_HOME="$result/user-data" DASHBOARD_RESULTS_DIR="$result/dashboard"
cleanup() {
  rm -rf -- "$result/user-data"
  python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);f=p/'result.json'
v=json.loads(f.read_text()) if f.exists() else {'status':'failed','reason':'result_not_observed'}
v['owned_xdg_removed']=not(p/'user-data').exists()
if not v['owned_xdg_removed']:v['status']='failed'
f.write_text(json.dumps(v,indent=2)+'\n');print(json.dumps(v))
PY
}
trap cleanup EXIT
python3 scripts/check_validation_ownership.py --plan .scratch/950-rules/validation-plan.json --output "$result/preflight.json" > "$result/preflight.log"
git rev-parse HEAD > "$result/revision.txt"
set +e
timeout --kill-after=10s 120s godot --headless --editor --path . --import --quit > "$result/import.log" 2>&1
import_code=$?
timeout --kill-after=10s 120s godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_item_creation_profile.gd -gdisable_colors -gexit -gjunit_xml_file="$result/gut.xml" > "$result/gut.log" 2>&1
suite_code=$?
set -e
python3 - "$result" "$mode" "$import_code" "$suite_code" <<'PY'
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as E
from pathlib import Path
p=Path(sys.argv[1]);mode=sys.argv[2];problems=[]
try:ss=list(E.parse(p/'gut.xml').iter('testsuite'))
except (OSError,E.ParseError):ss=[];problems.append('missing_junit')
n=sum(int(s.get('tests',0)) for s in ss);f=sum(int(s.get('failures',0)) for s in ss);e=sum(int(s.get('errors',0)) for s in ss);k=sum(int(s.get('skipped',0)) for s in ss)
if len(ss)!=1 or ss[0].get('name')!='tests/unit/test_item_creation_profile.gd' or n<1 or e or k:problems.append('invalid_coverage')
for name in ['import.log','gut.log']:
 if re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script',(p/name).read_text()):problems.append('script_error:'+name)
if int(sys.argv[3])!=0:problems.append('import_failed')
if mode=='red' and (n!=1 or f!=1 or int(sys.argv[4])!=1):problems.append('expected_red_missing')
if mode=='green' and (f or int(sys.argv[4])!=0):problems.append('green_failed')
v={'status':'failed' if problems else 'expected_red' if mode=='red' else 'passed','host':'192.168.1.254','revision':(p/'revision.txt').read_text().strip(),'engine':subprocess.check_output(['godot','--version'],text=True).strip(),'command':'bash .scratch/950-rules/run-focused.sh '+p.name+' '+mode,'tests':n,'failures':f,'errors':e,'skipped':k,'import_exit':int(sys.argv[3]),'suite_exit':int(sys.argv[4]),'validation_errors':problems,'source_sha256':{str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in [Path('tests/unit/test_item_creation_profile.gd'),Path('tests/fixtures/item_creation_profile.gd'),Path('.scratch/950-rules/run-focused.sh')]} }
(p/'result.json').write_text(json.dumps(v,indent=2)+'\n')
if problems:sys.exit(1)
PY
