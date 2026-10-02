#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
run="${1:?new run id required}"
case "$run" in *[!a-zA-Z0-9_-]*|'') exit 2;; esac
result="$PWD/build/validation/1341-ledger/$run"
test ! -e "$result"
mkdir -p "$result/user-data"
export XDG_DATA_HOME="$result/user-data"
export DASHBOARD_RESULTS_DIR="$result/dashboard"
export PROJECT0_LEDGER_EVIDENCE_DIR="$result/observations"
mkdir -p "$PROJECT0_LEDGER_EVIDENCE_DIR"
cleanup() {
  local cleanup_exit=0
  rm -rf -- "$XDG_DATA_HOME" || cleanup_exit=$?
  python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); f=p/'result.json'
r=json.loads(f.read_text()) if f.exists() else {'status':'failed','reason':'result_preparation_not_observed'}
r['owned_xdg_removed']=not (p/'user-data').exists()
if not r['owned_xdg_removed']: r['status']='failed'
f.write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r))
PY
  return "$cleanup_exit"
}
trap cleanup EXIT
set +e
timeout --kill-after=15s 900s godot --headless --editor --path . --import --quit > "$result/import.log" 2>&1
import_exit=$?
timeout --kill-after=15s 180s godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.scratch/1341-ledger/focused-gut.json -gjunit_xml_file="$result/gut.xml" -gdisable_colors -gexit > "$result/gut.log" 2>&1
exit_code=$?
set -e
python3 - "$result" "$import_exit" "$exit_code" <<'PY'
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as ET
from pathlib import Path
p=Path(sys.argv[1]); root=None
try: root=ET.parse(p/'gut.xml').getroot()
except (ET.ParseError,OSError): pass
suites=list(root.iter('testsuite')) if root is not None else []
selected=[s for s in suites if s.attrib.get('name')=='tests/integration/test_item_ledger_repository.gd']
tests=sum(int(s.attrib.get('tests',0)) for s in selected)
failures=sum(int(s.attrib.get('failures',0)) for s in selected)
errors=sum(int(s.attrib.get('errors',0)) for s in selected)
skipped=sum(int(s.attrib.get('skipped',0)) for s in selected)
expected_tests=len(re.findall(r'^func test_',Path('tests/integration/test_item_ledger_repository.gd').read_text(),re.M))
observation_errors=[]
for scenario in ['creation','retirement','retirement-retry-zero','malformed-zero','replay-zero','loot-retry-zero','create-rollback','retire-rollback','definition-type-zero','read-failure-zero','corrupt-quantity-zero','revision-overflow-1','revision-overflow-2','corrupt-discriminant-zero']:
 try:
  observation=json.loads((p/'observations'/(scenario+'.json')).read_text())
  if observation['scenario']!=scenario or observation['observation']['observation_status']!='OBSERVED' or observation['observation']['native_row_effects']!='NOT_OBSERVED': observation_errors.append(scenario)
 except (OSError,ValueError,KeyError,TypeError): observation_errors.append(scenario)
script_errors=any(re.search(r"SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script", (p/name).read_text()) for name in ['import.log','gut.log'])
passed=not script_errors and not observation_errors and errors==0 and skipped==0 and tests==expected_tests and int(sys.argv[2])==0 and int(sys.argv[3])==0 and len(selected)==1 and tests>0 and failures==0
r={'status':'passed' if passed else 'failed','host':'192.168.1.254','engine':subprocess.check_output(['godot','--version'],text=True).strip(),'revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'command':'bash .scratch/1341-ledger/run-focused.sh '+p.name,'import_exit':int(sys.argv[2]),'exit_code':int(sys.argv[3]),'script_errors_observed':script_errors,'observation_errors':observation_errors,'expected_tests':expected_tests,'errors':errors,'skipped':skipped,'selected_scripts_ran':len(selected),'tests':tests,'failures':failures,'owned_xdg_removed':'NOT_OBSERVED','source_sha256':{name:hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in ['server/item_ledger_repository.gd','tests/integration/test_item_ledger_repository.gd','.scratch/1341-ledger/run-focused.sh'] if Path(name).is_file()},'milestone_acceptance':'NOT_OBSERVED: runtime equipment/crafting/loot/restart integration'}
(p/'result.json').write_text(json.dumps(r,indent=2)+'\n')
if not passed: sys.exit(1)
PY
