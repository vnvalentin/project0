#!/usr/bin/env python3
"""Private supporting fixture comparison; raw child output is never persisted."""
import ctypes
import hashlib
import types
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
HARNESS = 'scripts/test_prediction_reconciliation.gd'
TELEMETRY = 'fixture_telemetry/telemetry.db'
LOGGING_OVERRIDE = '[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n'
NOT = 'NOT_OBSERVED'
BASELINE_CHILDREN = None


def identity():
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True,
                                       stderr=subprocess.DEVNULL, timeout=10).strip()
    revision = git('rev-parse', 'HEAD')
    if not re.fullmatch('[0-9a-f]{40}', revision) or git('status', '--porcelain'):
        raise ValueError('source_not_clean')
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT,
                                    stderr=subprocess.DEVNULL, timeout=10).decode().split('\0')
    return {'revision': revision, 'source_sha256': {n: hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names if n}}


def assertions():
    return set(re.findall(r'_assert\([^\n]+, "([^"]+)"\)', (ROOT/HARNESS).read_text()))



def preparation_contract(source):
    path=ROOT/'scripts/prepare_godot_project.py'
    if path.parent.is_symlink() or path.is_symlink() or not path.is_file():raise ValueError('preparation_helper_unavailable')
    content=path.read_bytes()
    if hashlib.sha256(content).hexdigest()!=source['source_sha256'].get('scripts/prepare_godot_project.py'):
        raise ValueError('preparation_helper_changed')
    # Execute only the source-bound snapshot; never reopen it through an importer.
    module=types.ModuleType('owned_preparation_contract');module.__file__=str(path)
    exec(compile(content,str(path),'exec'),module.__dict__)
    module.source_bytes=content
    return module


def qualify_phase_evidence(path,report):
    for phase in ['bootstrap','qualification']:
        record=report.get(phase)
        if record==NOT:continue
        fields={'status','exit_code','timed_out','script_error_observed','non_script_error_observed','output_valid','log'}
        if (not isinstance(record,dict) or set(record)!=fields or record['status'] not in {'passed','failed'} or
            any(type(record[name]) is not bool for name in ['timed_out','script_error_observed','non_script_error_observed','output_valid']) or
            (record['exit_code'] is not None and type(record['exit_code']) is not int)):
            raise ValueError('preparation_phase_not_qualified')
        log=path.parent/('prepare-'+phase+'.log')
        if record['log']!=str(log) or log.is_symlink() or not log.is_file() or log.stat().st_size>8192:
            raise ValueError('preparation_log_not_qualified')
        lines=[]
        if record['script_error_observed']:lines.append('SCRIPT ERROR: preparation script error observed')
        if record['non_script_error_observed']:lines.append('ERROR: non-script engine error observed')
        lines.append('PREPARATION: '+json.dumps({key:value for key,value in record.items() if key!='log'},sort_keys=True))
        if log.read_text()!='\n'.join(lines)+'\n':raise ValueError('preparation_log_not_qualified')


def preparation_receipt(path,project,source,logging=False):
    if path.is_symlink() or not path.is_file():raise ValueError('preparation_report_unavailable')
    if path.stat().st_size>1024*1024:raise ValueError('preparation_report_unavailable')
    report=json.loads(path.read_text())
    if (not isinstance(report,dict) or report.get('schema_version')!=1 or
        report.get('source_revision')!=source['revision'] or report.get('prepared_root')!=str(project) or
        report.get('prepared_root_created') is not True or report.get('configuration_restored') is not True or
        report.get('source_custody_qualified') is not True or report.get('configuration_custody_lost') is not False):
        raise ValueError('preparation_receipt_not_qualified')
    qualify_phase_evidence(path,report)
    qualify_staged(project,source,report,logging)
    return report


