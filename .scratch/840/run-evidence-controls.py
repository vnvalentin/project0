#!/usr/bin/env python3
"""Copied evidence-gate controls; never invoke repository Git or native Godot."""
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
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
SOURCES = (
    'tests/unit/test_construction_contract.gd', 'shared/construction_contract.gd',
    '.scratch/840/run-focused.sh', '.scratch/840/validation-plan.json',
    '.scratch/840/run-evidence-controls.py',
)
HEAD = 'a' * 40
WORKED = 'test_place_request_preserves_pins_and_detaches_client_values'
CANCEL = 'test_cancel_action_is_excluded_from_the_closed_verb_set'
LOCKED_VERBS = 'test_all_locked_verbs_are_accepted'
OBJECT = 'test_nested_object_values_are_rejected'
NESTED_NUMBER = 'test_nested_nonfinite_numbers_are_rejected'
TEXT_VALUE = 'test_request_text_value_size_is_bounded'
TEXT_KEY = 'test_request_dictionary_key_size_is_bounded'
COUNTER = 'test_cross_field_container_alias_is_rejected'
DEPTH = 'test_request_depth_is_bounded'
NODE_COUNT = 'test_request_node_count_is_bounded'
CONTAINER_COUNT = 'test_request_container_count_is_bounded'
ORIENTATION = 'test_orientation_must_be_finite_and_canonical_degrees'
FIXED_CASES = (COUNTER, DEPTH, NODE_COUNT, CONTAINER_COUNT)
FIXED_CASES = (*FIXED_CASES, NESTED_NUMBER, ORIENTATION)
RED_CASES = (TEXT_VALUE, TEXT_KEY)
NAMES = (WORKED, CANCEL, LOCKED_VERBS, OBJECT, *FIXED_CASES, *RED_CASES)
TEST_PATH = SOURCES[0]


def hashes(root):
    return {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in SOURCES}


def run_owned(command, cwd, env):
    child = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = child.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.communicate()
        raise AssertionError('copied control exceeded its bounded lifetime')
    return child.returncode, stdout, stderr


def make_xml(path, failed=(), names=NAMES, suite=TEST_PATH, classname=TEST_PATH):
    top = E.Element('testsuites')
    parent = E.SubElement(top, 'testsuite', name=suite)
    for name in names:
        case = E.SubElement(parent, 'testcase', name=name, classname=classname, status='fail' if name in failed else 'pass', assertions='1')
        if name in failed:
            E.SubElement(case, 'failure', message='fixture assertion')
    E.ElementTree(top).write(path)


def fixture(context):
    root = context / 'project'
    for rel in SOURCES:
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / rel, dst)
    bins = context / 'bin'
    bins.mkdir()
    git = bins / 'git'
    git.write_text('#!' + sys.executable + '\n' + '''
import os,sys,time
from pathlib import Path
args=sys.argv[1:]
kind='revision' if args==['rev-parse','HEAD'] else 'status'
count=Path(os.environ['CONTROL_CONTEXT'])/(kind+'-count')
n=int(count.read_text()) if count.exists() else 0
count.write_text(str(n+1))
mode=os.environ.get('CONTROL_MODE','')
if n==0 and mode==kind+'_failure': raise SystemExit(7)
if n==0 and mode==kind+'_unavailable': raise SystemExit(127)
if n==0 and mode==kind+'_timeout': time.sleep(1)
if kind=='revision': print('a'*40)
''')
    git.chmod(0o755)
    env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'],
               CONTROL_CONTEXT=str(context))
    return root, env


