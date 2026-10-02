#!/usr/bin/env python3
"""Private supporting fixture comparison; raw child output is never persisted."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HARNESS = 'scripts/test_prediction_reconciliation.gd'
TELEMETRY = 'fixture_telemetry/telemetry.db'
LOGGING_OVERRIDE = '[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n'
NOT = 'NOT_OBSERVED'
BASELINE_CHILDREN = set()


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



def qualify_staged(project, source):
    for name, expected in source['source_sha256'].items():
        target = project/name
        if target.is_symlink() or hashlib.sha256(target.read_bytes()).hexdigest()!=expected:
            raise ValueError('staged_source_changed')
    if (project/'override.cfg').read_text()!=LOGGING_OVERRIDE:
        raise ValueError('logging_override_not_qualified')
    files={p.relative_to(project).as_posix() for p in project.rglob('*') if p.is_file()}
    if files!=set(source['source_sha256'])|{'override.cfg'}:
        raise ValueError('unexpected_staged_file')


def stage_project(temporary, source):
    names=source['source_sha256']
    if 'override.cfg' in names or (ROOT/'override.cfg').exists():
        raise ValueError('existing_project_override')
    project=temporary/'project';project.mkdir()
    for name, expected in names.items():
        path=Path(name)
        if path.is_absolute() or '..' in path.parts or any(part in {'.git','build','logs','.aws','.codex'} for part in path.parts):
            raise ValueError('private_or_unsafe_staging_path')
        original=ROOT/path
        if original.is_symlink() or not original.is_file():raise ValueError('unsafe_staging_source')
        content=original.read_bytes()
        if hashlib.sha256(content).hexdigest()!=expected:raise ValueError('staging_source_changed')
        target=project/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
    (project/'override.cfg').write_text(LOGGING_OVERRIDE)
    qualify_staged(project,source)
    return project


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


def observe(commands, envs, allowed, limit):
    processes, records = [], []
    selector = selectors.DefaultSelector()
    deadline = time.monotonic()+limit
    cleaned = False
    try:
        for command, env in zip(commands, envs):
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, start_new_session=True)
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
    BASELINE_CHILDREN = set(owned_children())
    os.chdir(ROOT)
    result_dir = ROOT/'build/validation/1407-isolation'/run_id
    result_dir.mkdir(parents=True, exist_ok=False)
    result = {'schema_version':1,'issue':1407,'status':'failed','stage':'setup',
              'source_start':NOT,'source_end':NOT,'comparisons':[], 'cleanup_verified':False,
              'acceptance':'diagnostic only; full regression and root cause NOT_OBSERVED'}
    temporary = None
    sentinel = None
    try:
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
        result['stage']='safe_staging'
        project=stage_project(temporary,result['source_start'])
        result['staged_source_qualified']=True
        result['engine_file_logging']='disabled_before_launch'
        sentinel=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        sentinel.bind(('127.0.0.1',0))
        port=sentinel.getsockname()[1]
        setup=temporary/'import';setup.mkdir()
        env=minimal_environment(setup,port)
        result['stage']='engine_metadata'
        version=subprocess.check_output(['godot','--path',str(project),'--version'],env=env,cwd=ROOT,stderr=subprocess.DEVNULL,timeout=10).decode().strip()
        if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?\.[A-Za-z0-9.]+',version):
            raise ValueError('engine_not_qualified')
        result['engine']=version
        result['stage']='import'
        imported=observe([['godot','--headless','--editor','--path',str(project),'--import','--quit']],[env],allowed,120)[0]
        if imported['exit_code']!=0 or imported['timed_out'] or imported['script_error_observed']:
            raise ValueError('import_not_qualified')
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
        try:
            empty=teardown([])
            if temporary is not None:shutil.rmtree(temporary)
            result['cleanup_verified']=empty and (temporary is None or not temporary.exists())
        except (OSError, RuntimeError):
            result['cleanup_verified']=False
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
