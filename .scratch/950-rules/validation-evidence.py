#!/usr/bin/env python3
"""Owned creation-rule validation evidence. Detailed results remain local."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

TEST = 'tests/unit/test_item_creation_profile.gd'
PROFILE = 'server/item_creation_profile.gd'
SOURCES = [PROFILE, TEST, 'tests/fixtures/item_creation_profile.gd',
           '.scratch/950-rules/run-focused.sh', '.scratch/950-rules/validation-plan.json',
           '.scratch/950-rules/validation-evidence.py']
MARKERS = r'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script'


def read_object(path, errors, name):
    try:
        if path.is_symlink():
            raise OSError('unexpected_evidence_symlink')
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError('object_required')
        return value
    except (OSError, ValueError, UnicodeError):
        errors.append(name + '_not_observed')
        return {}


def source_identity(mode, binding):
    errors = []
    def git(arguments, name):
        try:
            value = subprocess.check_output(['git', *arguments], text=True,
                stderr=subprocess.DEVNULL, timeout=10).strip()
            if arguments[0] == 'rev-parse' and not re.fullmatch(r'[0-9a-f]{40}', value):
                raise ValueError('invalid_revision')
            return value
        except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
            errors.append(name + '_not_observed')
            return 'NOT_OBSERVED'
    revision = git(['rev-parse', 'HEAD'], 'revision')
    status = git(['status', '--porcelain'], 'source_status')
    clean = 'NOT_OBSERVED' if status == 'NOT_OBSERVED' else not status
    if binding == 'delivery' and clean is not True:
        errors.append('delivery_source_not_clean')
    hashes = {}
    for name in SOURCES:
        try:
            hashes[name] = hashlib.sha256(Path(name).read_bytes()).hexdigest()
        except FileNotFoundError:
            if name == PROFILE and mode == 'red' and binding == 'prepared':
                hashes[name] = 'ABSENT_EXPECTED_RED'
            else:
                hashes[name] = 'NOT_OBSERVED'
                errors.append('source_not_observed:' + name)
        except OSError:
            hashes[name] = 'NOT_OBSERVED'
            errors.append('source_not_observed:' + name)
    try:
        cases = re.findall(r'^func (test_\w+)\(', Path(TEST).read_text(), re.M)
        if not cases or len(cases) != len(set(cases)):
            raise ValueError('invalid_public_cases')
    except (OSError, ValueError, UnicodeError):
        cases = []
        errors.append('public_cases_not_observed')
    return {'revision': revision, 'source_status': status, 'source_clean': clean,
            'source_sha256': hashes, 'public_cases': cases, 'errors': errors}


def retain(path, record):
    record['result_retention'] = 'OBSERVED'
    try:
        if path.is_symlink() or path.exists():
            raise OSError('unexpected_result_target')
        with path.open('x') as stream:
            stream.write(json.dumps(record, indent=2) + '\n')
    except (OSError, UnicodeError):
        record['status'] = 'failed'
        record['result_retention'] = 'NOT_OBSERVED'
        record['evidence_exit_code'] = 1
        record['validation_errors'].append('result_retention_not_observed')
        print(json.dumps(record))
        return 1
    print(json.dumps({'status': record['status'], 'stage': record['stage'],
                      'evidence_exit_code': record['evidence_exit_code']}))
    return record['evidence_exit_code']


def start(directory, mode, binding, expected):
    source = source_identity(mode, binding)
    if len(source['public_cases']) != expected:
        source['errors'].append('expected_public_cases_mismatch')
    plan = read_object(Path('.scratch/950-rules/validation-plan.json'), source['errors'], 'validation_plan')
    steps = plan.get('steps')
    if not isinstance(steps, list) or len(steps) != 1 or not isinstance(steps[0], dict) or steps[0].get('tests') != [TEST]:
        source['errors'].append('validation_plan_mismatch')
    record = {'schema_version': 1, 'issue': 950, 'mode': mode, 'source_binding': binding,
              'expected_tests': expected, 'source': source, 'status': 'failed' if source['errors'] else 'passed'}
    try:
        with (directory / 'source-start.json').open('x') as stream:
            stream.write(json.dumps(record, indent=2) + '\n')
    except OSError:
        return 1
    return 1 if source['errors'] else 0


def log_errors(path, errors):
    try:
        if path.is_symlink():
            raise OSError('unexpected_log_symlink')
        if re.search(MARKERS, path.read_text(errors='replace')):
            errors.append('script_error:' + path.name)
    except OSError:
        errors.append('log_not_observed:' + path.name)


def finish(directory, mode, binding, expected, stage, runner_exit, cleanup_exit,
           import_exit, suite_exit, engine):
    errors = []
    initial = read_object(directory / 'source-start.json', errors, 'source_start')
    source = initial.get('source')
    qualified = (type(initial.get('schema_version')) is int and initial.get('schema_version') == 1
        and type(initial.get('issue')) is int and initial.get('issue') == 950
        and initial.get('mode') == mode and initial.get('source_binding') == binding
        and type(initial.get('expected_tests')) is int and initial.get('expected_tests') == expected
        and initial.get('status') == 'passed' and isinstance(source, dict)
        and set(source) == {'revision','source_status','source_clean','source_sha256','public_cases','errors'}
        and isinstance(source.get('revision'), str) and re.fullmatch(r'[0-9a-f]{40}', source['revision']) is not None
        and isinstance(source.get('source_status'), str) and type(source.get('source_clean')) is bool
        and source['source_clean'] == (not source['source_status'])
        and isinstance(source.get('source_sha256'), dict) and set(source['source_sha256']) == set(SOURCES)
        and isinstance(source.get('public_cases'), list) and len(source['public_cases']) == expected
        and all(isinstance(case, str) for case in source['public_cases']) and source.get('errors') == [])
    if not qualified:
        errors.append('source_start_not_qualified')
    end = source_identity(mode, binding)
    errors.extend(end['errors'])
    if not qualified or source != end:
        errors.append('source_changed_or_unavailable')
    preflight = read_object(directory / 'preflight.json', errors, 'preflight')
    if preflight.get('passed') is not True or preflight.get('errors') != []:
        errors.append('preflight_not_passed')
    log_errors(directory / 'import.log', errors)
    log_errors(directory / 'gut.log', errors)
    if import_exit != '0':
        errors.append('import_not_passed')
    if engine == 'NOT_OBSERVED' or not engine.strip():
        errors.append('engine_not_observed')
    suites = []
    cases = []
    totals = {key: 'NOT_OBSERVED' for key in ['tests','failures','errors','skipped']}
    try:
        document = ET.parse(directory / 'gut.xml').getroot()
        suites = list(document.iter('testsuite'))
        if len(suites) != 1 or suites[0].get('name') != TEST:
            raise ValueError('unexpected_suite')
        for key in totals:
            # Installed GUT omits errors; only that optional count may default.
            text = suites[0].get(key, '0') if key == 'errors' else suites[0].get(key)
            if not isinstance(text, str) or not re.fullmatch(r'[0-9]+', text):
                raise ValueError('invalid_counts')
            totals[key] = int(text)
        cases = suites[0].findall('testcase')
        names = [case.get('name') for case in cases]
        if not qualified or len(cases) != expected or len(names) != len(set(names)) or set(names) != set(source['public_cases']) or totals['tests'] != expected:
            errors.append('invalid_coverage')
        root_errors = document.get('errors', '0')
        if not re.fullmatch(r'[0-9]+', root_errors):
            raise ValueError('invalid_root_errors')
        if totals['errors'] != 0 or int(root_errors) != 0 or totals['skipped'] != 0 or document.find('.//error') is not None or any(case.find('skipped') is not None for case in cases):
            errors.append('error_or_skip_observed')
        failed = [case.get('name') for case in cases if case.find('failure') is not None]
        if mode == 'red' and (totals['failures'] < 1 or not qualified or failed != [source['public_cases'][-1]] or suite_exit != '1'):
            errors.append('expected_red_missing')
        if mode == 'green' and (totals['failures'] != 0 or failed or suite_exit != '0'):
            errors.append('green_failed')
    except (OSError, ET.ParseError, ValueError, TypeError):
        errors.append('junit_not_qualified')
    try:
        removed = not (directory / 'user-data').exists()
    except OSError:
        removed = 'NOT_OBSERVED'
    if cleanup_exit != 0 or removed is not True:
        errors.append('cleanup_not_verified')
    if runner_exit != 0:
        errors.append('runner_failed')
    result = {'schema_version': 1, 'issue': 950, 'mode': mode, 'source_binding': binding,
        'status': 'failed' if errors else 'expected_red' if mode == 'red' else 'passed',
        'stage': stage, 'revision': source.get('revision', 'NOT_OBSERVED') if isinstance(source, dict) else 'NOT_OBSERVED',
        'source_start': source if isinstance(source, dict) else 'NOT_OBSERVED', 'source_end': end,
        'engine': engine, 'import_exit': import_exit, 'suite_exit': suite_exit,
        'runner_exit': runner_exit, 'evidence_exit_code': 1 if errors else 0,
        **totals, 'validation_errors': errors, 'owned_xdg_removed': removed,
        'cleanup_verified': cleanup_exit == 0 and removed is True,
        'acceptance': 'authored-rule component only; persistence and full delivery NOT_OBSERVED'}
    return retain(directory / 'result.json', result)


def main():
    if len(sys.argv) < 6:
        return 2
    action, directory, mode, binding, expected = sys.argv[1:6]
    if mode not in ['red','green'] or binding not in ['prepared','delivery'] or (binding == 'delivery' and mode != 'green'):
        return 2
    if not re.fullmatch(r'[1-9][0-9]*', expected):
        return 2
    if action == 'start' and len(sys.argv) == 6:
        return start(Path(directory), mode, binding, int(expected))
    if action == 'import-check' and len(sys.argv) == 6:
        errors = []
        log_errors(Path(directory) / 'import.log', errors)
        return 1 if errors else 0
    if action == 'preflight-check' and len(sys.argv) == 6:
        errors = []
        preflight = read_object(Path(directory) / 'preflight.json', errors, 'preflight')
        if type(preflight.get('schema_version')) is not int or preflight.get('schema_version') != 1 or preflight.get('passed') is not True or preflight.get('errors') != [] or preflight.get('runtime_executed') is not False:
            errors.append('preflight_not_qualified')
        return 1 if errors else 0
    if action == 'finish' and len(sys.argv) == 12:
        return finish(Path(directory), mode, binding, int(expected), sys.argv[6], int(sys.argv[7]),
                      int(sys.argv[8]), sys.argv[9], sys.argv[10], sys.argv[11])
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
