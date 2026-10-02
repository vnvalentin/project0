#!/usr/bin/env python3
"""#951 owned validation custody and failure evidence; never launches Godot."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SOURCES = ['server/admitted_player_state.gd', 'server/workshop_station_contract.gd',
           'server/workshop_character_sensor.gd', 'server/workshop_station_volume.gd',
           'tests/integration/test_workshop_station_authority.gd', 'server/sqlite_store.gd',
           'server/interior_anchor_repository.gd', '.scratch/951/run-validation.sh',
           '.scratch/951/validation-evidence.py', '.scratch/951/validation-plan.json',
           '.scratch/951/full-validation-plan.json']


def git_identity(arguments, errors, name):
    try:
        value = subprocess.check_output(['git', *arguments], text=True, stderr=subprocess.DEVNULL, timeout=10).strip()
        if arguments[0] == 'rev-parse' and not re.fullmatch(r'[0-9a-f]{40}', value):
            raise ValueError('invalid_revision')
        return value
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        errors.append(name + '_not_observed')
        return 'NOT_OBSERVED'


def hashes(errors):
    values = {}
    for source in SOURCES:
        try:
            values[source] = hashlib.sha256(Path(source).read_bytes()).hexdigest()
        except OSError:
            values[source] = 'NOT_OBSERVED'
            errors.append('source_not_observed:' + source)
    return values


def read_object(path, errors, name):
    try:
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError('not_object')
        return value
    except (OSError, ValueError, UnicodeError):
        errors.append(name + '_not_observed')
        return {}


def retain(path, record):
    record['result_retention'] = 'OBSERVED'
    try:
        path.write_text(json.dumps(record, indent=2) + '\n')
    except (OSError, UnicodeError):
        record['status'] = 'failed'
        record['result_retention'] = 'NOT_OBSERVED'
        record['evidence_exit_code'] = 1
        record['evidence_errors'].append('result_retention_not_observed')
        print(json.dumps(record))
        return False
    print(json.dumps({k: record[k] for k in ['status', 'stage', 'revision', 'evidence_errors', 'result_retention']}))
    return True


def selection(mode):
    if mode == 'focused':
        return ['tests/integration/test_workshop_station_authority.gd']
    return sorted(str(p) for root in ['tests/unit', 'tests/integration'] for p in Path(root).glob('test_*.gd'))


def start(directory, mode):
    errors = []
    revision = git_identity(['rev-parse', 'HEAD'], errors, 'initial_revision')
    status = git_identity(['status', '--porcelain'], errors, 'initial_status')
    clean = 'NOT_OBSERVED' if status == 'NOT_OBSERVED' else not status
    if mode == 'full' and clean is not True:
        errors.append('source_not_clean_at_start')
    sources = hashes(errors)
    expected = selection(mode)
    plan_file = '.scratch/951/full-validation-plan.json' if mode == 'full' else '.scratch/951/validation-plan.json'
    plan = read_object(Path(plan_file), errors, 'validation_plan')
    steps = plan.get('steps')
    if not isinstance(steps, list) or len(steps) != 1 or not isinstance(steps[0], dict) or steps[0].get('tests') != expected:
        errors.append('validation_plan_inventory_mismatch')
    if not expected:
        errors.append('empty_test_selection')
    record = {'schema_version': 1, 'issue': 951, 'mode': mode, 'revision': revision,
              'source_clean': clean, 'source_sha256': sources, 'expected_scripts': expected,
              'status': 'failed' if errors else 'passed', 'stage': 'source_start', 'evidence_errors': errors}
    retained = retain(directory / 'source-start.json', record)
    return 0 if retained and not errors else 1


def finish(directory, mode, label, code, stage, cleanup, engine):
    errors = []
    initial = read_object(directory / 'source-start.json', errors, 'source_start')
    if type(initial.get('schema_version')) is not int or initial.get('schema_version') != 1 or type(initial.get('issue')) is not int or initial.get('issue') != 951 or initial.get('mode') != mode or initial.get('status') != 'passed' or initial.get('result_retention') != 'OBSERVED' or initial.get('evidence_errors') != [] or (mode == 'full' and initial.get('source_clean') is not True):
        errors.append('source_start_not_qualified')
    initial_errors = initial.get('evidence_errors')
    if isinstance(initial_errors, list):
        errors.extend(x for x in initial_errors if isinstance(x, str))
    revision = git_identity(['rev-parse', 'HEAD'], errors, 'final_revision')
    status = git_identity(['status', '--porcelain'], errors, 'final_status')
    clean = 'NOT_OBSERVED' if status == 'NOT_OBSERVED' else not status
    if mode == 'full' and clean is not True:
        errors.append('source_not_clean_at_end')
    sources = hashes(errors)
    if revision != initial.get('revision'):
        errors.append('revision_changed')
    if sources != initial.get('source_sha256'):
        errors.append('source_changed')
    expected = selection(mode)
    if expected != initial.get('expected_scripts'):
        errors.append('test_inventory_changed')
    suites = []
    try:
        suites = [s.attrib for s in ET.parse(directory / 'gut.xml').iter('testsuite')]
    except (OSError, ET.ParseError, UnicodeError):
        errors.append('junit_not_observed')
    if len(suites) != len(expected) or {s.get('name') for s in suites} != set(expected):
        errors.append('selected_script_coverage_incomplete')
    for suite in suites:
        try:
            if not all(re.fullmatch(r'[0-9]+', suite.get(k, '0')) for k in ['tests', 'failures', 'errors', 'skipped']):
                raise ValueError('invalid_count')
            if int(suite.get('tests', '0')) <= 0 or any(int(suite.get(k, '0')) for k in ['failures', 'errors', 'skipped']):
                errors.append('suite_not_passing')
        except (ValueError, TypeError):
            errors.append('invalid_junit_counts')
    markers = []
    logs = ['preflight.log', 'import.log', 'gut.log'] + (['full-runner.log'] if mode == 'full' else [])
    for name in logs:
        try:
            for n, line in enumerate((directory / name).read_text(errors='replace').splitlines(), 1):
                if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script', line, re.I):
                    markers.append({'file': name, 'line': n, 'message': line[:400]})
        except OSError:
            errors.append('log_not_observed:' + name)
    if markers:
        errors.append('godot_script_failure')
    summary = {}
    if mode == 'full':
        summary = read_object(directory / 'validation-summary.json', errors, 'standard_summary')
        if summary.get('status') != 'passed' or type(summary.get('scripts_expected')) is not int or summary.get('scripts_expected') != len(expected) or type(summary.get('scripts_ran')) is not int or summary.get('scripts_ran') != len(expected) or type(summary.get('exit_code')) is not int or summary.get('exit_code') != 0:
            errors.append('standard_summary_not_passing')
    if cleanup != 'true':
        errors.append('cleanup_not_verified')
    if code != 0:
        errors.append('engine_or_preparation_exit_nonzero')
    record = {'schema_version': 1, 'issue': 951, 'host': '192.168.1.254', 'mode': mode,
              'revision': initial.get('revision', 'NOT_OBSERVED'), 'final_revision': revision,
              'source_clean_start': initial.get('source_clean', 'NOT_OBSERVED'), 'source_clean_end': clean,
              'source_sha256': sources, 'source_sha256_start': initial.get('source_sha256', 'NOT_OBSERVED'),
              'expected_scripts': expected, 'suites': suites, 'engine': engine, 'stage': stage,
              'command': 'bash .scratch/951/run-validation.sh ' + label + ' ' + mode,
              'exit_code': code, 'evidence_exit_code': 1 if errors else 0, 'evidence_errors': errors,
              'status': 'failed' if errors else 'passed', 'script_failure_markers': markers,
              'cleanup_verified': cleanup == 'true', 'isolated_xdg': True, 'isolated_dashboard_results': True,
              'standard_summary': summary, 'artifact_directory': str(directory),
              'runtime_acceptance': 'bounded station component only; full workshop NOT_OBSERVED'}
    retained = retain(directory / 'result.json', record)
    return 0 if retained and not errors else 1


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ['start', 'finish'] or sys.argv[3] not in ['focused', 'full']:
        return 2
    directory = Path(sys.argv[2])
    if sys.argv[1] == 'start' and len(sys.argv) == 4:
        return start(directory, sys.argv[3])
    if sys.argv[1] == 'finish' and len(sys.argv) == 9:
        return finish(directory, sys.argv[3], sys.argv[4], int(sys.argv[5]), sys.argv[6], sys.argv[7], sys.argv[8])
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
