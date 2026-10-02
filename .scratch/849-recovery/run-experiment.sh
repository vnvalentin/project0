#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
label="${1:?unique label required}"
mode="${2:-baseline}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 2
[[ "$mode" == baseline || "$mode" == negative-control ]] || exit 2
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${label}-$$"
result_dir="$PWD/build/validation/849-recovery/$run_id"
test ! -e "$result_dir"
mkdir -p "$result_dir"
fixture_dir="$(mktemp -d /tmp/project0-849-recovery-XXXXXX)"
export XDG_DATA_HOME="$fixture_dir/xdg"
export DASHBOARD_RESULTS_DIR="$result_dir/dashboard"
mkdir -p "$XDG_DATA_HOME" "$DASHBOARD_RESULTS_DIR"
state_path="$fixture_dir/expected.json"
revision="$(git rev-parse HEAD)"
prepare_exit=-1
recover_exit=-1
stage=ownership
engine_version=NOT_OBSERVED
result_exit=1
python3 - "$result_dir/source-start.json" <<'PYHASH'
import hashlib,json,sys
from pathlib import Path
paths=['scripts/test_interior_anchor_process_recovery.gd','.scratch/849-recovery/run-experiment.sh','.scratch/849-recovery/validation-plan.json','server/interior_anchor_repository.gd','shared/interior_anchor_contract.gd','server/sqlite_store.gd','server/canon_repository.gd','server/canon_mutation_repository.gd','server/canon_sector_integrity.gd']
Path(sys.argv[1]).write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths},indent=2)+'\n')
PYHASH
finish() {
  trap - EXIT
  set +e
  case "$fixture_dir" in /tmp/project0-849-recovery-*) rm -rf -- "$fixture_dir" ;; *) exit 2 ;; esac
  cleanup=false
  test ! -e "$fixture_dir" && cleanup=true
  python3 - "$result_dir" "$run_id" "$revision" "$engine_version" "$prepare_exit" "$recover_exit" "$stage" "$cleanup" "$mode" "$result_exit" "$label" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
out,run_id,revision,engine,prep_exit,recover_exit,stage,cleanup,mode,exit_code,label=sys.argv[1:]
out=Path(out); errors=[]; phases={}
for phase in ['prepare','recover']:
    try:
        p=json.loads((out/(phase+'.json')).read_text())
        if p.get('schema_version')!=1 or p.get('issue')!=849 or p.get('phase')!=phase: errors.append('invalid_phase:'+phase)
        if not isinstance(p.get('native_pid'),int) or p['native_pid']<=0: errors.append('invalid_pid:'+phase)
        if set(p.get('scenarios',{}))!={'valid','damaged'}: errors.append('incomplete_scenarios:'+phase)
        phases[phase]=p
    except (OSError,ValueError,TypeError): errors.append('missing_or_invalid_phase:'+phase)
for log in ['import.log','prepare.log','recover.log']:
    path=out/log
    if not path.is_file(): errors.append('missing_log:'+log)
    elif any(m in path.read_text(errors='replace') for m in ['SCRIPT ERROR','Parse Error','Compile Error']): errors.append('script_error:'+log)
if cleanup!='true': errors.append('cleanup_unverified')
if int(prep_exit)!=0 or phases.get('prepare',{}).get('status')!='passed' or phases.get('prepare',{}).get('errors')!=[]: errors.append('prepare_not_passed')
expected_recover_errors=[] if mode=='baseline' else ['valid:canon_bytes_unchanged']
expected_recover_exit=0 if mode=='baseline' else 1
recover=phases.get('recover',{})
if int(recover_exit)!=expected_recover_exit or recover.get('errors')!=expected_recover_errors or recover.get('status')!=('passed' if mode=='baseline' else 'failed'): errors.append('recovery_verdict_mismatch')
if phases.get('prepare',{}).get('native_pid')==recover.get('native_pid'): errors.append('same_native_process')
observations={}
for scenario in ['valid','damaged']:
    data=recover.get('scenarios',{}).get(scenario,{})
    try:
        obs=data['observation']
        if obs['observation_status']!='OBSERVED' or obs['scope']!='direct_single_statements_through_this_store' or obs['native_row_effects']!='NOT_OBSERVED': errors.append('unsupported_observation:'+scenario)
        for counts in [obs['totals'],*obs['by_table'].values()]:
            if set(counts)!={'attempted','committed','rolled_back','failed'}: errors.append('incomplete_windows:'+scenario)
            for window in counts.values():
                if window!={'insert':0,'replace':0,'update':0,'delete':0}: errors.append('nonzero_or_incomplete_dml:'+scenario)
        observations[scenario]=obs
        for key in ['canon_utf8_bytes','canon_sha1','ordered_mutation_sha1','ordered_mutation_identities','anchor_sha1','cell_sha1']:
            if data[key]!=phases['prepare']['scenarios'][scenario][key]: errors.append('retained_identity_mismatch:'+scenario+':'+key)
        events=data['ordered_mutation_identities']
        if len(events)!=2 or [e['applied_revision'] for e in events]!=[1,2] or [e['expected_revision'] for e in events]!=[0,1] or any(e['actor_player_id']!='fixture-character-owner' for e in events): errors.append('incomplete_history_identity:'+scenario)
        wanted=('ok','idempotent') if scenario=='valid' else ('invalid_record','invalid_record')
        if (data['resolution_outcome'],data['replay_outcome'])!=wanted: errors.append('public_recovery_outcome:'+scenario)
    except (KeyError,TypeError,ValueError): errors.append('missing_or_invalid_observation:'+scenario)
