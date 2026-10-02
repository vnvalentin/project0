#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
label="${1:?unique label required}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 2
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${label}-$$"
result_dir="$PWD/build/validation/850/process-recovery/$run_id"
test ! -e "$result_dir" && test ! -L "$result_dir"
mkdir -p "$result_dir"
fixture_dir=""
source_revision=NOT_OBSERVED
engine_version=NOT_OBSERVED
prepare_exit=-1
recover_exit=-1
stage=setup
source_clean_start=false

finish() {
  local runner_exit=$? cleanup_exit=0 finalize_exit=0
  trap - EXIT
  set +e
  case "$fixture_dir" in
    "") ;;
    /tmp/project0-850-recovery-*) rm -rf -- "$fixture_dir"; cleanup_exit=$? ;;
    *) cleanup_exit=2 ;;
  esac
  local cleanup_verified=false
  if [[ -z "$fixture_dir" || ! -e "$fixture_dir" ]]; then cleanup_verified=true; fi
  python3 - "$result_dir" "$run_id" "$label" "$source_revision" "$engine_version" \
    "$prepare_exit" "$recover_exit" "$stage" "$cleanup_verified" "$cleanup_exit" \
    "$runner_exit" "$source_clean_start" <<'PY'
import hashlib,json,re,subprocess,sys
from pathlib import Path

out,run_id,label,revision,engine,prepare_exit,recover_exit,stage,cleanup,cleanup_exit,runner_exit,source_clean_start=sys.argv[1:]
out=Path(out)
errors=[]
sources=['scripts/test_claim_permit_authority_process_recovery.gd',
         '.scratch/850/run-process-recovery.sh','.scratch/850/validation-plan.json',
         'server/claim_permit_authority.gd','server/sqlite_store.gd']

def identity(arguments,fallback,failure):
    try:
        return subprocess.check_output(['git',*arguments],text=True,stderr=subprocess.DEVNULL,timeout=10).strip()
    except (OSError,subprocess.SubprocessError,UnicodeError):
        errors.append(failure)
        return fallback

def hashes():
    result={}
    for source in sources:
        try:
            result[source]=hashlib.sha256(Path(source).read_bytes()).hexdigest()
        except OSError:
            errors.append('source_not_observed:'+source)
            result[source]='NOT_OBSERVED'
    return result

def load_phase(phase):
    try:
        data=json.loads((out/(phase+'.json')).read_text())
        if not isinstance(data,dict):
            raise ValueError('not_object')
        if data.get('schema_version')!=1 or data.get('issue')!=850 or data.get('phase')!=phase:
            errors.append('invalid_phase_identity:'+phase)
        if data.get('status')!='passed' or data.get('errors')!=[]:
            errors.append('phase_not_passed:'+phase)
        if type(data.get('process_id')) is not int or data['process_id']<=0:
            errors.append('invalid_process_id:'+phase)
        if data.get('native_row_effects')!='NOT_OBSERVED':
            errors.append('unsupported_native_row_claim:'+phase)
        return data
    except (OSError,ValueError,TypeError):
        errors.append('missing_or_invalid_phase:'+phase)
        return {}

try:
    start_hashes=json.loads((out/'source-start.json').read_text())
    if not isinstance(start_hashes,dict):
        raise ValueError('not_object')
except (OSError,ValueError,TypeError):
    errors.append('source_start_missing')
    start_hashes={}
final_hashes=hashes()
if start_hashes!=final_hashes:
    errors.append('source_changed_during_run')
final_revision=identity(['rev-parse','HEAD'],'NOT_OBSERVED','final_revision_not_observed')
if revision=='NOT_OBSERVED' or final_revision!=revision:
    errors.append('head_changed_or_unobserved')
final_status=identity(['status','--porcelain'],'NOT_OBSERVED','final_status_not_observed')
if final_status!='':
    errors.append('source_not_clean_at_end')
if cleanup!='true' or cleanup_exit!='0':
    errors.append('fixture_cleanup_unverified')
for name in ['import.log','preflight.log','prepare.log','recover.log']:
    path=out/name
    if not path.is_file():
        if name in ['prepare.log','recover.log'] and stage not in ['recover','complete']:
            continue
        errors.append('missing_log:'+name)
        continue
    try:
        if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',path.read_text(errors='replace')):
            errors.append('script_error:'+name)
    except OSError:
        errors.append('log_not_observed:'+name)
try:
    preflight=json.loads((out/'preflight.json').read_text())
    if not isinstance(preflight,dict) or preflight.get('passed') is not True or preflight.get('errors')!=[]:
        errors.append('ownership_preflight_failed')
except (OSError,ValueError,TypeError):
    errors.append('ownership_preflight_missing')
prepare=load_phase('prepare') if (out/'prepare.json').is_file() else {}
recover=load_phase('recover') if (out/'recover.json').is_file() else {}
if prepare_exit!='0': errors.append('prepare_exit_not_zero')
if recover_exit!='0': errors.append('recover_exit_not_zero')
for key in ['claim_registered','membership_projection_written','permit_committed']:
    if prepare.get('checks',{}).get(key) is not True: errors.append('prepare_not_proven:'+key)
for key in ['claim_recovered','owner_recovered','claim_revision_recovered','member_permission_recovered','unauthorized_visitor_still_denied','permit_receipt_replayed','original_permit_result_preserved','receipt_replay_zero_dml']:
    if recover.get('checks',{}).get(key) is not True: errors.append('recovery_not_proven:'+key)