def qualify_staged(project,source,report,logging):
    contract=preparation_contract(source)
    expected={name:value for name,value in source['source_sha256'].items() if not contract.excluded(Path(name))}
    if (report.get('source_manifest')!=expected or report.get('source_inventory_kind')!='git-tracked' or
        report.get('source_sha256')!=hashlib.sha256(json.dumps(expected,sort_keys=True).encode()).hexdigest() or
        report.get('configuration_original_sha256')!=expected.get('project.godot') or HARNESS not in expected):
        raise ValueError('preparation_source_not_qualified')
    for name,digest in expected.items():
        target=project/name;original=ROOT/name
        if (target.is_symlink() or not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=digest or
            bool(target.stat().st_mode & stat.S_IXUSR)!=bool(original.stat().st_mode & stat.S_IXUSR)):
            raise ValueError('staged_source_changed')
        parent=target.parent
        while parent!=project:
            if parent.is_symlink():raise ValueError('staged_parent_not_qualified')
            parent=parent.parent
    if project.is_symlink():raise ValueError('staged_project_not_qualified')
    registry=project/'.godot/extension_list.cfg'
    if (registry.parent.is_symlink() or registry.is_symlink() or not registry.is_file() or
        registry.read_bytes()!=contract.REGISTRY):raise ValueError('prepared_registry_not_qualified')
    override=project/'override.cfg'
    if logging:
        if override.is_symlink() or not override.is_file() or override.read_text()!=LOGGING_OVERRIDE:
            raise ValueError('logging_override_not_qualified')
    elif override.exists() or override.is_symlink():raise ValueError('unexpected_project_override')
    # Generated import/cache state is permitted only in the helper's declared roots.
    for target in project.rglob('*'):
        name=target.relative_to(project).as_posix()
        if target.is_symlink():raise ValueError('unexpected_staged_symlink')
        if target.is_file() and name not in expected and name!='override.cfg' and target.relative_to(project).parts[0] not in {'.godot','.preparation-runtime'}:
            raise ValueError('unexpected_staged_file')


def minimal_environment(base, sentinel):
    for name in ['home','data','config','cache']:
        (base/name).mkdir()
    return {'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': str(base/'home'),
            'XDG_DATA_HOME': str(base/'data'), 'XDG_CONFIG_HOME': str(base/'config'),
            'XDG_CACHE_HOME': str(base/'cache'), 'LANG': 'C.UTF-8',
            'PROJECT0_SERVER_HOST': '127.0.0.1', 'PROJECT0_SERVER_BIND_ADDRESS': '127.0.0.1',
            'PROJECT0_SERVER_PORT': str(sentinel), 'PROJECT0_OPERATOR_CONTROL_PORT': '0',
            'PROJECT0_CLIENT_LOGIN_SPLIT': '0', 'PROJECT0_CLIENT_HTTPS_LOGIN': '0',
            'PROJECT0_CLIENT_NAKAMA_LOGIN': '0', 'PROJECT0_CLIENT_NAKAMA_GAMEPLAY': '0',
            'PROJECT0_TELEMETRY_DB_PATH': TELEMETRY}


def classify(line, result, allowed):
    # Never return unknown text or any substring extracted from it.
    text = line.decode('utf-8', errors='replace').strip()
    for label in allowed:
        if text == 'PASS: '+label:
            result['passed_assertions'].add(label)
        if text == 'ERROR: FAIL: '+label or text == 'FAIL: '+label:
            result['failed_assertions'].add(label)
    if text == 'ALL PASS':
        result['all_pass'] = True
    if text == 'Telemetry database ready at user://'+TELEMETRY+'.':
        result['telemetry_ready'] = True
    if 'database is locked' in text.lower() or 'database table is locked' in text.lower():
        result['sqlite_lock_observed'] = True
    if any(marker in text for marker in ['SCRIPT ERROR:', 'Parse Error:', 'Compile Error:', 'Failed to load script']):
        result['script_error_observed'] = True


def owned_children():
    # Kernel direct/adopted child list, never inventory unrelated host processes.
    text = Path('/proc/self/task/%d/children' % os.getpid()).read_text().strip()
    return [int(value) for value in text.split()]


