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
python3 scripts/check_validation_ownership.py --plan .scratch/1341-ledger/sync-timing-validation-plan.json --output "$result/preflight.json" > "$result/preflight.log"
git rev-parse HEAD > "$result/start-revision.txt"
test -z "$(git status --porcelain)"
set +e
timeout --kill-after=5s 45s strace -f -ttt -T -e trace=fsync,fdatasync -o "$result/sync.trace" godot --headless --path . -s .scratch/1341-ledger/canon-timing-probe.gd -- "$result/probe.json" > "$result/probe.log" 2>&1
code=$?
set -e
python3 - "$result" "$code" <<'PY'
import hashlib,json,re,subprocess,sys
from pathlib import Path
p=Path(sys.argv[1]);problems=[]
try:probe=json.loads((p/'probe.json').read_text())
except (OSError,ValueError):probe={};problems.append('missing_probe_result')
if probe.get('status')!='passed' or len(probe.get('samples',[]))!=3:problems.append('probe_not_complete')
if re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script',(p/'probe.log').read_text()):problems.append('script_error')
revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True,stderr=subprocess.DEVNULL,timeout=10).strip()
if revision!=(p/'start-revision.txt').read_text().strip() or subprocess.check_output(['git','status','--porcelain'],text=True,stderr=subprocess.DEVNULL,timeout=10).strip():problems.append('source_changed')
if int(sys.argv[2])!=0:problems.append('command_failed')
r={'status':'failed' if problems else 'passed','host':'192.168.1.254','engine':subprocess.check_output(['godot','--version'],text=True,stderr=subprocess.DEVNULL,timeout=10).strip(),'revision':revision,'command':'bash .scratch/1341-ledger/run-sync-timing.sh '+p.name,'exit_code':int(sys.argv[2]),'validation_errors':problems,'probe':probe,'owned_xdg_removed':'NOT_OBSERVED','source_sha256':{f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in ['server/sqlite_store.gd','server/canon_repository.gd','server/canon_generation_coordinator.gd','.scratch/1341-ledger/canon-timing-probe.gd','.scratch/1341-ledger/run-sync-timing.sh','.scratch/1341-ledger/sync-timing-validation-plan.json']},'acceptance':'diagnosis only; existing<=15ms acceptance unchanged'}
trace_path=p/'sync.trace'
trace=trace_path.read_text() if trace_path.exists() else ''
pattern=re.compile(r'^\s*(?:\d+\s+)?(\d+\.\d+)\s+(fsync|fdatasync)\((\d+)\)\s+=\s+(-?\d+).*<(\d+\.\d+)>$')
records=[];unparsed=0
for line in trace.splitlines():
 m=pattern.match(line)
 if m:
  records.append({'start_s':float(m[1]),'syscall':m[2],'fd':int(m[3]),'return':int(m[4]),'elapsed_ms':float(m[5])*1000.0})
 elif 'fsync(' in line or 'fdatasync(' in line or 'resumed>' in line:
  unparsed+=1
windows=[]
for sample in probe.get('samples',[]):
 calls=[c for c in sample.get('store_calls',[]) if c.get('method')=='transaction']
 for call in calls:
  start=call.get('wall_start_s');end=call.get('wall_end_s')
  selected=[x for x in records if start is not None and end is not None and x['start_s']>=start and x['start_s']+x['elapsed_ms']/1000.0<=end]
  windows.append({'iteration':sample['iteration'],'transaction_elapsed_ms':call['elapsed_ms'],'syscalls':selected,'synchronization_wall_ms':sum(x['elapsed_ms'] for x in selected)})
observed=bool(records) and unparsed==0 and len(windows)==3
r['synchronization_observation']={'status':'OBSERVED' if observed else 'NOT_OBSERVED','scope':'owned child fsync/fdatasync only; timestamp-contained public transaction windows; trace adds overhead','transactions':windows,'total_parsed_syscalls':len(records),'unparsed_syscall_lines':unparsed,'limitations':'wall durations can include scheduling/storage wait; no root-cause or <=15ms acceptance inferred'}
if not observed:
 problems.append('synchronization_observation_incomplete');r['status']='failed'
(p/'result.json').write_text(json.dumps(r,indent=2)+'\n')
if problems:sys.exit(1)
PY
