#!/usr/bin/env python3
"""Reproducible copied whole-runner #850 controls; native/Git tools are stubs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid

PROJECT = Path(__file__).resolve().parents[2]
SOURCES = ['server/claim_permit_authority.gd', 'server/sqlite_store.gd',
           'tests/integration/test_claim_permit_authority.gd', '.scratch/850/run-full.sh',
           '.scratch/850/run-focused.sh', '.scratch/850/observation-manifest.json',
           '.scratch/850/validation-plan.json', '.scratch/850/full-validation-plan.json',
           '.scratch/850/validation-evidence.py', '.scratch/850/run-evidence-controls.py']
CASES = ['valid', 'initial_git_missing', 'initial_git_timeout', 'initial_sha_invalid',
         'preflight_failed', 'setup_failed', 'start_truncated', 'start_list', 'source_changed', 'head_changed', 'dirty_end',
         'final_git_missing', 'final_source_missing', 'engine_missing', 'engine_timeout',
         'result_truncated', 'result_list', 'result_shape', 'cleanup_failed', 'retention_failed']
STUB = r'''#!/usr/bin/env python3
import json,os,subprocess,sys,time
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(os.environ['CONTROL_ROOT']); case=os.environ['CONTROL_CASE']; kind=os.environ['CONTROL_KIND']
name=Path(sys.argv[0]).name; phase=(root/'phase').exists()
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps({'tool':name,'arguments':sys.argv[1:]})+'\n')
if name=='git':
 if sys.argv[1]=='rev-parse':
  if case=='initial_git_missing' and not phase or case=='final_git_missing' and phase:sys.exit(42)
  if case=='initial_git_timeout' and not phase:time.sleep(1)
  print('invalid' if case=='initial_sha_invalid' else ('b' if case=='head_changed' and phase else 'a')*40)
 elif sys.argv[1]=='status':
  if case=='dirty_start' and not phase or case=='dirty_end' and phase:print(' M fixture.gd')
 else:sys.exit(42)
elif name=='godot':
 if sys.argv[1:]==['--version']:
  if case=='engine_missing':sys.exit(42)
  if case=='engine_timeout':time.sleep(1)
  print('COPIED_CONTROL_NO_NATIVE')
 elif '--import' not in sys.argv:generate()
 elif '--import' in sys.argv:
  if case=='import_failed':sys.exit(42)
  if case=='import_markers':print('SCRIPT ERROR: copied preparation fixture')
elif name=='fake-gut':generate()
elif name=='timeout':
 args=sys.argv[1:]
 while args and args[0].startswith('--'):args=args[1:]
 os.execvp(args[1],args[1:])
elif name=='mkdir':
 if case=='setup_failed' and any(a.endswith('/user-data') for a in sys.argv[1:]):sys.exit(42)
 os.execv('/usr/bin/mkdir',['mkdir',*sys.argv[1:]])
elif name=='mktemp':
 if case=='setup_failed':sys.exit(42)
 os.execv('/usr/bin/mktemp',['mktemp',*sys.argv[1:]])
elif name=='rm':
 if case=='cleanup_failed':sys.exit(42)
 os.execv('/usr/bin/rm',['rm',*sys.argv[1:]])
elif name=='python3':
 p=subprocess.run([os.environ['CONTROL_PYTHON'],*sys.argv[1:]])
 if len(sys.argv)>2 and sys.argv[1]=='.scratch/850/validation-evidence.py' and sys.argv[2]=='collect' and p.returncode==0:
  target=Path(sys.argv[3])
  if case=='start_truncated':Path(str(target)+'.source-start.json').write_text('{')
  if case=='start_list':Path(str(target)+'.source-start.json').write_text('[]')
  if case=='result_truncated':target.write_text('{')
  if case=='result_list':target.write_text('[]')
  if case=='result_shape':target.write_text('{"status":"passed"}')
  if case=='retention_failed':target.unlink();target.mkdir()
 sys.exit(p.returncode)
else:sys.exit(42)
'''
GENERATOR = r'''
def generate():
 if kind=='full':
  out=Path(os.environ['RESULT_DIR']); tests=json.loads(Path('.scratch/850/full-validation-plan.json').read_text())['steps'][0]['tests']; xml=out/'gut.xml'
 else:
  xml=Path(next(a.split('=',1)[1] for a in sys.argv if a.startswith('-gjunit_xml_file=')));out=xml.parent;tests=['tests/integration/test_claim_permit_authority.gd']
 red=case=='valid_red';document=E.Element('testsuites')
 for test in tests:
  suite=E.SubElement(document,'testsuite',name=test,tests='2',failures='1' if red else '0',errors='0',skipped='0')
  for i in range(2):
   item=E.SubElement(suite,'testcase',name='fixture'+str(i))
   if red and i==0:E.SubElement(item,'failure').text='expected fixture rejection'
 E.ElementTree(document).write(xml)
 if kind=='full':
  (out/'gut.log').write_text('synthetic control log; no native\n')
  (out/'validation-summary.json').write_text(json.dumps({'status':'passed','scripts_expected':len(tests),'scripts_ran':len(tests),'exit_code':0}))
 observations=Path(os.environ['PROJECT0_PERMISSION_EVIDENCE_DIR']);observations.mkdir(exist_ok=True)
 for filename in json.loads(Path('.scratch/850/observation-manifest.json').read_text()):
  (observations/filename).write_text(json.dumps({'observation':{'observation_status':'OBSERVED','native_row_effects':'NOT_OBSERVED'}}))
 if case=='source_changed':Path('server/claim_permit_authority.gd').write_text('changed copied source')
 if case=='final_source_missing':Path('server/claim_permit_authority.gd').unlink()
 (root/'phase').write_text('end')
 if red:sys.exit(1)
'''


def hashes():
    return {name: hashlib.sha256((PROJECT/name).read_bytes()).hexdigest() for name in SOURCES}


def run():
    before = hashes()
    output = PROJECT/'build/validation/850'/('whole-evidence-controls-'+uuid.uuid4().hex[:12])
    output.mkdir(parents=True)
    context = Path(tempfile.mkdtemp(prefix='project0-850-evidence-controls-'))
    records = []
    report = {'schema_version': 1, 'issue': 850, 'status': 'failed', 'controls': records,
              'native_godot_run': False, 'actual_git_mutation': False, 'source_sha256': before}
    try:
        inventory = json.loads((PROJECT/'.scratch/850/full-validation-plan.json').read_text())['steps'][0]['tests']
        for kind in ['focused','full']:
            for case in CASES+(['valid_red'] if kind=='focused' else ['dirty_start','import_failed','import_markers']):
                root=context/(kind+'-'+case);root.mkdir()
                for source in SOURCES:
                    target=root/source;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(PROJECT/source,target)
                if case in ['initial_git_timeout','engine_timeout']:
                    helper=root/'.scratch/850/validation-evidence.py';helper.write_text(helper.read_text().replace('timeout=10','timeout=0.1'))
                for test in inventory:
                    target=root/test;target.parent.mkdir(parents=True,exist_ok=True)
                    if not target.exists():target.write_text('copied inventory fixture\n')
                scripts=root/'scripts';scripts.mkdir(exist_ok=True)
                (scripts/'check_validation_ownership.py').write_text('raise SystemExit('+('42' if case=='preflight_failed' else '0')+')\n')
                (scripts/'check_record_sync.sh').write_text('#!/bin/bash\ntouch record-sync-called\nexit 0\n')
                (scripts/'run_gut_validation.sh').write_text('#!/bin/bash\nexec fake-gut\n')
                fake=root/'bin';fake.mkdir()
                # Define the fixture generator before dispatch in each explicit stub.
                dispatch=STUB.replace("if name=='git':",GENERATOR+"\nif name=='git':")
                for name in ['git','godot','timeout','rm','mkdir','mktemp','python3','fake-gut']:
                    tool=fake/name;tool.write_text(dispatch.replace('#!/usr/bin/env python3', '#!'+sys.executable, 1));tool.chmod(0o700)
                environment=os.environ.copy();environment.update({'CONTROL_ROOT':str(root),'CONTROL_CASE':case,'CONTROL_KIND':kind,'CONTROL_PYTHON':sys.executable,'PATH':str(fake)+':'+environment['PATH']})
                if kind=='full': command=['/bin/bash','.scratch/850/run-full.sh','fixture']
                else:command=['/bin/bash','.scratch/850/run-focused.sh','fixture','2','red' if case=='valid_red' else 'green']
                process=subprocess.Popen(command,cwd=root,env=environment,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
                try:
                    stdout,stderr=process.communicate(timeout=20)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid,signal.SIGKILL)
                    stdout,stderr=process.communicate()
                    raise AssertionError((kind,case,'owned control timed out',stdout,stderr))
                result=subprocess.CompletedProcess(command,process.returncode,stdout,stderr)
                target=root/'build/validation/850'/('fixture/result.json' if kind=='full' else 'fixture-result.json')
                if target.is_file(): verdict=json.loads(target.read_text());retained=True
                else:
                    candidates=[]
                    for line in result.stdout.splitlines():
                        try:value=json.loads(line)
                        except ValueError:continue
                        if isinstance(value,dict) and value.get('issue')==850 and 'cleanup_verified' in value:candidates.append(value)
                    assert candidates,(kind,case,'no failed structured verdict',result.stderr)
                    verdict=candidates[-1];retained=False
                valid=case in ['valid','valid_red']
                assert result.returncode==(0 if valid else 1),(kind,case,result.returncode,result.stdout,result.stderr)
                assert verdict['status']==('expected_red' if case=='valid_red' else 'passed' if valid else 'failed'),(kind,case,verdict)
                assert verdict['cleanup_verified']==(case!='cleanup_failed'),(kind,case,verdict)
                assert verdict['result_retention']==('NOT_OBSERVED' if case=='retention_failed' else 'OBSERVED'),(kind,case,verdict)
                if case in ['initial_git_missing','initial_git_timeout','initial_sha_invalid','preflight_failed','dirty_start','setup_failed']:
                    calls=[json.loads(line) for line in (root/'calls.jsonl').read_text().splitlines()]
                    assert not any(call['tool'] in ['godot','fake-gut'] for call in calls),(kind,case,'runtime started')
                if case in ['import_failed','import_markers']:
                    calls=[json.loads(line) for line in (root/'calls.jsonl').read_text().splitlines()]
                    assert not any(call['tool']=='fake-gut' for call in calls),(kind,case,'GUT started after failed preparation')
                    assert not (root/'record-sync-called').exists(),(kind,case,'record sync started after failed preparation')
                    assert verdict['stage']=='import', (kind,case,verdict)
                if case.startswith('engine_'):assert verdict['engine']=='NOT_OBSERVED' and any(error.startswith('engine_') for error in verdict['validation_errors'])
                if case in ['source_changed','head_changed','dirty_end','final_source_missing','final_git_missing']:assert 'source_changed_during_validation' in verdict['validation_errors']
                (output/(kind+'-'+case+'.json')).write_text(json.dumps(verdict,indent=2)+'\n')
                records.append({'runner':kind,'case':case,'status':'passed','runner_exit':result.returncode,'retained_result':retained,'cleanup_qualified':verdict['cleanup_verified'],'validation_errors':verdict['validation_errors']})
        assert hashes()==before
        report['status']='passed'
    finally:
        shutil.rmtree(context)
        report['actual_source_preserved']=hashes()==before
        report['copied_contexts_removed']=not context.exists()
        report['control_count']=len(records)
        (output/'control-result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'control_count':len(records),'control_path':str(output/'control-result.json'),'actual_source_preserved':report['actual_source_preserved'],'copied_contexts_removed':report['copied_contexts_removed'],'native_godot_run':False,'actual_git_mutation':False}))
    return 0 if report['status']=='passed' else 1


if __name__=='__main__':
    raise SystemExit(run())