def teardown(processes):
    if BASELINE_CHILDREN is None:
        return False
    deadline = time.monotonic()+5
    while time.monotonic()<deadline:
        children = [pid for pid in owned_children() if pid not in BASELINE_CHILDREN]
        if not children:
            return True
        for pid in children:
            try:
                descriptor = os.pidfd_open(pid)
                try:
                    # waitid qualifies parent custody before a PID-bound signal.
                    os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                    signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                finally:
                    os.close(descriptor)
            except ProcessLookupError:
                pass
            except ChildProcessError:
                raise RuntimeError('child_custody_not_qualified')
        while True:
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                break
            if not pid:
                break
        time.sleep(0.02)
    return not [pid for pid in owned_children() if pid not in BASELINE_CHILDREN]


def reset_child_sigchld():
    # Single-threaded coordinator; explicit reset clears inherited autoreap flags.
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)


def observe(commands, envs, allowed, limit):
    processes, records = [], []
    selector = selectors.DefaultSelector()
    deadline = time.monotonic()+limit
    cleaned = False
    try:
        for command, env in zip(commands, envs):
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, start_new_session=True, preexec_fn=reset_child_sigchld)
            processes.append(process)
            os.set_blocking(process.stdout.fileno(), False)
            record = {'passed_assertions': set(), 'failed_assertions': set(), 'all_pass': False,
                      'telemetry_ready': False, 'sqlite_lock_observed': False,
                      'script_error_observed': False, 'exit_code': NOT, 'timed_out': False,
                      'oversized_output_discarded': False}
            records.append(record)
            selector.register(process.stdout, selectors.EVENT_READ, (record, bytearray(), [False]))
        while selector.get_map() and time.monotonic()<deadline:
            for key, _ in selector.select(min(0.1, max(0, deadline-time.monotonic()))):
                record, buffer, discard = key.data
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    if buffer and not discard[0]:
                        classify(bytes(buffer), record, allowed)
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                for byte in chunk:
                    if byte == 10:
                        if not discard[0]: classify(bytes(buffer), record, allowed)
                        buffer.clear(); discard[0] = False
                    elif not discard[0]:
                        if len(buffer)<4096: buffer.append(byte)
                        else:
                            buffer.clear(); discard[0] = True
                            record['oversized_output_discarded'] = True
        for process, record in zip(processes, records):
            code = process.poll()
            if code is None and not selector.get_map():
                try: code = process.wait(timeout=max(0.01, deadline-time.monotonic()))
                except subprocess.TimeoutExpired: pass
            record['exit_code'] = code if code is not None else NOT
            record['timed_out'] = bool(selector.get_map()) or code is None
    finally:
        selector.close()
        cleaned = teardown(processes)
        for process in processes:
            if process.stdout and not process.stdout.closed: process.stdout.close()
        for record in records:
            for name in ['passed_assertions','failed_assertions']:
                record[name] = sorted(record[name])
    if not cleaned:
        raise RuntimeError('owned_descendants_not_removed')
    return records


def retain(path, result):
    result['result_retention'] = 'OBSERVED'
    try:
        with path.open('x') as stream:
            stream.write(json.dumps(result, indent=2)+'\n')
    except (OSError, UnicodeError):
        result.update(status='failed', result_retention=NOT)
        print(json.dumps({'status':'failed','result_retention':NOT}))
        return 1
    print(json.dumps({'status':result['status'],'result_retention':'OBSERVED'}))
    return 0 if result['status']=='observed' else 1


