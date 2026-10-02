#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
kind="${1:?lifecycle or prediction required}"
run="${2:?new run id required}"
case "$run" in *[!a-zA-Z0-9_-]*|'') exit 2;; esac
case "$kind" in lifecycle) test_script=tests/integration/test_jit_lifecycle_correlation.gd;; prediction) test_script=tests/integration/test_prediction_reconciliation_e2e.gd;; *) exit 2;; esac
result="$PWD/build/validation/1341-ledger/$run"
test ! -e "$result"
mkdir -p "$result/user-data"
export XDG_DATA_HOME="$result/user-data"
export DASHBOARD_RESULTS_DIR="$result/dashboard"
cleanup() {
  rm -rf -- "$XDG_DATA_HOME"
  python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); f=p/'result.json'
r=json.loads(f.read_text()) if f.exists() else {'status':'failed','reason':'result_preparation_not_observed'}
r['owned_xdg_removed']=not (p/'user-data').exists()
if not r['owned_xdg_removed']:r['status']='failed'
f.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
PY
}
trap cleanup EXIT
python3 scripts/check_validation_ownership.py --plan .scratch/1341-ledger/diagnostic-validation-plan.json --output "$result/preflight.json" > "$result/preflight.log"
git rev-parse HEAD > "$result/start-revision.txt"
git status --porcelain > "$result/start-status.txt"
test ! -s "$result/start-status.txt"
set +e
timeout --kill-after=15s 180s godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig= -gtest="res://$test_script" -gjunit_xml_file="$result/gut.xml" -gdisable_colors -gexit > "$result/gut.log" 2>&1
code=$?
set -e
python3 - "$result" "$test_script" "$code" "$kind" <<'PY'
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as ET
from pathlib import Path
p=Path(sys.argv[1]); selected=sys.argv[2];problems=[]
try:suites=list(ET.parse(p/'gut.xml').iter('testsuite'))
except (OSError,ET.ParseError):suites=[];problems.append('invalid_junit')
expected_tests=len(re.findall(r'^func test_',Path(selected).read_text(),re.M))
if len(suites)!=1 or suites[0].attrib.get('name')!=selected:problems.append('incomplete_script_coverage')
tests=sum(int(s.attrib.get('tests',0)) for s in suites)
failures=sum(int(s.attrib.get('failures',0)) for s in suites)
errors=sum(int(s.attrib.get('errors',0)) for s in suites)
skips=sum(int(s.attrib.get('skipped',0)) for s in suites)
if tests!=expected_tests or tests<=0 or failures or errors or skips:problems.append('suite_not_passing')
log=(p/'gut.log').read_text()
script_errors=bool(re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script',log))
if script_errors:problems.append('script_error')
revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
if revision!=(p/'start-revision.txt').read_text().strip() or subprocess.check_output(['git','status','--porcelain'],text=True).strip():problems.append('source_changed')
if int(sys.argv[3])!=0:problems.append('command_failed')
r={'status':'failed' if problems else 'passed','host':'192.168.1.254','engine':subprocess.check_output(['godot','--version'],text=True).strip(),'revision':revision,'command':'bash .scratch/1341-ledger/run-diagnostic.sh '+sys.argv[4]+' '+p.name,'exit_code':int(sys.argv[3]),'selected_script':selected,'expected_tests':expected_tests,'tests':tests,'failures':failures,'errors':errors,'skipped':skips,'script_errors_observed':script_errors,'validation_errors':problems,'source_sha256':{f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in [selected,'.scratch/1341-ledger/run-diagnostic.sh']},'owned_xdg_removed':'NOT_OBSERVED','acceptance':'diagnosis only; does not replace failed full suite'}
(p/'result.json').write_text(json.dumps(r,indent=2)+'\n')
if problems:sys.exit(1)
PY
