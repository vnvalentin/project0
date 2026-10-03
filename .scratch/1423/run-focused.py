#!/usr/bin/env python3
"""Owned pure-query focus. Requires coordinator review/window before execution."""
import argparse
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import tempfile
import threading
import time
import types
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
LIFECYCLE = Path('/data/code/project0-m3-1396-bootstrap-20261002/build/validation/1396-bootstrap/run-helper-qualification.py')
LIFECYCLE_SHA = '448d77e2793693fdbd2cf74477aa5e1c2d3203473bedb0d0fb54fcdacee4c03c'
HELPER_SHA = '13434bab2d8e45138268b691723df3fbd8314f2d9c944dd657df7173c44ab6b9'
TEST = 'tests/unit/test_lan_config.gd'
PREFIX = 'test_defaults_to_localhost_with_no_override'
LOGGING = '[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n'
NOT = 'NOT_OBSERVED'


def pinned_module(path, digest, name):
    for parent in path.parents:
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError('module_parent_unqualified')
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('module_file_unqualified')
    content = path.read_bytes()
    if hashlib.sha256(content).hexdigest() != digest:
        raise ValueError('module_identity_changed')
    module = types.ModuleType(name)
    module.__file__ = str(path)
    exec(compile(content, str(path), 'exec'), module.__dict__)
    return module, content


