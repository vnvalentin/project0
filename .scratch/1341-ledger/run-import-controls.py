#!/usr/bin/env python3
"""Whole copied-runner preparation-stop controls; command tools are explicit stubs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['.scratch/1341-ledger/run-full.sh', '.scratch/1341-ledger/run-focused.sh',
           '.scratch/1341-ledger/evidence_guard.py', '.scratch/1341-ledger/run-import-controls.py',
           'server/item_ledger_repository.gd', 'server/sqlite_store.gd',
           'tests/integration/test_item_ledger_repository.gd']
CASES = ['valid', 'nonzero', 'timeout', 'script_marker', 'missing_log', 'unreadable_log', 'oversized_log']
STUB = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
root=Path(os.environ['CONTROL_ROOT']);case=os.environ['CONTROL_CASE'];name=Path(sys.argv[0]).name
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps({'tool':name,'arguments':sys.argv[1:]})+'\n')
if name=='git':
 if sys.argv[1]=='status':pass
 elif sys.argv[1]=='rev-parse':print('a'*40)
 elif sys.argv[1]=='ls-files':sys.stdout.write('\0'.join(json.loads((root/'tracked.json').read_text()))+'\0')
 else:sys.exit(42)
elif name=='timeout':
 args=sys.argv[1:]
 while args and args[0].startswith('--'):args=args[1:]
 os.execvp(args[1],args[1:])
elif name=='godot':
 if sys.argv[1:]==['--version']:print('COPIED_NO_NATIVE')
 elif '--import' in sys.argv:
  log=Path(os.environ['XDG_DATA_HOME']).parent/'import.log'
  if case=='script_marker':print('SCRIPT ERROR: synthetic preparation marker')
  if case=='missing_log':log.unlink()
  if case=='unreadable_log':log.unlink();log.mkdir()
  if case=='oversized_log':print('x'*1048577)
  if case=='nonzero':sys.exit(42)
  if case=='timeout':sys.exit(124)
 else:sys.exit(42)
else:sys.exit(42)
'''
GUT = r'''import json,os
from pathlib import Path
import xml.etree.ElementTree as E
root=Path.cwd();out=Path(os.environ['RESULT_DIR'])
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps({'tool':'fake-gut'})+'\n')
tests=sorted(str(p) for d in ['tests/unit','tests/integration'] for p in Path(d).rglob('test_*.gd'))
document=E.Element('testsuites')
for test in tests:E.SubElement(document,'testsuite',name=test,tests='1',failures='0',skipped='0')
E.ElementTree(document).write(out/'gut.xml');(out/'gut.log').write_text('synthetic successful suite')
(out/'validation-summary.json').write_text(json.dumps({'status':'passed','scripts_expected':len(tests),'scripts_ran':len(tests),'exit_code':0}))
scenarios=['creation','retirement','retirement-retry-zero','malformed-zero','replay-zero','loot-retry-zero','create-rollback','retire-rollback','definition-type-zero','read-failure-zero','corrupt-quantity-zero','revision-overflow-1','revision-overflow-2','corrupt-discriminant-zero']+[k+'-receipt-'+f+'-zero' for k in ['create','retire'] for f in ['operation_kind','instance_id','instance_revision','owner_revision','location_revision']]
for scenario in scenarios:(out/'observations'/(scenario+'.json')).write_text(json.dumps({'scenario':scenario,'observation':{'observation_status':'OBSERVED','native_row_effects':'NOT_OBSERVED'}}))
'''


def hashes():
    return {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in SOURCES}


def run():
    before = hashes()
    pre_fix = sys.argv[1:] == ['--expect-pre-fix']
    if sys.argv[1:] and not pre_fix:
        return 2
    output = ROOT/'build/validation/1341-ledger'/('import-stop-controls-'+uuid.uuid4().hex[:12])
    output.mkdir(parents=True)
    contexts = Path(tempfile.mkdtemp(prefix='project0-1341-import-controls-'))
    records = []
    report = {'status':'failed','pre_fix':pre_fix,'controls':records,'source_sha256':before,
              'native_godot_run':False,'actual_git_run':False}
    try:
        for case in CASES:
            root = contexts/case
            root.mkdir()
            for source in SOURCES:
                target=root/source
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(ROOT/source,target)
            (root/'tracked.json').write_text(json.dumps(SOURCES))
            scripts=root/'scripts'
            scripts.mkdir()
            (scripts/'fake-gut.py').write_text(GUT)
            (scripts/'run_gut_validation.sh').write_text('#!/bin/bash\nexec python3 scripts/fake-gut.py\n')
            (scripts/'check_record_sync.sh').write_text('#!/bin/bash\nexit 0\n')
            bins=root/'bin'
            bins.mkdir()
            for name in ['git','godot','timeout']:
                path=bins/name
                path.write_text(STUB.replace('#!/usr/bin/env python3','#!'+sys.executable,1))
                path.chmod(0o700)
            environment=os.environ.copy()
            environment.update({'CONTROL_ROOT':str(root),'CONTROL_CASE':case,
                                'PATH':str(bins)+':'+environment['PATH']})
            result=subprocess.run(['/bin/bash','.scratch/1341-ledger/run-full.sh','fixture'],
                                  cwd=root,env=environment,capture_output=True,text=True,timeout=30)
            out=root/'build/validation/1341-ledger/fixture'
            verdict=json.loads((out/'result.json').read_text())
            calls=[json.loads(line) for line in (root/'calls.jsonl').read_text().splitlines()]
            gut_started=any(call['tool']=='fake-gut' for call in calls)
            expected_started=case=='valid' or pre_fix
            assert gut_started==expected_started,(case,'preparation_stop_mismatch')
            assert verdict['cleanup_verified'] is True and verdict['result_retention']=='OBSERVED',case
            if case=='valid' or (pre_fix and case=='oversized_log'):assert result.returncode==0 and verdict['status']=='passed',case
            else:
                assert result.returncode==1 and verdict['status']=='failed',case
                if not pre_fix:assert verdict.get('phase')=='import_qualification' and verdict.get('validation_errors'),case
            (output/(case+'-verdict.json')).write_text(json.dumps(verdict,indent=2)+'\n')
            records.append({'case':case,'status':'passed','gut_started':gut_started,
                            'runner_exit':result.returncode,'cleanup_verified':True})
        assert hashes()==before
        report['status']='passed'
    except (AssertionError, OSError, subprocess.SubprocessError, ValueError) as error:
        report['control_failure_class'] = type(error).__name__
        raise
    finally:
        shutil.rmtree(contexts)
        report.update({'actual_sources_preserved':hashes()==before,
                       'copied_contexts_removed':not contexts.exists()})
        (output/'control-result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'private_artifact':str(output/'control-result.json')}))
    return 0 if report['status']=='passed' else 1


if __name__=='__main__':
    raise SystemExit(run())
