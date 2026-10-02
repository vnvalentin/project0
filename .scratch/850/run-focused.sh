#!/usr/bin/env bash
set -euo pipefail
stage="${1:?stage required}"
expected="${2:?test count required}"
mode="${3:-green}"
[[ "$stage" =~ ^[a-z0-9-]+$ && "$expected" =~ ^[1-9][0-9]*$ && "$mode" =~ ^(red|green)$ ]] || exit 2
cd "$(dirname "$0")/../.."
root="$PWD/build/validation/850"
mkdir -p "$root"
owned_state="$(mktemp -d "$root/state-$stage.XXXXXX")"
cleanup() { rm -rf -- "$owned_state"; }
trap cleanup EXIT
export XDG_DATA_HOME="$owned_state/data"
export DASHBOARD_RESULTS_DIR="$owned_state/dashboard"
export PROJECT0_PERMISSION_EVIDENCE_DIR="$root/$stage-observations"
test ! -e "$PROJECT0_PERMISSION_EVIDENCE_DIR"
mkdir -p "$PROJECT0_PERMISSION_EVIDENCE_DIR"
python3 scripts/check_validation_ownership.py --plan .scratch/850/validation-plan.json --output "$root/$stage-preflight.json" > "$root/$stage-preflight.log"
set +e
timeout --kill-after=5s 90s godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/integration/test_claim_permit_authority.gd -gdisable_colors -gexit -gjunit_xml_file="$root/$stage.xml" > "$root/$stage.log" 2>&1
result=$?
set -e
python3 - "$root" "$stage" "$expected" "$mode" "$result" "$owned_state" <<'PY'
from pathlib import Path
import sys,json,re,xml.etree.ElementTree as E,subprocess
root=Path(sys.argv[1]);stage=sys.argv[2];expected=int(sys.argv[3]);mode=sys.argv[4];code=int(sys.argv[5]);state=Path(sys.argv[6]);r=E.parse(root/f'{stage}.xml').getroot();log=(root/f'{stage}.log').read_text()
observations={f.name:json.loads(f.read_text()) for f in (root/f'{stage}-observations').glob('*.json')}
assert all(o['observation']['observation_status']=='OBSERVED' and o['observation']['native_row_effects']=='NOT_OBSERVED' for o in observations.values())
report={'observation_files':sorted(observations),'source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'worktree_dirty':bool(subprocess.check_output(['git','status','--porcelain'],text=True).strip()),'exit':code,'tests':len(r.findall('.//testcase')),'failures':len(r.findall('.//failure')),'errors':len(r.findall('.//error')),'skips':len(r.findall('.//skipped')),'script_errors':bool(re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',log)),'fixture_databases_remaining':[str(p.relative_to(state)) for p in state.rglob('*.db*')]}
(root/f'{stage}-result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
assert report['tests']==expected and not report['errors'] and not report['skips'] and not report['script_errors'] and not report['fixture_databases_remaining']
assert code==0 and not report['failures'] if mode=='green' else code!=0 and report['failures']>0
PY
cleanup
trap - EXIT
python3 - "$root/$stage-result.json" "$owned_state" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]);r=json.loads(p.read_text());r['cleanup_complete']=not Path(sys.argv[2]).exists();p.write_text(json.dumps(r,indent=2)+'\n');assert r['cleanup_complete']
PY