def gut_observation(lifecycle, command, environment):
    """Discard unknown output; retain direct identities until unified teardown."""
    result = {'exit_code': NOT, 'timed_out': False, 'output_valid': True,
              'script_error_observed': False, 'non_script_error_observed': False}
    pending = bytearray()
    discard = False
    total = 0
    selector = selectors.DefaultSelector()

    def classify(raw):
        try:
            line = raw.decode('utf-8')
        except UnicodeError:
            result['output_valid'] = False
            return
        if '\x00' in line:
            result['output_valid'] = False
        if any(marker in line for marker in ('SCRIPT ERROR', 'Parse Error', 'Compile Error', 'Failed to load script')):
            result['script_error_observed'] = True
        elif 'ERROR:' in line:
            result['non_script_error_observed'] = True

    process = subprocess.Popen(command, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               preexec_fn=lifecycle.child_limits)
    lifecycle.RETAINED.append(process)
    descriptor = os.pidfd_open(process.pid)
    lifecycle.DIRECT_PIDFDS.append(descriptor)
    os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    try:
        os.set_blocking(process.stdout.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = min(time.monotonic() + 30, lifecycle.DEADLINE - 10)
        ended = None
        while time.monotonic() < deadline:
            ended = os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if ended is not None and not selector.get_map():
                break
            for key, _ in selector.select(0.05):
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    if pending and not discard:
                        classify(bytes(pending))
                    selector.unregister(key.fileobj)
                    continue
                total += len(chunk)
                if total > 16 * 1024 * 1024:
                    result['output_valid'] = False
                for byte in chunk:
                    if byte == 10:
                        if not discard:
                            classify(bytes(pending))
                        pending.clear()
                        discard = False
                    elif not discard:
                        if len(pending) < 4096:
                            pending.append(byte)
                        else:
                            pending.clear()
                            discard = True
                            result['output_valid'] = False
        if ended is not None and not selector.get_map():
            result['exit_code'] = ended.si_status if ended.si_code == os.CLD_EXITED else -ended.si_status
        else:
            result['timed_out'] = True
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
    finally:
        selector.close()
        process.stdout.close()
    return result


def receipt(contract, path, project, revision, hashes, original):
    contract.checked_file(path.parent, Path(path.name), 'receipt_unqualified')
    if path.stat().st_size > 2 * 1024 * 1024:
        raise ValueError('receipt_oversized')
    value = json.loads(path.read_bytes())
    if (not isinstance(value, dict) or value.get('schema_version') != 1 or
        value.get('source_revision') != revision or value.get('prepared_root') != str(project) or
        value.get('prepared_root_created') is not True or value.get('configuration_restored') is not True or
        value.get('source_custody_qualified') is not True or value.get('configuration_custody_lost') is not False or
        value.get('source_manifest') != hashes or value.get('configuration_original_sha256') != hashlib.sha256(original).hexdigest() or
        value.get('source_inventory_kind') != 'git-tracked' or value.get('source_sha256') != hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()):
        raise ValueError('receipt_identity_unqualified')
    for name in ('bootstrap', 'qualification'):
        phase = value.get(name)
        if (not isinstance(phase, dict) or phase.get('status') != 'passed' or phase.get('exit_code') != 0 or
            phase.get('timed_out') is not False or phase.get('script_error_observed') is not False or
            phase.get('output_valid') is not True or type(phase.get('non_script_error_observed')) is not bool):
            raise ValueError('preparation_phase_unqualified')
        log = path.parent / ('prepare-' + name + '.log')
        contract.checked_file(log.parent, Path(log.name), 'phase_log_unqualified')
        lines = ['ERROR: non-script engine error observed'] if phase['non_script_error_observed'] else []
        lines.append('PREPARATION: ' + json.dumps({k:v for k,v in phase.items() if k != 'log'}, sort_keys=True))
        if phase.get('log') != str(log) or log.stat().st_size > 8192 or log.read_text() != '\n'.join(lines) + '\n':
            raise ValueError('phase_log_unqualified')
    if value.get('status') != 'passed' or value.get('exit_code') != 0:
        raise ValueError('preparation_failed')
    contract.verify_copy(project, hashes, original)
    return value


def staged_custody(contract, project, hashes, original, logging):
    override = project / 'override.cfg'
    if logging:
        contract.checked_file(project, Path('override.cfg'), 'override_unqualified')
        if override.read_text() != LOGGING:
            raise ValueError('override_changed')
        # verify_copy requires no override; equivalent selected-byte/registry
        # checks are performed without removing or replacing any file.
        for name, digest in hashes.items():
            p = contract.checked_file(project, Path(name), 'prepared_source_unqualified')
            if hashlib.sha256(p.read_bytes()).hexdigest() != digest:
                raise ValueError('prepared_source_changed')
        contract.check_registry(project)
        registry = contract.checked_file(project, Path('.godot/extension_list.cfg'), 'registry_unavailable')
        if registry.read_bytes() != contract.REGISTRY:
            raise ValueError('registry_changed')
    else:
        contract.verify_copy(project, hashes, original)


def reduced_xml(contract, raw, destination, expected, mode):
    contract.checked_file(raw.parent, Path(raw.name), 'xml_unavailable')
    if not 0 < raw.stat().st_size <= 1024 * 1024:
        raise ValueError('xml_size_unqualified')
    tree = ET.fromstring(raw.read_bytes())
    suites = list(tree.iter('testsuite'))
    if tree.tag != 'testsuites' or len(suites) != 1 or suites[0].get('name') != TEST:
        raise ValueError('selected_suite_unqualified')
    cases = list(tree.iter('testcase'))
    names = [case.get('name') for case in cases]
    if len(names) != len(expected) or set(names) != set(expected) or len(set(names)) != len(names):
        raise ValueError('selected_cases_unqualified')
    if int(suites[0].get('tests', '-1')) != len(cases):
        raise ValueError('selected_count_unqualified')
    for case in cases:
        failures_in_case = len(case.findall('failure'))
        if (case.get('classname') != TEST or int(case.get('assertions', '0')) < 1 or
            case.get('status') not in {'pass','fail'} or failures_in_case > 1 or
            (case.get('status') == 'fail') != bool(failures_in_case)):
            raise ValueError('selected_case_verdict_unqualified')
    failures = sum(len(case.findall('failure')) for case in cases)
    errors = sum(len(case.findall('error')) for case in cases)
    skipped = sum(len(case.findall('skipped')) for case in cases)
    counts = {'tests': len(cases), 'failures': failures, 'errors': errors, 'skipped': skipped}
    root = ET.Element('testsuites')
    suite = ET.SubElement(root, 'testsuite', name=TEST, **{k:str(v) for k,v in counts.items()})
    for case in cases:
        item = ET.SubElement(suite, 'testcase', name=case.get('name'))
        for category in ('failure', 'error', 'skipped'):
            for _ in case.findall(category):
                ET.SubElement(item, category)
    payload = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    with destination.open('xb') as stream:
        stream.write(payload)
    if destination.read_bytes() != payload:
        raise ValueError('xml_retention_unqualified')
    counts['expected_verdict'] = errors == 0 and skipped == 0 and failures == (1 if mode == 'red' else 0)
    return counts


def run(args, lifecycle):
    lifecycle.ROOT = ROOT
    lifecycle.DEADLINE = time.monotonic() + 150
    destination = ROOT / 'build/validation/1423' / args.run_id
    destination.mkdir(parents=True, exist_ok=False, mode=0o700)
    result = {'schema_version':1, 'issue':1423, 'status':'failed', 'stage':'setup',
              'source_revision':args.source_revision, 'mode':args.mode, 'source_start':False, 'source_end':False,
              'lifecycle_sha256':LIFECYCLE_SHA, 'helper_sha256':HELPER_SHA,
              'engine':NOT, 'preparation':NOT, 'gut':NOT, 'junit':NOT, 'process_cleanup_verified':False,
              'temporary_cleanup_verified':False, 'retained_stage':NOT,
              'acceptance':'focused pure-query evidence only; full delivery NOT_OBSERVED'}
    temporary = project = contract = None
    hashes = committed = original = None
    attempted = logging = False
    try:
        if threading.active_count() != 1 or threading.current_thread() is not threading.main_thread():
            raise ValueError('single_thread_required')
        signal.signal(signal.SIGCHLD, signal.SIG_DFL)
        lifecycle.BASELINE = lifecycle.children()
        if lifecycle.BASELINE or ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            raise ValueError('child_custody_unavailable')
        if not lifecycle.source_qualified(args.source_revision) or lifecycle.git('status', '--porcelain'):
            raise ValueError('source_not_clean')
        result['source_start'] = True
        contract, helper_bytes = pinned_module(ROOT/'scripts/prepare_godot_project.py', HELPER_SHA, 'selected_preparation')
        temporary = Path(tempfile.mkdtemp(prefix='project0-1423.'))
        if temporary.is_symlink() or temporary.stat().st_uid != os.getuid():
            raise ValueError('temporary_not_owned')
        project = temporary/'project'
        selected, committed = contract.source_inventory(ROOT, args.source_revision, project)
        hashes = {str(p):hashlib.sha256(contract.checked_file(ROOT,p,'source_unqualified').read_bytes()).hexdigest() for p in selected}
        original = (ROOT/'project.godot').read_bytes()
        names = re.findall(r'^func (' + re.escape(PREFIX) + r'\w*)\(', (ROOT/TEST).read_text(), re.M)
        if len(names) != (1 if args.mode == 'red' else 4) or len(set(names)) != len(names):
            raise ValueError('pure_selection_unqualified')
        result['selected_cases'] = names
        result['source_manifest_sha256'] = hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest()
        result['stage'] = 'preflight'
        preflight = destination/'preflight.json'
        code = subprocess.run(['/usr/bin/python3','scripts/check_validation_ownership.py','--plan','.scratch/1423/validation-plan.json','--output',str(preflight)], cwd=ROOT, env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8'}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15).returncode
        pre = json.loads(preflight.read_bytes())
        if code or pre.get('passed') is not True or pre.get('errors') != [] or pre.get('runtime_executed') is not False:
            raise ValueError('preflight_unqualified')
        env = lifecycle.environment(temporary)
        env['PATH'] = '/usr/local/bin:/usr/bin:/bin'
        env['M4_SOURCE_REVISION'] = args.source_revision
        engine = shutil.which('godot',path=env['PATH'])
        if not engine:
            raise ValueError('engine_unavailable')
        metadata = temporary/'metadata'; metadata.mkdir()
        result['stage'] = 'engine'
        lifecycle.ROOT = metadata
        try:
            version = lifecycle.observe([engine,'--version'],env,5,version=True)
        finally:
            lifecycle.ROOT = ROOT
        result['engine'] = version
        if version['exit_code'] != 0 or version['timed_out'] or not version['output_qualified'] or not version['engine_identity_observed']:
            raise ValueError('engine_unqualified')
        snapshot = temporary/'prepare.py'; snapshot.write_bytes(helper_bytes)
        result['stage'] = 'preparation'; attempted = True
        report = destination/'prepare.json'
        observed = lifecycle.observe(['/usr/bin/python3',str(snapshot),'--source-root',str(ROOT),'--prepared-root',str(project),'--godot',engine,'--source-revision',args.source_revision,'--timeout-seconds','40','--report',str(report)],env,100)
        if observed['exit_code'] != 0 or observed['timed_out'] or not observed['output_qualified'] or observed['script_error_observed']:
            raise ValueError('preparation_execution_failed')
        proof = receipt(contract,report,project,args.source_revision,hashes,original)
        result['preparation'] = {'passed':True,'bootstrap':proof['bootstrap'],'qualification':proof['qualification'],'helper_sha256':HELPER_SHA}
        for name in hashes:
            if bool((project/name).stat().st_mode & stat.S_IXUSR) != (committed[Path(name)][0]=='100755'):
                raise ValueError('copy_mode_changed')
        with (project/'override.cfg').open('x') as stream:
            stream.write(LOGGING)
        logging = True
        staged_custody(contract,project,hashes,original,logging)
        env.update(PROJECT0_SERVER_BIND_ADDRESS='127.0.0.1',PROJECT0_SERVER_HOST='127.0.0.1',PROJECT0_SERVER_PORT='19997',PROJECT0_CLIENT_LOGIN_SPLIT='0',PROJECT0_CLIENT_HTTPS_LOGIN='0',PROJECT0_CLIENT_NAKAMA_LOGIN='0',PROJECT0_CLIENT_NAKAMA_GAMEPLAY='0')
        raw = temporary/'gut.xml'
        command = [engine,'--headless','--path',str(project),'-s','addons/gut/gut_cmdln.gd','-gconfig=','-gtest=res://'+TEST,'-gunit_test_name='+PREFIX,'-gdisable_colors','-gexit','-gjunit_xml_file='+str(raw)]
        result['command'] = command
        result['stage'] = 'gut'
        result['gut'] = gut_observation(lifecycle,command,env)
        result['junit'] = reduced_xml(contract,raw,destination/'gut.xml',names,args.mode)
        observation = result['gut']
        expected_exit = observation['exit_code'] != 0 if args.mode == 'red' else observation['exit_code'] == 0
        if (type(observation['exit_code']) is not int or not expected_exit or observation['timed_out'] or
            observation['script_error_observed'] or not observation['output_valid'] or not result['junit']['expected_verdict']):
            raise ValueError('focused_verdict_failed')
        result['status'] = 'passed'
    except (OSError,ValueError,UnicodeError,RuntimeError,subprocess.SubprocessError,ET.ParseError):
        result['status'] = 'failed'
        result['failure_class'] = 'stage_not_qualified'
    finally:
        try:
            result['process_cleanup_verified'] = lifecycle.cleanup_children()
        except (OSError,ValueError,RuntimeError):
            result['process_cleanup_verified'] = False
        for process in lifecycle.RETAINED:
            process.returncode = -1
        for descriptor in lifecycle.DIRECT_PIDFDS:
            os.close(descriptor)
        custody = False
        try:
            if contract is not None and hashes is not None:
                contract.verify_source(ROOT,args.source_revision,hashes,committed)
                result['source_end'] = lifecycle.source_qualified(args.source_revision) and not lifecycle.git('status','--porcelain')
            if attempted:
                staged_custody(contract,project,hashes,original,logging)
                for name in hashes:
                    if bool((project/name).stat().st_mode & stat.S_IXUSR) != (committed[Path(name)][0]=='100755'):
                        raise ValueError('copy_mode_changed')
                if logging:
                    (project/'override.cfg').unlink()
                contract.verify_copy(project,hashes,original)
            custody = result['source_end']
        except (OSError,ValueError,UnicodeError,RuntimeError,subprocess.SubprocessError):
            custody = False
        if temporary is None:
            result['temporary_cleanup_verified'] = True
        elif custody and result['process_cleanup_verified']:
            try:
                shutil.rmtree(temporary)
                result['temporary_cleanup_verified'] = not temporary.exists()
            except OSError:
                pass
        if temporary is not None and temporary.exists():
            result['retained_stage'] = str(temporary)
        if not result['process_cleanup_verified'] or not result['temporary_cleanup_verified'] or not result['source_end']:
            result['status'] = 'failed'
        try:
            with (destination/'result.json').open('x') as stream:
                stream.write(json.dumps(result,indent=2)+'\n')
        except OSError:
            print(json.dumps({'status':'failed','result_retention':NOT}))
            return 1
    print(json.dumps({'status':result['status'],'artifact':str(destination/'result.json')}))
    return 0 if result['status']=='passed' else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-revision',required=True)
    parser.add_argument('--run-id',required=True)
    parser.add_argument('--mode',choices=['red','green'],required=True)
    args = parser.parse_args()
    if not re.fullmatch('[0-9a-f]{40}',args.source_revision) or not re.fullmatch('[A-Za-z0-9_-]+',args.run_id):
        parser.error('exact revision and new simple run id required')
    try:
        lifecycle,_ = pinned_module(LIFECYCLE,LIFECYCLE_SHA,'owned_lifecycle')
    except (OSError,ValueError,UnicodeError,SyntaxError):
        # Prerequisite absence/drift must retain a fixed failure record without
        # importing unqualified code or launching any child/native command.
        destination = ROOT/'build/validation/1423'/args.run_id
        try:
            for parent in destination.parent.parents:
                if not stat.S_ISDIR(parent.lstat().st_mode):
                    raise ValueError('result_parent_unqualified')
            if destination.parent.exists() and not stat.S_ISDIR(destination.parent.lstat().st_mode):
                raise ValueError('result_parent_unqualified')
            destination.mkdir(parents=True,exist_ok=False,mode=0o700)
            record = {'schema_version':1,'issue':1423,'status':'failed','stage':'lifecycle_prerequisite',
                      'source_revision':args.source_revision,'mode':args.mode,
                      'failure_class':'pinned_lifecycle_unavailable','native_execution':NOT,
                      'temporary_cleanup_verified':True,'owned_processes_started':False,
                      'process_cleanup_verified':NOT}
            with (destination/'result.json').open('x') as stream:
                stream.write(json.dumps(record,indent=2)+'\n')
            print(json.dumps({'status':'failed','artifact':str(destination/'result.json')}))
        except (OSError,ValueError):
            print(json.dumps({'status':'failed','result_retention':NOT}))
        raise SystemExit(1)
    def interrupted(_signal,_frame):
        raise RuntimeError('focused_interrupted')
    signal.signal(signal.SIGTERM,interrupted)
    signal.signal(signal.SIGINT,interrupted)
    with lifecycle.LOCK.open('a') as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('native_window_unavailable')
        raise SystemExit(run(args,lifecycle))