if prepare and recover and prepare.get('process_id')==recover.get('process_id'):
    errors.append('same_native_process')
observation=recover.get('details',{}).get('observation',{})
if observation.get('observation_status')!='OBSERVED' or observation.get('native_row_effects')!='NOT_OBSERVED':
    errors.append('replay_observation_unqualified')
operations=['insert','replace','update','delete']
windows=['attempted','committed','rolled_back','failed']
def zero_counts(value):
    return isinstance(value,dict) and set(value)==set(operations) and all(type(value[key]) is int and value[key]==0 for key in operations)
totals=observation.get('totals',{})
for window in windows:
    if not isinstance(totals,dict) or not zero_counts(totals.get(window)):
        errors.append('nonzero_or_incomplete_total:'+window)
tables=observation.get('by_table')
if not isinstance(tables,dict):
    errors.append('table_observations_unavailable')
else:
    for table,counts in tables.items():
        for window in windows:
            if not isinstance(counts,dict) or not zero_counts(counts.get(window)):
                errors.append('nonzero_or_incomplete_table:'+str(table)+':'+window)
passed=runner_exit=='0' and not errors
record={'schema_version':1,'issue':850,'run_id':run_id,'label':label,'host':'192.168.1.254',
        'revision':revision,'final_revision':final_revision,'engine':engine,
        'command':'bash .scratch/850/run-process-recovery.sh '+label,
        'phase_command':'timeout --kill-after=10s 60s godot --headless --path . -s scripts/test_claim_permit_authority_process_recovery.gd -- <phase> <expected-state> <phase-report>',
        'scope':'two-process ClaimPermitAuthority persistence and receipt replay',
        'status':'passed' if passed else 'failed','stage':stage,
        'prepare_exit_code':int(prepare_exit),'recover_exit_code':int(recover_exit),
        'native_pids':{'prepare':prepare.get('process_id'),'recover':recover.get('process_id')},
        'source_clean_start':source_clean_start=='true','source_clean_end':final_status=='',
        'cleanup_verified':cleanup=='true' and cleanup_exit=='0','statement_observation':observation,
        'native_row_effects':'NOT_OBSERVED','source_sha256':final_hashes,'errors':errors,'result_retention':'OBSERVED'}
try:
    (out/'experiment-result.json').write_text(json.dumps(record,indent=2)+'\n')
except OSError:
    record['status']='failed';record['result_retention']='NOT_OBSERVED';record['errors'].append('result_retention_not_observed')
    print(json.dumps(record))
    raise SystemExit(1)
print(json.dumps({key:record[key] for key in ['status','run_id','prepare_exit_code','recover_exit_code','native_pids','cleanup_verified','errors']}))
raise SystemExit(0 if passed else 1)
PY
  finalize_exit=$?
  if [[ "$finalize_exit" -ne 0 ]]; then exit "$finalize_exit"; fi
  exit "$runner_exit"
}
trap finish EXIT
trap 'exit 130' INT TERM

stage=source_start
source_revision="$(timeout --kill-after=1s 10s git rev-parse HEAD)"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ -z "$(git status --porcelain)" ]] || exit 1
source_clean_start=true
fixture_dir="$(mktemp -d /tmp/project0-850-recovery-XXXXXX)"
owned_xdg="$fixture_dir/xdg"
mkdir -p "$owned_xdg" "$result_dir/observations"
export XDG_DATA_HOME="$owned_xdg"
export DASHBOARD_RESULTS_DIR="$result_dir/dashboard"

stage=source_fingerprint
python3 - "$result_dir/source-start.json" <<'PYHASH'
import hashlib,json,sys
from pathlib import Path
sources=['scripts/test_claim_permit_authority_process_recovery.gd','.scratch/850/run-process-recovery.sh','.scratch/850/validation-plan.json','server/claim_permit_authority.gd','server/sqlite_store.gd']
Path(sys.argv[1]).write_text(json.dumps({path:hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in sources},indent=2)+'\n')
PYHASH
stage=ownership_preflight
python3 scripts/check_validation_ownership.py --plan .scratch/850/validation-plan.json --output "$result_dir/preflight.json" > "$result_dir/preflight.log" 2>&1
stage=engine_import
engine_version="$(godot --version)"
timeout --kill-after=10s 60s godot --headless --path . --import --quit > "$result_dir/import.log" 2>&1
python3 - "$result_dir/import.log" <<'PYSCAN'
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(errors='replace')
raise SystemExit(1 if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',text) else 0)
PYSCAN
run_phase() {
  local phase="$1" report="$result_dir/$1.json"
  timeout --kill-after=10s 60s godot --headless --path . -s scripts/test_claim_permit_authority_process_recovery.gd -- "$phase" "$result_dir/expected.json" "$report" > "$result_dir/$phase.log" 2>&1
  python3 - "$result_dir/$phase.log" <<'PYSCAN'
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(errors='replace')
raise SystemExit(1 if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',text) else 0)
PYSCAN
}
stage=prepare
set +e
run_phase prepare
prepare_exit=$?
set -e
[[ "$prepare_exit" -eq 0 ]] || exit "$prepare_exit"
stage=recover
set +e
run_phase recover
recover_exit=$?
set -e
[[ "$recover_exit" -eq 0 ]] || exit "$recover_exit"
stage=complete
exit 0