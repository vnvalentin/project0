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
    temporary=Path(tempfile.mkdtemp(prefix='project0-1407-controls.'));records=[];completed=False
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
        m.BASELINE_CHILDREN=set(m.owned_children())
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
        nested="import os,signal,time;assert signal.getsignal(signal.SIGCHLD)==signal.SIG_DFL;pid=os.fork();\nif pid==0:os._exit(0)\ndeadline=time.monotonic()+2;info=None\nwhile info is None and time.monotonic()<deadline:info=os.waitid(os.P_PID,pid,os.WEXITED|os.WNOHANG|os.WNOWAIT);time.sleep(0.01)\nassert info is not None and info.si_pid==pid;os.kill(pid,0);assert os.waitpid(pid,0)[0]==pid;print('PASS: safe assertion');print('ALL PASS')"
        reset=m.reset_child_sigchld
        def inherited_ignored_then_reset():
            m.signal.signal(m.signal.SIGCHLD,m.signal.SIG_IGN);reset()
        m.reset_child_sigchld=inherited_ignored_then_reset
        result=m.observe([[sys.executable,'-c',nested]],[{'PATH':'/usr/bin:/bin'}],{'safe assertion'},3)[0]
        assert result['exit_code']==0 and result['all_pass'] and result['passed_assertions']==['safe assertion'] and not m.owned_children()
        m.reset_child_sigchld=reset
        records.append({'case':'nested_child_default_and_waitable_pid','passed':True})
        cases=['nondefault_sigchld','initial_custody_unavailable','valid','prepared_before_consumers','normal_generated_sidecar','normal_generated_svg','normal_generated_font','normal_generated_bitmap_font','orphan_generated_sidecar','nonasset_generated_sidecar','foreign_generated_source_file','foreign_generated_destination','sidecar_wrong_importer','sidecar_symlink','sidecar_changed_after_shared','sidecar_added_after_shared','sidecar_removed_after_shared','sidecar_parent_changed_after_shared','sidecar_missing_cache','consumer_override_changed','preparation_log_changed','helper_source_changed','missing_preparation_report','wrong_preparation_source','altered_executable_mode','unexpected_prepared_private_file','changed_registry','consumer_registry_changed','consumer_config_changed','prepared_parent_symlink','dirty_source','changed_source','metadata_unavailable','metadata_timeout','unsupported_engine','import_failure','import_marker','missing_readiness','missing_assertion','child_timeout','cleanup_failure','retention_failure','existing_override','altered_staged_copy','altered_logging_override']
        assert len(cases)==len(set(cases))
        for case in cases:
            root=temporary/case;root.mkdir();shutil.copyfile(SOURCE,root/'runner.py');m=load(root/'runner.py');m.ROOT=root
            (root/'scripts').mkdir();shutil.copy2(ROOT/'scripts/prepare_godot_project.py',root/'scripts/prepare_godot_project.py');(root/'scripts/test_prediction_reconciliation.gd').write_text('_assert(true, "safe assertion")\n')
            (root/'project.godot').write_text('config/name="Project0"\n')
            (root/'scripts/fixture.sh').write_text('#!/bin/sh\nexit 0\n');(root/'scripts/fixture.sh').chmod(0o755)
            (root/'.scratch').mkdir();(root/'.scratch/fixture.txt').write_text('SYNTHETIC_EXCLUDED_STAGING_FIXTURE')
            (root/'fixtures').mkdir();(root/'fixtures/icon.png').write_bytes(b'\x89PNG\r\n\x1a\nSYNTHETIC_AUTHORED_ASSET_1407')
            for name in ['icon.svg','font.ttf','font.fnt']:(root/'fixtures'/name).write_text('SYNTHETIC_AUTHORED_ASSET_1407')
            source_names=['fixtures/icon.svg','fixtures/font.ttf','fixtures/font.fnt','fixtures/icon.png','project.godot','scripts/test_prediction_reconciliation.gd','scripts/prepare_godot_project.py','scripts/fixture.sh','.scratch/fixture.txt']
            calls=[];identity_calls=[0];prepared_project=[None]
            def identity():
                identity_calls[0]+=1
                if case=='dirty_source':raise ValueError('copied dirty source')
                return {'revision':('b' if case=='changed_source' and identity_calls[0]>1 else 'a')*40,'source_sha256':{p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/name for name in source_names]}}
            m.identity=identity
            if case=='initial_custody_unavailable':
                def unavailable_children():raise OSError('copied proc unavailable')
                m.owned_children=unavailable_children
            if case=='existing_override':(root/'override.cfg').write_text('copied existing override')
            original_stage=getattr(m,'stage_project',None)
            def stage(temporary,source):
                project=original_stage(temporary,source)
                if case=='altered_staged_copy':(project/'scripts/test_prediction_reconciliation.gd').write_text('changed copied source')
                if case=='altered_logging_override':(project/'override.cfg').write_text('[debug]\nfile_logging/enable_file_logging.pc=true\n')
                m.qualify_staged(project,source)
                return project
            if original_stage is not None:m.stage_project=stage
            original_run=m.subprocess.run;original_output=m.subprocess.check_output
            original_pidfd=m.os.pidfd_open;original_signal=m.signal.pidfd_send_signal
            original_getsignal=m.signal.getsignal;original_mkdtemp=m.tempfile.mkdtemp;original_bytes=Path.read_bytes
            if case=='nondefault_sigchld':m.signal.getsignal=lambda sig:m.signal.SIG_IGN if sig==m.signal.SIGCHLD else original_getsignal(sig)
            if case=='initial_custody_unavailable':
                def forbidden_signal(*args,**kwargs):raise AssertionError('unknown custody must not open pidfd or signal child')
                m.os.pidfd_open=forbidden_signal;m.signal.pidfd_send_signal=forbidden_signal
            def fake_run(command,**kwargs):
                path=Path(command[-1]);path.write_text(json.dumps({'passed':True,'errors':[],'runtime_executed':False}))
                return subprocess.CompletedProcess(command,0)
            def fake_output(command,**kwargs):
                assert kwargs.get('timeout')==10 and kwargs.get('preexec_fn') is m.reset_child_sigchld
                project=Path(command[command.index('--path')+1]);assert project!=root
                if (project/'project.godot').exists():
                    assert (project/'override.cfg').read_text()==m.LOGGING_OVERRIDE
                    assert (project/'scripts/test_prediction_reconciliation.gd').read_bytes()==(root/'scripts/test_prediction_reconciliation.gd').read_bytes()
                else:assert not list(project.iterdir())
                if case=='metadata_unavailable':raise OSError('copied metadata unavailable')
                if case=='metadata_timeout':raise subprocess.TimeoutExpired(command,10)
                return b'4.7.2.stable.official.synthetic\n' if case=='unsupported_engine' else b'4.3.stable.official.77dcf97d8\n'
            generated_cases=['normal_generated_sidecar','normal_generated_svg','normal_generated_font','normal_generated_bitmap_font','orphan_generated_sidecar','nonasset_generated_sidecar','foreign_generated_source_file','foreign_generated_destination','sidecar_wrong_importer','sidecar_symlink','sidecar_changed_after_shared','sidecar_added_after_shared','sidecar_removed_after_shared','sidecar_parent_changed_after_shared','sidecar_missing_cache']
            def write_sidecar(project):
                asset={'normal_generated_svg':'fixtures/icon.svg','normal_generated_font':'fixtures/font.ttf','normal_generated_bitmap_font':'fixtures/font.fnt'}.get(case,'fixtures/icon.png')
                importer,kind,suffix={'.png':('texture','CompressedTexture2D','.ctex'),'.svg':('texture','CompressedTexture2D','.ctex'),'.ttf':('font_data_dynamic','FontFile','.fontdata'),'.fnt':('font_data_bmfont','FontFile','.fontdata')}[Path(asset).suffix]
                destination='res://.godot/imported/'+Path(asset).name+'-'+('1'*32)+suffix
                cache=project/destination.removeprefix('res://');cache.parent.mkdir(parents=True,exist_ok=True);cache.write_bytes(b'SYNTHETIC_IMPORT_CACHE_1407')
                sidecar=project/(asset+'.import')
                sidecar.write_text('[remap]\nimporter='+json.dumps(importer)+'\ntype='+json.dumps(kind)+'\npath='+json.dumps(destination)+'\n\n[deps]\nsource_file='+json.dumps('res://'+asset)+'\ndest_files='+json.dumps([destination])+'\n\n[params]\ngenerate/mipmaps=false\n')
                return sidecar,cache
            def observe(commands,envs,allowed,limit):
                if '--prepared-root' in commands[0]:
                    command=commands[0];calls.append('prepare')
                    project=Path(command[command.index('--prepared-root')+1]);assert not project.exists()
                    project.mkdir();prepared_project[0]=project
                    hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in source_names if not name.startswith('.scratch/')}
                    for name in hashes:
                        target=project/name;target.parent.mkdir(parents=True,exist_ok=True)
                        shutil.copy2(root/name,target)
                    (project/'.godot').mkdir();(project/'.godot/extension_list.cfg').write_text('res://addons/godot-sqlite/gdsqlite.gdextension\n')
                    report=Path(command[command.index('--report')+1])
                    phase={'status':'failed' if case in ['import_failure','import_marker'] else 'passed','exit_code':1 if case=='import_failure' else 0,'timed_out':False,'script_error_observed':case=='import_marker','non_script_error_observed':False,'output_valid':True}
                    receipt={'schema_version':1,'status':'passed','exit_code':0,'source_revision':'a'*40,'prepared_root':str(project),
                        'bootstrap':dict(phase),'qualification':dict(phase),'configuration_restored':True,'source_custody_qualified':True,
                        'configuration_custody_lost':False,'prepared_root_created':True,'source_manifest':hashes,
                        'source_sha256':hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest(),
                        'source_inventory_kind':'git-tracked','configuration_original_sha256':hashes['project.godot']}
                    for name in ['bootstrap','qualification']:
                        log=report.parent/('prepare-'+name+'.log');log.write_text(('SCRIPT ERROR: preparation script error observed\n' if phase['script_error_observed'] else '')+'PREPARATION: '+json.dumps(phase,sort_keys=True)+'\n');receipt[name]['log']=str(log)
                        if case=='preparation_log_changed' and name=='qualification':log.write_text('SYNTHETIC_EXCLUDED_RAW_PREPARATION\n')
                    if case=='wrong_preparation_source':receipt['source_revision']='b'*40
                    report.write_text(json.dumps(receipt))
                    if case in generated_cases and case!='sidecar_added_after_shared':
                        sidecar,cache=write_sidecar(project)
                        if case=='orphan_generated_sidecar':sidecar.rename(project/'fixtures/missing.png.import')
                        if case=='nonasset_generated_sidecar':sidecar.rename(project/'scripts/fixture.sh.import')
                        if case=='foreign_generated_source_file':sidecar.write_text(sidecar.read_text().replace('source_file="res://fixtures/icon.png"','source_file="res://outside/other.png"'))
                        if case=='foreign_generated_destination':sidecar.write_text(sidecar.read_text().replace('res://.godot/imported/','res://outside/'))
                        if case=='sidecar_wrong_importer':sidecar.write_text(sidecar.read_text().replace('importer="texture"','importer="script"'))
                        if case=='sidecar_symlink':sidecar.rename(project/'.godot/sidecar-retained');sidecar.symlink_to(project/'.godot/sidecar-retained')
                        if case=='sidecar_missing_cache':cache.unlink()
                    if case=='missing_preparation_report':report.unlink()
                    if case=='altered_executable_mode':(project/'scripts/fixture.sh').chmod(0o644)
                    if case=='unexpected_prepared_private_file':(project/'.scratch').mkdir();(project/'.scratch/fixture.txt').write_text('SYNTHETIC_EXCLUDED_STAGING_FIXTURE')
                    if case=='prepared_parent_symlink':shutil.rmtree(project/'scripts');(project/'scripts').symlink_to(root/'scripts',target_is_directory=True)
                    if case=='changed_registry':(project/'.godot/extension_list.cfg').write_text('copied unknown registry')
                    if case=='helper_source_changed':
                        helper=root/'scripts/prepare_godot_project.py';helper.write_text(helper.read_text()+f'\nPath({str(root / "forbidden-helper-marker")!r}).write_text("copied unexpected execution")\n')
                    if case=='altered_staged_copy':(project/'scripts/test_prediction_reconciliation.gd').write_text('changed copied source')
                    if case=='altered_logging_override':(project/'override.cfg').write_text('copied unknown override')
                    return [{'exit_code':0,'timed_out':False,'script_error_observed':False}]
                project=Path(commands[0][commands[0].index('--path')+1]);assert (project/'override.cfg').read_text()==m.LOGGING_OVERRIDE
                # The unchanged harness derives nested server --path from res://.
                assert project!=root and (project/'scripts/test_prediction_reconciliation.gd').is_file()
                calls.append('import' if '--import' in commands[0] else ('shared' if Path(envs[0]['HOME']).parent.parent.name=='shared' else 'distinct'))
                assert (project/'scripts/fixture.sh').stat().st_mode & 0o100 and not (project/'.scratch').exists()
                if case=='consumer_registry_changed' and calls[-1]=='distinct':(project/'.godot/extension_list.cfg').write_text('copied unknown consumer registry')
                if case=='consumer_config_changed' and calls[-1]=='distinct':(project/'project.godot').write_text('copied unknown consumer configuration')
                if case=='consumer_override_changed' and calls[-1]=='distinct':(project/'override.cfg').write_text('copied unknown consumer override')
                if calls[-1]=='shared':
                    sidecar=project/'fixtures/icon.png.import'
                    if case=='sidecar_changed_after_shared':sidecar.write_text(sidecar.read_text()+'; synthetic changed state\n')
                    if case=='sidecar_added_after_shared':write_sidecar(project)
                    if case=='sidecar_removed_after_shared':sidecar.unlink()
                    if case=='sidecar_parent_changed_after_shared':(project/'fixtures').rename(project/'detached-fixtures');(project/'fixtures').symlink_to(root/'fixtures',target_is_directory=True)
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
            def guarded_bytes(path):
                if case=='prepared_parent_symlink' and prepared_project[0] is not None and path.parent==prepared_project[0]/'scripts':raise AssertionError('source read before parent custody qualification')
                return original_bytes(path)
            Path.read_bytes=guarded_bytes
            m.tempfile.mkdtemp=lambda **kwargs:original_mkdtemp(dir=temporary,**kwargs)
            m.subprocess.run=fake_run;m.subprocess.check_output=fake_output
            try:
                stream=io.StringIO()
                with contextlib.redirect_stdout(stream):code=m.run('control')
                path=root/'build/validation/1407-isolation/control/result.json'
                expected=0 if case in ['valid','prepared_before_consumers','normal_generated_sidecar','normal_generated_svg','normal_generated_font','normal_generated_bitmap_font','missing_assertion'] else 1
                assert code==expected,case
                if case!='retention_failure':
                    result=json.loads(path.read_text());assert result['status']==('observed' if expected==0 else 'failed'),case
                    assert result['cleanup_verified']==(case not in ['cleanup_failure','initial_custody_unavailable','consumer_override_changed','changed_source','altered_staged_copy','altered_logging_override','preparation_log_changed','helper_source_changed','missing_preparation_report','wrong_preparation_source','altered_executable_mode','unexpected_prepared_private_file','changed_registry','consumer_registry_changed','consumer_config_changed','prepared_parent_symlink','orphan_generated_sidecar','nonasset_generated_sidecar','foreign_generated_source_file','foreign_generated_destination','sidecar_wrong_importer','sidecar_symlink','sidecar_changed_after_shared','sidecar_added_after_shared','sidecar_removed_after_shared','sidecar_parent_changed_after_shared','sidecar_missing_cache']),case
                    if case in ['valid','prepared_before_consumers','normal_generated_sidecar','normal_generated_svg','normal_generated_font','normal_generated_bitmap_font']:assert [pair['mode'] for pair in result['comparisons']]==['shared','distinct'] and all(len(pair['children'])==2 for pair in result['comparisons'])
                    if case=='consumer_override_changed':assert result['process_cleanup_verified'] is True and Path(result['retained_stage']).is_dir() and (Path(result['retained_stage'])/'project/override.cfg').read_text()=='copied unknown consumer override'
                    if case=='initial_custody_unavailable':assert result['initial_child_custody']=='NOT_OBSERVED' and not calls
                    if case=='nondefault_sigchld':assert result['stage']=='child_signal_contract' and not calls and identity_calls[0]==0
                    if case=='unsupported_engine':assert result['stage']=='engine_metadata' and not calls
                    if case=='missing_assertion':assert all(child['public_assertion_verdict']=='failed' for mode in result['comparisons'] for child in mode['children'])
                    (output/(case+'-result.json')).write_text(json.dumps(result,indent=2)+'\n')
                else:assert 'NOT_OBSERVED' in stream.getvalue()
                if case=='helper_source_changed':assert not (root/'forbidden-helper-marker').exists(),case
                if case in ['prepared_before_consumers','normal_generated_sidecar','normal_generated_svg','normal_generated_font','normal_generated_bitmap_font']:assert calls==['prepare','shared','distinct'],case
                if case in ['orphan_generated_sidecar', 'nonasset_generated_sidecar', 'foreign_generated_source_file', 'foreign_generated_destination', 'sidecar_wrong_importer', 'sidecar_symlink', 'sidecar_changed_after_shared', 'sidecar_added_after_shared', 'sidecar_removed_after_shared', 'sidecar_parent_changed_after_shared', 'sidecar_missing_cache']:
                    assert result['process_cleanup_verified'] is True and Path(result['retained_stage']).is_dir(),case
                    assert calls==(['prepare','shared'] if case.endswith('_after_shared') else ['prepare']),case
                if case in ['normal_generated_sidecar','normal_generated_svg','normal_generated_font','normal_generated_bitmap_font']:assert len(result['generated_sidecars'])==1 and all(record['source_sha256']==result['source_start']['source_sha256'][record['source_asset']] for record in result['generated_sidecars'].values()),case
                if case in ['dirty_source','metadata_unavailable','metadata_timeout','unsupported_engine','import_failure','import_marker']:assert not any(call in ['shared','distinct'] for call in calls),case
                records.append({'case':case,'passed':True})
            finally:
                m.subprocess.run=original_run;m.subprocess.check_output=original_output
                m.os.pidfd_open=original_pidfd;m.signal.pidfd_send_signal=original_signal
                m.signal.getsignal=original_getsignal;m.tempfile.mkdtemp=original_mkdtemp;Path.read_bytes=original_bytes
        completed=True
    finally:
        shutil.rmtree(temporary)
        unchanged=hashlib.sha256(SOURCE.read_bytes()).hexdigest()==before
        report={'status':'passed' if completed and len(records)==52 and unchanged and not temporary.exists() else 'failed','cases':records,
                'actual_source_preserved':unchanged,'copied_context_removed':not temporary.exists(),'godot_run':False,'actual_git_mutation':False}
        (output/'control-result.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps({'status':report['status'],'artifact':str(output/'control-result.json')}))
    return 0 if report['status']=='passed' else 1

if __name__=='__main__':raise SystemExit(main())
