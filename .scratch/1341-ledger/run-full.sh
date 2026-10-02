#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
run="${1:?new run id required}"
case "$run" in *[!a-zA-Z0-9_-]*|'') exit 2;; esac
result="$PWD/build/validation/1341-ledger/$run"
test ! -e "$result"
mkdir -p "$result/user-data" "$result/observations"
export XDG_DATA_HOME="$result/user-data"
export DASHBOARD_RESULTS_DIR="$result/dashboard"
export PROJECT0_LEDGER_EVIDENCE_DIR="$result/observations"
cleanup() {
  local runner_exit=$? cleanup_exit=0 evidence_exit=0
  trap - EXIT
  set +e
  rm -rf -- "$XDG_DATA_HOME" || cleanup_exit=$?
  python3 .scratch/1341-ledger/evidence_guard.py finalize "$result" "$runner_exit" "$cleanup_exit"
  evidence_exit=$?
  exit "$evidence_exit"
}
trap cleanup EXIT
python3 .scratch/1341-ledger/evidence_guard.py start "$result"
set +e
timeout --kill-after=15s 900s godot --headless --editor --path . --import --quit > "$result/import.log" 2>&1
import_exit=$?
RESULT_DIR="$result" GUT_TIMEOUT_SECONDS=900 bash scripts/run_gut_validation.sh > "$result/full-runner.log" 2>&1
suite_exit=$?
bash scripts/check_record_sync.sh > "$result/record-sync.log" 2>&1
record_exit=$?
set -e
python3 - "$result" "$import_exit" "$suite_exit" "$record_exit" <<'PY'
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as ET
from pathlib import Path
p=Path(sys.argv[1]);problems=[]
try:suites=list(ET.parse(p/'gut.xml').iter('testsuite'))
except (OSError,ET.ParseError):suites=[];problems.append('invalid_junit')
expected={str(f) for root in ['tests/unit','tests/integration'] for f in Path(root).rglob('test_*.gd')}
if {s.attrib.get('name') for s in suites}!=expected or len(suites)!=len(expected):problems.append('incomplete_script_coverage')
for suite in suites:
 if int(suite.attrib.get('tests',0))<=0 or any(int(suite.attrib.get(k,0)) for k in ['failures','errors','skipped']):problems.append('suite_not_passing:'+suite.attrib.get('name',''))
for log in ['import.log','gut.log','full-runner.log']:
 try:
  if re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script',(p/log).read_text()):problems.append('script_error:'+log)
 except OSError:problems.append('missing_log:'+log)
try:
 summary=json.loads((p/'validation-summary.json').read_text())
 if summary['status']!='passed' or summary['scripts_expected']!=len(expected) or summary['scripts_ran']!=len(expected):problems.append('standard_summary_not_passing')
except (OSError,ValueError,KeyError):summary={};problems.append('invalid_standard_summary')
observations={}
for scenario in ['creation','retirement','retirement-retry-zero','malformed-zero','replay-zero','loot-retry-zero','create-rollback','retire-rollback','definition-type-zero','read-failure-zero','corrupt-quantity-zero','revision-overflow-1','revision-overflow-2','corrupt-discriminant-zero'] + [kind+'-receipt-'+field+'-zero' for kind in ['create','retire'] for field in ['operation_kind','instance_id','instance_revision','owner_revision','location_revision']]:
 try:
  observed=json.loads((p/'observations'/(scenario+'.json')).read_text())
  if observed['scenario']!=scenario or observed['observation']['observation_status']!='OBSERVED' or observed['observation']['native_row_effects']!='NOT_OBSERVED':problems.append('invalid_observation:'+scenario)
  observations[scenario]='observations/'+scenario+'.json'
 except (OSError,ValueError,KeyError,TypeError):problems.append('missing_observation:'+scenario)
if any(int(code)!=0 for code in sys.argv[2:]):problems.append('command_failed')
r={'status':'failed' if problems else 'passed','host':'192.168.1.254','engine':subprocess.check_output(['godot','--version'],text=True,stderr=subprocess.DEVNULL,timeout=10).strip(),'revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True,stderr=subprocess.DEVNULL,timeout=10).strip(),'command':'bash .scratch/1341-ledger/run-full.sh '+p.name,'import_exit':int(sys.argv[2]),'suite_exit':int(sys.argv[3]),'record_sync_exit':int(sys.argv[4]),'scripts_expected':len(expected),'scripts_ran':len(suites),'tests':sum(int(s.attrib.get('tests',0)) for s in suites),'failures':sum(int(s.attrib.get('failures',0)) for s in suites),'errors':sum(int(s.attrib.get('errors',0)) for s in suites),'skipped':sum(int(s.attrib.get('skipped',0)) for s in suites),'validation_errors':problems,'observations':observations,'owned_xdg_removed':'NOT_OBSERVED','standard_summary':summary,'source_sha256':{f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in ['server/item_ledger_repository.gd','server/sqlite_store.gd','tests/integration/test_item_ledger_repository.gd','.scratch/1341-ledger/run-full.sh','.scratch/1341-ledger/run-focused.sh']},'milestone_acceptance':'NOT_OBSERVED: integrated equipment/crafting/loot/process recovery'}
(p/'result.json').write_text(json.dumps(r,indent=2)+'\n')
if problems:sys.exit(1)
PY