def run(run_id):
    global BASELINE_CHILDREN
    BASELINE_CHILDREN = None
    os.chdir(ROOT)
    result_dir = ROOT/'build/validation/1407-isolation'/run_id
    result_dir.mkdir(parents=True, exist_ok=False)
    result = {'schema_version':1,'issue':1407,'status':'failed','stage':'setup',
              'source_start':NOT,'source_end':NOT,'comparisons':[], 'cleanup_verified':False,
              'initial_child_custody':NOT,'process_cleanup_verified':False,'retained_stage':NOT,
              'acceptance':'diagnostic only; full regression and root cause NOT_OBSERVED'}
    temporary = None
    sentinel = None
    preparation_attempted=False
    logging=False
    report_path=None
    project=None
    try:
        result['stage']='initial_child_custody'
        BASELINE_CHILDREN = set(owned_children())
        result['initial_child_custody']='OBSERVED'
        result['stage']='child_signal_contract'
        if threading.active_count()!=1:
            raise RuntimeError('single_threaded_launch_not_qualified')
        if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
            raise RuntimeError('sigchld_disposition_not_qualified')
        result['sigchld_contract']='default_before_child_execution'
        if not hasattr(os, 'pidfd_open') or not hasattr(os, 'P_PIDFD') or not hasattr(signal, 'pidfd_send_signal'):
            raise RuntimeError('pid_bound_cleanup_not_supported')
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            raise RuntimeError('subreaper_not_observed')
        if BASELINE_CHILDREN: raise RuntimeError('unexpected_existing_children')
        result['stage']='source_start'
        result['source_start']=identity()
        config=(ROOT/'project.godot').read_text()
        if 'config/name="Project0"' not in config or re.search(r'config/(use_custom_user_dir|custom_user_dir_name)\s*=',config):
            raise ValueError('user_directory_not_qualified')
        allowed=assertions()
        if not allowed: raise ValueError('assertions_not_observed')
        result['stage']='preflight'
        preflight=subprocess.run([sys.executable,'scripts/check_validation_ownership.py','--plan',
            '.scratch/1407-isolation/validation-plan.json','--output',str(result_dir/'preflight.json')],
            cwd=ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=15)
        pre=json.loads((result_dir/'preflight.json').read_text())
        if preflight.returncode or not isinstance(pre,dict) or pre.get('passed') is not True or pre.get('errors')!=[] or pre.get('runtime_executed') is not False:
            raise ValueError('preflight_not_qualified')
        temporary=Path(tempfile.mkdtemp(prefix='project0-1407.'))
        project=temporary/'project'
        if (ROOT/'override.cfg').exists() or (ROOT/'override.cfg').is_symlink():raise ValueError('existing_project_override')
        sentinel=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        sentinel.bind(('127.0.0.1',0))
        port=sentinel.getsockname()[1]
        setup=temporary/'metadata';setup.mkdir()
        environment=temporary/'preparation-environment';environment.mkdir()
        env=minimal_environment(environment,port)
        result['stage']='engine_metadata'
        version=subprocess.check_output(['godot','--path',str(setup),'--version'],env=env,cwd=setup,stderr=subprocess.DEVNULL,timeout=10,preexec_fn=reset_child_sigchld).decode().strip()
        if version != '4.3.stable.official.77dcf97d8':raise ValueError('engine_not_qualified')
        result['engine']=version
        result['stage']='preparation'
        report_path=result_dir/'preparation.json'
        contract=preparation_contract(result['source_start'])
        helper_snapshot=temporary/'preparation-helper.py'
        with helper_snapshot.open('xb') as stream:stream.write(contract.source_bytes)
        command=[sys.executable,str(helper_snapshot),'--source-root',str(ROOT),
                 '--prepared-root',str(project),'--godot','godot','--source-revision',result['source_start']['revision'],
                 '--timeout-seconds','120','--report',str(report_path)]
        preparation_attempted=True
        prepared=observe([command],[env],allowed,420)[0]
        receipt=preparation_receipt(report_path,project,result['source_start'])
        result['preparation']={'report':str(report_path),'status':receipt.get('status'),
            'source_sha256':receipt['source_sha256'],'bootstrap':receipt.get('bootstrap'),'qualification':receipt.get('qualification')}
        if (prepared['exit_code']!=0 or prepared['timed_out'] or prepared['script_error_observed'] or
            receipt.get('status')!='passed' or receipt.get('exit_code')!=0):raise ValueError('preparation_not_qualified')
        for phase in ['bootstrap','qualification']:
            observed=receipt.get(phase)
            log=result_dir/('prepare-'+phase+'.log')
            if (not isinstance(observed,dict) or observed.get('status')!='passed' or observed.get('exit_code')!=0 or
                observed.get('timed_out') is not False or observed.get('script_error_observed') is not False or
                observed.get('output_valid') is not True or observed.get('log')!=str(log) or log.is_symlink() or not log.is_file()):
                raise ValueError('preparation_phase_not_qualified')
        with (project/'override.cfg').open('x') as stream:stream.write(LOGGING_OVERRIDE)
        logging=True
        qualify_staged(project,result['source_start'],receipt,True)
        result['staged_source_qualified']=True
        result['engine_file_logging']='disabled_during_preparation_and_before_consumers'
        for mode in ['shared','distinct']:
            result['stage']=mode
            mode_dir=temporary/mode;mode_dir.mkdir()
            envs=[];targets=[]
            for index in range(2):
                child=mode_dir/('child'+str(index));child.mkdir()
                env=minimal_environment(child,port)
                target=mode_dir/('telemetry-shared' if mode=='shared' else 'telemetry-'+str(index))
                target.mkdir(exist_ok=True)
                user=child/'data/godot/app_userdata/Project0';user.mkdir(parents=True)
                link=user/'fixture_telemetry';link.symlink_to(target,target_is_directory=True)
                if not link.resolve().is_relative_to(temporary) or link.resolve()!=target.resolve():
                    raise ValueError('telemetry_target_not_owned')
                envs.append(env);targets.append(target/'telemetry.db')
            relationship='same' if targets[0].resolve()==targets[1].resolve() else 'distinct'
            if relationship!=('same' if mode=='shared' else 'distinct'):raise ValueError('treatment_not_qualified')
            observed=observe([['godot','--headless','--path',str(project),'-s',HARNESS]]*2,envs,allowed,60)
            for record in observed:
                record['public_assertion_verdict']='passed' if record['exit_code']==0 and record['all_pass'] and set(record['passed_assertions'])==allowed and not record['failed_assertions'] and not record['script_error_observed'] and not record['timed_out'] else 'failed'
            qualified=all(record['telemetry_ready'] for record in observed) and all(path.is_file() for path in targets)
            result['comparisons'].append({'mode':mode,'telemetry_path_relationship':relationship if qualified else NOT,
                'telemetry_path_qualified':qualified,'children':observed})
            if not qualified:raise ValueError('telemetry_path_not_observed')
        result['stage']='consumer_custody'
        preparation_receipt(report_path,project,result['source_start'],logging)
        result['stage']='source_end'
        result['source_end']=identity()
        if result['source_start']!=result['source_end']:raise ValueError('source_changed')
        if any(child['timed_out'] for mode in result['comparisons'] for child in mode['children']):
            raise ValueError('child_timeout')
        result['status']='observed'
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError, RuntimeError):
        result['status']='failed'
        result['failure_class']='stage_not_qualified'
    finally:
        empty=False
        custody=True
        try:
            empty=teardown([])
            result['process_cleanup_verified']=empty
        except (OSError, RuntimeError):
            result['process_cleanup_verified']=False
        if preparation_attempted:
            try:
                if identity()!=result['source_start']:raise ValueError('cleanup_source_changed')
                preparation_receipt(report_path,project,result['source_start'],logging)
            except (OSError, ValueError, UnicodeError, RuntimeError, subprocess.SubprocessError):
                custody=False
                result['retained_stage']=str(temporary)
        try:
            if temporary is not None and custody and empty:shutil.rmtree(temporary)
            result['cleanup_verified']=empty and custody and (temporary is None or not temporary.exists())
            if temporary is not None and temporary.exists():result['retained_stage']=str(temporary)
        except OSError:
            result['cleanup_verified']=False
            result['retained_stage']=str(temporary)
        if sentinel is not None:sentinel.close()
        if not result['cleanup_verified']:result['status']='failed'
    return retain(result_dir/'result.json',result)


if __name__=='__main__':
    def interrupted(_signal, _frame):
        raise RuntimeError('coordinator_interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    if len(sys.argv)!=2 or not re.fullmatch('[A-Za-z0-9_-]+',sys.argv[1]):raise SystemExit(2)
    raise SystemExit(run(sys.argv[1]))
