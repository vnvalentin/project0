#!/usr/bin/env python3
"""Copied diagnostic controls. No Godot, actual Git mutation or live database."""
import contextlib
import ctypes
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'.scratch/1407-isolation/run-comparison.py'

def load(path):
    spec=importlib.util.spec_from_file_location('copied_diagnostic',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def main():
    before=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    output=ROOT/'build/validation/1407-isolation'/('controls-'+uuid.uuid4().hex[:12]);output.mkdir(parents=True)
    temporary=Path(tempfile.mkdtemp(prefix='project0-1407-controls.'));records=[]
    try:
        copied=temporary/'runner.py';shutil.copyfile(SOURCE,copied);m=load(copied)
        secret='SYNTHETIC_EXCLUDED_TEXT_1407'
        record={'passed_assertions':set(),'failed_assertions':set(),'all_pass':False,'telemetry_ready':False,'sqlite_lock_observed':False,'script_error_observed':False}
        for line in [secret.encode(),b'PASS: safe assertion',b'ERROR: FAIL: safe assertion',b'database is locked',b'ALL PASS']:
            m.classify(line,record,{'safe assertion'})
        assert secret not in repr(record) and record['sqlite_lock_observed'] and record['failed_assertions']=={'safe assertion'}
        records.append({'case':'output_allowlist','passed':True})
        envroot=temporary/'environment';envroot.mkdir();env=m.minimal_environment(envroot,12345)
        assert not any(key in env for key in ['PROJECT0_ASSERTION_SECRET','PROJECT0_TEST_CHARACTER_ASSERTION','PROJECT0_ACCOUNTS_DB_PATH','PROJECT0_CANON_DB_PATH','PROJECT0_LLM_URL','HTTP_PROXY'])
        assert env['PROJECT0_SERVER_HOST']==env['PROJECT0_SERVER_BIND_ADDRESS']=='127.0.0.1' and env['PROJECT0_SERVER_PORT']=='12345'
        records.append({'case':'minimal_environment','passed':True})
        assert ctypes.CDLL(None).prctl(36,1,0,0,0)==0
        for case,script,limit in [
            ('success',"print('PASS: safe assertion');print('ALL PASS')",2),
            ('timeout',"import time;time.sleep(30)",0.2),
            ('parent_first',"import subprocess,sys;subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']);print('ALL PASS')",0.2),
            ('oversized',"print('x'*10000);print('ALL PASS')",2)]:
            with contextlib.redirect_stdout(io.StringIO()):
                result=m.observe([[sys.executable,'-c',script]],[{'PATH':'/usr/bin:/bin'}],{'safe assertion'},limit)[0]
            assert not m.owned_children(),case
            if case in ['timeout','parent_first']:assert result['timed_out'],case
            if case=='oversized':assert result['oversized_output_discarded'],case
            records.append({'case':case,'passed':True})
        cases=['valid','dirty_source','changed_source','metadata_unavailable','metadata_timeout','import_failure','import_marker','missing_readiness','missing_assertion','child_timeout','cleanup_failure','retention_failure']
        for case in cases:
            root=temporary/case;root.mkdir();shutil.copyfile(SOURCE,root/'runner.py');m=load(root/'runner.py');m.ROOT=root
            (root/'scripts').mkdir();(root/'scripts/test_prediction_reconciliation.gd').write_text('_assert(true, "safe assertion")\n')
            (root/'project.godot').write_text('config/name="Project0"\n')
            calls=[];identity_calls=[0]
            def identity():
                identity_calls[0]+=1
                if case=='dirty_source':raise ValueError('copied dirty source')
                return {'revision':('b' if case=='changed_source' and identity_calls[0]>1 else 'a')*40,'source_sha256':{'copied':'hash'}}
            m.identity=identity
            original_run=m.subprocess.run;original_output=m.subprocess.check_output
            def fake_run(command,**kwargs):
                path=Path(command[-1]);path.write_text(json.dumps({'passed':True,'errors':[],'runtime_executed':False}))
                return subprocess.CompletedProcess(command,0)
            def fake_output(command,**kwargs):
                assert kwargs.get('timeout')==10
                if case=='metadata_unavailable':raise OSError('copied metadata unavailable')
                if case=='metadata_timeout':raise subprocess.TimeoutExpired(command,10)
                return b'4.3.stable.copied\n'
            def observe(commands,envs,allowed,limit):
                calls.append('import' if '--import' in commands[0] else 'harness')
                output=[]
                for env in envs:
                    if '--import' not in commands[0]:
                        target=Path(env['XDG_DATA_HOME'])/'godot/app_userdata/Project0'/m.TELEMETRY;target.touch()
                    output.append({'passed_assertions':[] if case=='missing_assertion' else ['safe assertion'],'failed_assertions':[],
                        'all_pass':True,'telemetry_ready':case!='missing_readiness','sqlite_lock_observed':False,
                        'script_error_observed':case=='import_marker','exit_code':1 if case=='import_failure' else 0,
                        'timed_out':case=='child_timeout' and '--import' not in commands[0]})
                return output
            m.observe=observe
            original_teardown=m.teardown
            if case=='cleanup_failure':m.teardown=lambda _:False
            original_retain=m.retain
            if case=='retention_failure':
                def retain(path,result):path.mkdir();return original_retain(path,result)
                m.retain=retain
            m.subprocess.run=fake_run;m.subprocess.check_output=fake_output
            try:
                stream=io.StringIO()
                with contextlib.redirect_stdout(stream):code=m.run('control')
                path=root/'build/validation/1407-isolation/control/result.json'
                expected=0 if case in ['valid','missing_assertion'] else 1
                assert code==expected,case
                if case!='retention_failure':
                    result=json.loads(path.read_text());assert result['status']==('observed' if expected==0 else 'failed'),case
                    assert result['cleanup_verified']==(case!='cleanup_failure'),case
                    if case=='missing_assertion':assert all(child['public_assertion_verdict']=='failed' for mode in result['comparisons'] for child in mode['children'])
                    (output/(case+'-result.json')).write_text(json.dumps(result,indent=2)+'\n')
                else:assert 'NOT_OBSERVED' in stream.getvalue()
                if case in ['dirty_source','metadata_unavailable','metadata_timeout','import_failure','import_marker']:assert 'harness' not in calls,case
                records.append({'case':case,'passed':True})
            finally:
                m.subprocess.run=original_run;m.subprocess.check_output=original_output
    finally:
        shutil.rmtree(temporary)
        unchanged=hashlib.sha256(SOURCE.read_bytes()).hexdigest()==before
        report={'status':'passed' if len(records)==18 and unchanged and not temporary.exists() else 'failed','cases':records,
                'actual_source_preserved':unchanged,'copied_context_removed':not temporary.exists(),'godot_run':False,'actual_git_mutation':False}
        (output/'control-result.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps({'status':report['status'],'artifact':str(output/'control-result.json')}))
    return 0 if report['status']=='passed' else 1

if __name__=='__main__':raise SystemExit(main())