for phase in phases.values():
    for key in ['generation','scene_assembly','physical_actor_authorization']:
        if phase.get(key)!='NOT_OBSERVED': errors.append('unsupported_acceptance_claim:'+key)
current=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
if current!=revision: errors.append('head_changed_during_run')
sources={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in ['scripts/test_interior_anchor_process_recovery.gd','.scratch/849-recovery/run-experiment.sh','.scratch/849-recovery/validation-plan.json','server/interior_anchor_repository.gd','shared/interior_anchor_contract.gd','server/sqlite_store.gd','server/canon_repository.gd','server/canon_mutation_repository.gd','server/canon_sector_integrity.gd']}
try:
    if json.loads((out/'source-start.json').read_text())!=sources: errors.append('source_changed_during_run')
except (OSError,ValueError): errors.append('source_start_missing')
passed=not errors and int(exit_code)==0
record={'schema_version':1,'issue':849,'run_id':run_id,'host':'192.168.1.254','revision':revision,'engine':engine,'command':'bash .scratch/849-recovery/run-experiment.sh '+label+' '+mode,'phase_command':'timeout --kill-after=10s 60s /usr/local/bin/godot --headless --path . -s scripts/test_interior_anchor_process_recovery.gd -- <phase> <owned-expected-state> <owned-phase-report>','mode':mode,'status':'passed' if passed else 'failed','scope':'two-process Linux anchor recovery; no generation or scene assembly','negative_control_recovery_rejected':mode=='negative-control' and recover.get('status')=='failed','prepare_exit_code':int(prep_exit),'recover_exit_code':int(recover_exit),'stage':stage,'cleanup_verified':cleanup=='true','errors':errors,'native_pids':{k:v.get('native_pid') for k,v in phases.items()},'source_sha256':sources,'statement_observations':observations}
(out/'experiment-result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({k:record[k] for k in ['status','run_id','mode','prepare_exit_code','recover_exit_code','cleanup_verified','errors','native_pids']}))
raise SystemExit(0 if passed else 1)
PY
  evidence_exit=$?
  exit "$evidence_exit"
}
trap finish EXIT
python3 scripts/check_validation_ownership.py --plan .scratch/849-recovery/validation-plan.json --output "$result_dir/plan-ownership.json" > "$result_dir/preflight.log" 2>&1
stage=import
engine_version="$(/usr/local/bin/godot --version)"
timeout --kill-after=10s 60s /usr/local/bin/godot --headless --path . --import > "$result_dir/import.log" 2>&1
! rg -q 'SCRIPT ERROR|Parse Error|Compile Error' "$result_dir/import.log"
stage=prepare
set +e
timeout --kill-after=10s 60s /usr/local/bin/godot --headless --path . -s scripts/test_interior_anchor_process_recovery.gd -- prepare "$state_path" "$result_dir/prepare.json" > "$result_dir/prepare.log" 2>&1
prepare_exit=$?
set -e
[[ "$prepare_exit" -eq 0 ]] || exit "$prepare_exit"
! rg -q 'SCRIPT ERROR|Parse Error|Compile Error' "$result_dir/prepare.log"
if [[ "$mode" == negative-control ]]; then
  python3 - "$state_path" "$fixture_dir/negative-expected.json" <<'PY'
import json,sys
from pathlib import Path
state=json.loads(Path(sys.argv[1]).read_text()); state['valid']['canon_bytes']+='\n'
Path(sys.argv[2]).write_text(json.dumps(state)+'\n')
PY
  state_path="$fixture_dir/negative-expected.json"
fi
stage=recover
set +e
timeout --kill-after=10s 60s /usr/local/bin/godot --headless --path . -s scripts/test_interior_anchor_process_recovery.gd -- recover "$state_path" "$result_dir/recover.json" > "$result_dir/recover.log" 2>&1
recover_exit=$?
set -e
! rg -q 'SCRIPT ERROR|Parse Error|Compile Error' "$result_dir/recover.log"
result_exit=0