def serializer_control(context, variation):
    root, env = fixture(context)
    out = root / 'build/control'
    out.mkdir(parents=True)
    (out / 'source-start.json').write_text(json.dumps(hashes(root)))
    for name in ('import.log', 'gut.log'):
        (out / name).write_text('fixture phase completed\n')
    failed = RED_CASES
    names = NAMES
    suite = classname = TEST_PATH
    mode, exit_code = 'red', 1
    if variation == 'green': failed, mode, exit_code = (), 'green', 0
    if variation == 'prior-failure': failed = (WORKED,)
    if variation == 'both-fail': failed = (WORKED, COUNTER)
    if variation == 'cancel-only': failed = (CANCEL,)
    if variation == 'object-only': failed = (OBJECT,)
    if variation == 'nested-nonfinite-only': failed = (NESTED_NUMBER,)
    if variation == 'text-value-only': failed = (TEXT_VALUE,)
    if variation == 'text-key-only': failed = (TEXT_KEY,)
    if variation == 'orientation-only': failed = (ORIENTATION,)
    if variation == 'depth-only': failed = (DEPTH,)
    if variation == 'node-count-only': failed = (NODE_COUNT,)
    if variation == 'container-count-only': failed = (CONTAINER_COUNT,)
    if variation == 'counter-pass': failed = ()
    if variation == 'timeout-exit': exit_code = 124
    if variation == 'unsupported-exit': exit_code = 2
    if variation == 'duplicate-case': names = (COUNTER, COUNTER)
    if variation == 'missing-case': names = (COUNTER,)
    if variation == 'unknown-case': names = ('test_unknown', COUNTER)
    if variation == 'wrong-suite': suite = 'other.gd'
    if variation == 'wrong-class': classname = 'other.gd'
    if variation == 'green-failure': mode, exit_code = 'green', 0
    make_xml(out / 'gut.xml', failed, names, suite, classname)
    if variation == 'source-inventory':
        (root / TEST_PATH).write_text('func test_other():\n    pass\n')
        (out / 'source-start.json').write_text(json.dumps(hashes(root)))
    if variation == 'unattributed-failure':
        tree = E.parse(out / 'gut.xml')
        E.SubElement(tree.getroot(), 'failure')
        tree.write(out / 'gut.xml')
    if variation in ('prior-not-run', 'prior-no-assertions'):
        tree = E.parse(out / 'gut.xml')
        case = tree.find('.//testcase')
        case.set('status', 'not run' if variation=='prior-not-run' else 'pass')
        if variation=='prior-no-assertions': case.set('assertions','0')
        tree.write(out / 'gut.xml')
    if variation == 'unexpected-skip':
        tree = E.parse(out / 'gut.xml')
        E.SubElement(tree.find('.//testcase'), 'skipped')
        tree.write(out / 'gut.xml')
    script = (root / SOURCES[2]).read_text().split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
    command = [sys.executable, '-c', script, str(out), variation, HEAD, HEAD,
               '4.3.stable.fixture', 'gut', str(exit_code), 'true', 'true', 'true', mode, 'true']
    code, _, stderr = run_owned(command, root, env)
    report = json.loads((out / 'focused-result.json').read_text())
    accepted = variation in ('red', 'green', 'nested-nonfinite-only')
    assert report['status'] == ('passed' if accepted else 'failed'), (variation, report)
    assert (code == 0) == accepted, (variation, code, stderr)
    assert report['cleanup_verified'] and report['result_retention'] == 'OBSERVED'
    return {'case': variation, 'expected_acceptance': accepted, 'status': 'passed'}


def whole_control(context, variation):
    root, env = fixture(context)
    env['CONTROL_MODE'] = variation
    godot = context / 'fixture-engine'
    godot.write_text('#!' + sys.executable + '\n' + '''
import os,sys,time
from pathlib import Path
if sys.argv[1:]!=['--version']:
    Path(os.environ['CONTROL_CONTEXT'],'unexpected-runtime').write_text('called')
    raise SystemExit(99)
mode=os.environ['CONTROL_MODE']
if mode=='engine_unavailable': raise SystemExit(127)
if mode=='engine_timeout': time.sleep(1)
if mode=='engine_empty': raise SystemExit(0)
if mode=='engine_malformed': print('unknown'); raise SystemExit(0)
print('4.3.stable.fixture')
''')
    godot.chmod(0o755)
    runner = root / SOURCES[2]
    copied = runner.read_text().replace('/usr/local/bin/godot', str(godot))
    copied = copied.replace('10s git', '0.1s git').replace('10s ' + str(godot), '0.1s ' + str(godot))
    sentinel = None
    if variation == 'evidence_collision':
        collision = root / 'build/validation/840/collided'
        collision.mkdir(parents=True)
        sentinel = collision / 'sentinel'
        sentinel.write_text('preserve existing evidence')
        copied = copied.replace('out="$PWD/build/validation/840/$run_id"',
                                'out="$PWD/build/validation/840/collided"')
    runner.write_text(copied)
    checker = root / 'scripts/check_validation_ownership.py'
    checker.parent.mkdir()
    checker.write_text('import sys\nfrom pathlib import Path\nPath(sys.argv[sys.argv.index("--output")+1]).write_text("{}")\n')
    code, stdout, stderr = run_owned(['bash', str(runner), 'copied-control', HEAD, 'red'], root, env)
    if variation == 'evidence_collision':
        report = json.loads(stdout.strip().splitlines()[-1])
        assert code != 0 and report['status'] == 'failed', (variation, code, report, stderr)
        assert report['result_retention'] == 'NOT_OBSERVED'
        assert 'evidence_directory_not_reserved' in report['errors']
        assert sentinel.read_text() == 'preserve existing evidence'
        assert not (context / 'unexpected-runtime').exists()
        return {'case': variation, 'expected_acceptance': False, 'status': 'passed'}
    reports = list((root / 'build/validation/840').glob('*/focused-result.json'))
    assert len(reports) == 1, (variation, code, stderr)
    report = json.loads(reports[0].read_text())
    assert code != 0 and report['status'] == 'failed', (variation, report)
    assert report['cleanup_verified'] and report['result_retention'] == 'OBSERVED'
    assert report['stage'] == ('source_guard' if variation.startswith('status_') else 'engine_identity')
    assert report['native_exit_code'] == -1 and not (context / 'unexpected-runtime').exists()
    if variation.startswith('status_'): assert not report['source_clean_start']
    return {'case': variation, 'expected_acceptance': False, 'status': 'passed'}


