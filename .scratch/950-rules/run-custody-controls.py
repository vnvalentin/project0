#!/usr/bin/env python3
"""Copied whole-runner controls; actual Git and Godot never execute."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
LANE = ROOT / '.scratch/950-rules'
SOURCES = ['server/item_creation_profile.gd', 'tests/unit/test_item_creation_profile.gd',
           'tests/fixtures/item_creation_profile.gd', '.scratch/950-rules/run-focused.sh',
           '.scratch/950-rules/validation-plan.json', '.scratch/950-rules/validation-evidence.py']
CASES = ['valid_delivery','valid_explicit_zero_errors','valid_prepared_dirty','qualified_red','wrong_red_case',
         'multiple_red_cases','unsupported_red_exit','red_without_failure','green_suite_failure',
         'import_nonzero','import_marker','dirty_start','dirty_end','changed_head','changed_source',
         'missing_start_identity','missing_end_identity','missing_end_source',
         'timeout_start_revision','timeout_start_status','timeout_end_revision','timeout_end_status',
         'engine_unavailable','engine_expired','nonmap_start','truncated_start','unreadable_start',
         'invalid_start_fields','nonmap_preflight','truncated_preflight','unreadable_preflight',
         'invalid_junit','gut_marker','missing_case','invalid_counts','invalid_errors','nonzero_errors','root_nonzero_errors','root_invalid_errors','missing_tests','missing_failures','missing_skipped','root_error_node','skipped_case','errored_case','unreadable_log','cleanup_failure','retention_failure','unexpected_result']
STUB = r'''#!/usr/bin/env python3
import json,os,re,sys
from pathlib import Path
import xml.etree.ElementTree as ET
name=Path(sys.argv[0]).name;root=Path(os.environ['CONTROL_ROOT']);case=os.environ['CONTROL_CASE']
phase=(root/'end-phase').exists()
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps({'tool':name,'arguments':sys.argv[1:]})+'\n')
if name=='git':
 if sys.argv[1]=='rev-parse':
  if case=='missing_start_identity' and not phase or case=='missing_end_identity' and phase:sys.exit(1)
  print(('b' if case=='changed_head' and phase else 'a')*40)
 elif sys.argv[1]=='status':
  if case=='valid_prepared_dirty' or case=='dirty_start' and not phase or case=='dirty_end' and phase:print(' M copied-source.gd')
 else:sys.exit(2)
elif name=='timeout':
 args=sys.argv[1:]
 while args and args[0].startswith('--'):args=args[1:]
 if case=='engine_expired' and args[0]=='10s' and args[1:]==['godot','--version']:sys.exit(124)
 args=args[1:];os.execvp(args[0],args)
elif name=='rm':
 if case=='cleanup_failure':sys.exit(1)
 os.execv('/bin/rm',['rm',*sys.argv[1:]])
elif name=='godot':
 if sys.argv[1:]==['--version']:
  if case=='engine_unavailable':sys.exit(1)
  print('COPIED_NO_NATIVE_ENGINE')
 elif '--import' in sys.argv:
  if case=='import_marker':print('SCRIPT ERROR: copied import control')
  sys.exit(3 if case=='import_nonzero' else 0)
 else:
  (root/'gut-called').touch();out=root/'build/validation/950-rules/control'
  names=re.findall(r'^func (test_\w+)\(',Path('tests/unit/test_item_creation_profile.gd').read_text(),re.M)
  red=os.environ['CONTROL_MODE']=='red';bad=[names[-1]] if red or case=='green_suite_failure' else []
  if case=='wrong_red_case':bad=[names[0]]
  if case=='multiple_red_cases':bad=[names[0],names[-1]]
  if case=='red_without_failure':bad=[]
  doc=ET.Element('testsuites');suite=ET.SubElement(doc,'testsuite',name='tests/unit/test_item_creation_profile.gd',tests=str(len(names)),failures=str(len(bad)),skipped='0',time='0.0')
  doc.set('name','GutTests');doc.set('tests',str(len(names)));doc.set('failures',str(len(bad)))
  if case=='valid_explicit_zero_errors':suite.set('errors','0')
  if case=='invalid_errors':suite.set('errors','invalid')
  if case=='nonzero_errors':suite.set('errors','1')
  if case=='root_nonzero_errors':doc.set('errors','1')
  if case=='root_invalid_errors':doc.set('errors','invalid')
  if case=='root_error_node':ET.SubElement(doc,'error')
  if case.startswith('missing_') and case[8:] in ['tests','failures','skipped']:del suite.attrib[case[8:]]
  for item in names:
   node=ET.SubElement(suite,'testcase',name=item)
   if item in bad:ET.SubElement(node,'failure').text='copied assertion'
  ET.ElementTree(doc).write(out/'gut.xml')
  if case=='invalid_junit':(out/'gut.xml').write_text('<bad')
  if case=='gut_marker':print('SCRIPT ERROR: copied GUT control')
  if case=='missing_case':suite.remove(suite[-1]);ET.ElementTree(doc).write(out/'gut.xml')
  if case=='invalid_counts':suite.set('tests','invalid');ET.ElementTree(doc).write(out/'gut.xml')
  if case=='skipped_case':ET.SubElement(suite[-1],'skipped');ET.ElementTree(doc).write(out/'gut.xml')
  if case=='errored_case':ET.SubElement(suite[-1],'error');ET.ElementTree(doc).write(out/'gut.xml')
  initial=out/'source-start.json'
  if case=='nonmap_start':initial.write_text('[]')
  if case=='truncated_start':initial.write_text('{')
  if case=='unreadable_start':initial.unlink();initial.mkdir()
  if case=='invalid_start_fields':v=json.loads(initial.read_text());v['schema_version']=True;initial.write_text(json.dumps(v))
  if case=='changed_source':Path('server/item_creation_profile.gd').write_text('changed copied source')
  if case=='missing_end_source':Path('server/item_creation_profile.gd').unlink()
  if case=='unreadable_log':(out/'gut.log').unlink();(out/'gut.log').mkdir()
  if case=='retention_failure':(out/'result.json').mkdir()
  if case=='unexpected_result':(out/'result.json').write_text('{')
  (root/'end-phase').touch()
  sys.exit(2 if case=='unsupported_red_exit' else 1 if red or case=='green_suite_failure' else 0)
else:sys.exit(2)
'''
HOOK = r'''import os,subprocess
from pathlib import Path
original=subprocess.check_output
case=os.environ.get('CONTROL_CASE','');root=Path(os.environ.get('CONTROL_ROOT','.'))
def bounded(command,**kwargs):
 if command[0]=='git':
  assert kwargs.get('timeout')==10
  phase=(root/'end-phase').exists();key='revision' if command[1]=='rev-parse' else 'status'
  if case=='timeout_'+('end' if phase else 'start')+'_'+key:
   raise subprocess.TimeoutExpired(command,kwargs['timeout'])
 return original(command,**kwargs)
subprocess.check_output=bounded
'''


def fingerprints():
    return {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in SOURCES}


def main():
    os.chdir(ROOT)
    output = ROOT/'build/validation/950-rules'/('custody-controls-'+uuid.uuid4().hex[:12])
    output.mkdir(parents=True)
    before = fingerprints()
    records = []
    context = Path(tempfile.mkdtemp(prefix='project0-950-controls.'))
    try:
        for case in CASES:
            root = context/case
            root.mkdir()
            for name in SOURCES:
                target=root/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
            bins=root/'bin';bins.mkdir()
            for name in ['git','godot','timeout','rm']:
                tool=bins/name;tool.write_text(STUB);tool.chmod(0o700)
            hook=root/'hooks';hook.mkdir();(hook/'sitecustomize.py').write_text(HOOK)
            scripts=root/'scripts';scripts.mkdir()
            (scripts/'check_validation_ownership.py').write_text('''import json,os,sys
from pathlib import Path
out=Path(sys.argv[sys.argv.index('--output')+1]);case=os.environ['CONTROL_CASE']
out.write_text(json.dumps({'schema_version':1,'passed':True,'errors':[],'runtime_executed':False}))
if case=='nonmap_preflight':out.write_text('[]')
if case=='truncated_preflight':out.write_text('{')
if case=='unreadable_preflight':out.unlink();out.mkdir()
''')
            red=case in ['qualified_red','wrong_red_case','multiple_red_cases','unsupported_red_exit','red_without_failure']
            mode='red' if red else 'green'
            binding='prepared' if red or case=='valid_prepared_dirty' else 'delivery'
            expected=len(re.findall(r'^func test_\w+\(', (root/'tests/unit/test_item_creation_profile.gd').read_text(),re.M))
            env={**os.environ,'CONTROL_ROOT':str(root),'CONTROL_CASE':case,'CONTROL_MODE':mode,
                 'PATH':str(bins)+':/usr/bin:/bin','PYTHONPATH':str(hook)}
            result=subprocess.run(['/bin/bash','.scratch/950-rules/run-focused.sh','control',mode,str(expected),binding],cwd=root,env=env,capture_output=True,text=True,timeout=45)
            path=root/'build/validation/950-rules/control/result.json';verdict=None;retained=path.is_file()
            if retained and case!='unexpected_result':verdict=json.loads(path.read_text())
            else:
                for line in result.stdout.splitlines():
                    try:value=json.loads(line)
                    except ValueError:continue
                    if isinstance(value,dict) and value.get('issue')==950:verdict=value
            assert isinstance(verdict,dict),(case,'missing_structured_verdict',result.stderr)
            good=case in ['valid_delivery','valid_explicit_zero_errors','valid_prepared_dirty','qualified_red']
            assert result.returncode==(0 if good else 1),(case,result.returncode,result.stderr,verdict)
            assert verdict['evidence_exit_code']==result.returncode and verdict['status']==('expected_red' if red and good else 'passed' if good else 'failed'),case
            assert verdict['cleanup_verified']==(case!='cleanup_failure'),case
            assert verdict['result_retention']==('NOT_OBSERVED' if case in ['retention_failure','unexpected_result'] else 'OBSERVED'),case
            if case in ['import_nonzero','import_marker','dirty_start','missing_start_identity','timeout_start_revision','timeout_start_status','engine_unavailable','engine_expired','nonmap_preflight','truncated_preflight','unreadable_preflight']:
                assert not (root/'gut-called').exists(),(case,'unexpected_GUT_execution')
            if case in ['import_nonzero','import_marker']:assert verdict['suite_exit']=='NOT_OBSERVED'
            records.append({'case':case,'passed':True,'exit':result.returncode,'structured_verdict_captured':True,
                            'retained_file':retained and case!='unexpected_result','cleanup_verified':verdict['cleanup_verified']})
            (output/(case+'-verdict.json')).write_text(json.dumps(verdict,indent=2)+'\n')
    finally:
        shutil.rmtree(context)
        unchanged=fingerprints()==before
        report={'passed':len(records)==len(CASES) and unchanged and not context.exists(),'cases':records,
                'actual_sources_preserved':unchanged,'copied_context_removed':not context.exists(),
                'godot_run':False,'actual_git_mutation':False}
        (output/'control-result.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps({'status':'passed' if report['passed'] else 'failed','artifact':str(output/'control-result.json')}))
    return 0 if report['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())