def main():
    try:
        before = hashes(ROOT)
    except Exception as exc:
        print(json.dumps({'status': 'failed', 'result_retention': 'NOT_OBSERVED',
                          'error': f'source identity capture failed: {exc}'}))
        return 1
    out = ROOT / 'build/validation/840' / ('evidence-controls-' + uuid.uuid4().hex[:12])
    try:
        out.mkdir(parents=True, exist_ok=False)
    except OSError as exc:
        print(json.dumps({'status': 'failed', 'result_retention': 'NOT_OBSERVED',
                          'error': f'evidence directory setup failed: {exc}'}))
        return 1
    cases = []
    failures = []
    contexts_removed = True
    serializers = ('red', 'green', 'prior-failure', 'both-fail', 'cancel-only', 'object-only',
                   'depth-only', 'node-count-only', 'container-count-only', 'orientation-only',
                   'nested-nonfinite-only', 'text-value-only', 'text-key-only', 'counter-pass',
                   'timeout-exit', 'unsupported-exit', 'duplicate-case', 'missing-case',
                   'unknown-case', 'wrong-suite', 'wrong-class', 'green-failure',
                   'source-inventory', 'unattributed-failure', 'unexpected-skip',
                   'prior-not-run', 'prior-no-assertions')
    whole = ('status_failure', 'status_unavailable', 'status_timeout',
             'engine_unavailable', 'engine_timeout', 'engine_empty', 'engine_malformed')
    for variation, operation in [(c, serializer_control) for c in serializers] + [(c, whole_control) for c in whole + ('evidence_collision',)]:
        context = None
        try:
            context = Path(tempfile.mkdtemp(prefix='project0-840-copied-evidence-'))
            cases.append(operation(context, variation))
        except Exception as exc:
            failures.append({'case': variation, 'error': str(exc)})
        finally:
            if context is not None:
                try:
                    shutil.rmtree(context)
                    if context.exists():
                        raise OSError('temporary context still exists after cleanup')
                except Exception as exc:
                    contexts_removed = False
                    failures.append({'case': variation, 'cleanup_error': str(exc)})
    try:
        preserved = before == hashes(ROOT)
    except Exception as exc:
        preserved = False
        failures.append({'case': 'source-integrity', 'error': str(exc)})
    report = {'status': 'passed' if not failures and preserved and contexts_removed else 'failed',
              'cases': cases, 'failures': failures, 'actual_source_preserved': preserved,
              'copied_contexts_removed': contexts_removed, 'native_runtime_executed': False,
              'actual_git_mutated': False}
    serialized = json.dumps(report, indent=2) + '\n'
    print(serialized, end='')
    try:
        (out / 'control-result.json').write_text(serialized)
    except OSError as exc:
        print(json.dumps({'status': 'failed', 'result_retention': 'NOT_OBSERVED',
                          'error': f'control result retention failed: {exc}'}))
        return 1
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
