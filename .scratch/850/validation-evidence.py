#!/usr/bin/env python3
"""Owned #850 validation source custody, collection and failed-verdict retention."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SOURCES = ['server/claim_permit_authority.gd', 'server/sqlite_store.gd',
           'tests/integration/test_claim_permit_authority.gd', '.scratch/850/run-full.sh',
           '.scratch/850/run-focused.sh', '.scratch/850/observation-manifest.json',
           '.scratch/850/validation-plan.json', '.scratch/850/full-validation-plan.json',
           '.scratch/850/validation-evidence.py', '.scratch/850/run-evidence-controls.py']


def query(arguments, errors, label):
    try:
        value = subprocess.check_output(arguments, text=True, stderr=subprocess.DEVNULL, timeout=10).strip()
        if not value:
            raise ValueError('empty_identity')
        return value
    except subprocess.TimeoutExpired:
        errors.append(label + '_timeout')
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        errors.append(label + '_not_observed')
    return 'NOT_OBSERVED'


def identity(errors):
    revision = query(['git', 'rev-parse', 'HEAD'], errors, 'revision')
    if re.fullmatch('[0-9a-f]{40}', revision) is None:
        errors.append('revision_not_qualified')
        revision = 'NOT_OBSERVED'
    try:
        status = subprocess.check_output(['git', 'status', '--porcelain'], text=True,
                                        stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.SubprocessError, UnicodeError):
        status = 'NOT_OBSERVED'
        errors.append('source_status_not_observed')
    hashes = {}
    for source in SOURCES:
        try:
            hashes[source] = hashlib.sha256(Path(source).read_bytes()).hexdigest()
        except OSError:
            hashes[source] = 'NOT_OBSERVED'
            errors.append('source_hash_not_observed:' + source)
    return {'revision': revision, 'status': status, 'hashes': hashes}


def read_object(path, errors, label):
    try:
        if path.is_symlink():
            raise OSError('evidence symlink refused')
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError('object required')
        return value
    except (OSError, ValueError):
        errors.append(label + '_not_observed')
        return {}


def retain(path, record):
    record['result_retention'] = 'OBSERVED'
    try:
        if path.is_symlink():
            raise OSError('evidence symlink refused')
        path.write_text(json.dumps(record, indent=2) + '\n')
    except OSError:
        record['status'] = 'failed'
        record['result_retention'] = 'NOT_OBSERVED'
        record['validation_errors'].append('result_retention_failed')
        print(json.dumps(record))
        return 1
    print(json.dumps(record))
    return 1 if record['status'] == 'failed' else 0


def start(result, kind):
    errors = []
    snapshot = identity(errors)
    if kind == 'full' and snapshot['status'] != '':
        errors.append('source_not_clean_at_start')
    record = {'schema_version': 1, 'issue': 850, 'status': 'failed' if errors else 'passed',
              'identity': snapshot, 'validation_errors': errors}
    return retain(Path(str(result) + '.source-start.json'), record)


def collect(result, kind, label, expected, mode, codes, state):
    errors = []
    out = result.parent
    prefix = label if kind == 'focused' else 'gut'
    xml_path = out / (prefix + '.xml')
    counts = {'tests': 0, 'failures': 0, 'errors': 0, 'skips': 0}
    suites = []
    try:
        document = ET.parse(xml_path).getroot()
        suites = list(document.iter('testsuite'))
        counts = {'tests': len(document.findall('.//testcase')), 'failures': len(document.findall('.//failure')),
                  'errors': len(document.findall('.//error')), 'skips': len(document.findall('.//skipped'))}
    except (OSError, ET.ParseError):
        errors.append('junit_not_observed')
    logs = [label + '.log'] if kind == 'focused' else ['import.log', 'gut.log', 'full-runner.log']
    script_errors = False
    for name in logs:
        try:
            if re.search('SCRIPT ERROR|Parse Error|Compile Error|Failed to load script',
                         (out / name).read_text(errors='replace')):
                script_errors = True
        except OSError:
            errors.append('log_not_observed:' + name)
    if script_errors:
        errors.append('script_errors_observed')
    observations = {}
    observation_directory = out / (label + '-observations') if kind == 'focused' else out / 'observations'
    try:
        filenames = [path.name for path in observation_directory.glob('*.json')]
        if kind == 'full':
            manifest = json.loads(Path('.scratch/850/observation-manifest.json').read_text())
            if not isinstance(manifest, list) or any(not isinstance(name, str) for name in manifest):
                raise ValueError('invalid_observation_manifest')
            filenames = manifest
        for filename in filenames:
            observation = read_object(observation_directory / filename, errors, 'observation:' + filename)
            detail = observation.get('observation')
            if not isinstance(detail, dict) or detail.get('observation_status') != 'OBSERVED' or detail.get('native_row_effects') != 'NOT_OBSERVED':
                errors.append('observation_not_qualified:' + filename)
            observations[filename] = filename
    except (OSError, ValueError):
        errors.append('observation_inventory_not_observed')
    engine = query(['godot', '--version'], errors, 'engine')
    report = {'schema_version': 1, 'issue': 850, 'status': 'failed' if errors else ('passed' if mode == 'green' else 'expected_red'),
              'engine': engine, 'command': 'bash .scratch/850/run-' + kind + '.sh ' + label,
              **counts, 'script_errors': script_errors, 'observation_files': sorted(observations),
              'validation_errors': errors, 'milestone_acceptance': 'NOT_OBSERVED: integrated physical workshop authority'}
    if kind == 'focused':
        try:
            remaining = [str(path.relative_to(state)) for path in state.rglob('*.db*')]
        except OSError:
            remaining = 'NOT_OBSERVED'; errors.append('fixture_inventory_not_observed')
        report.update({'exit': codes[0], 'fixture_databases_remaining': remaining})
        if counts['tests'] != expected or counts['errors'] or counts['skips'] or remaining:
            errors.append('focused_evidence_not_qualified')
        if (mode == 'green' and (codes[0] != 0 or counts['failures'])) or (mode == 'red' and (codes[0] == 0 or counts['failures'] <= 0)):
            errors.append('focused_verdict_not_qualified')
    else:
        expected_scripts = {str(path) for directory in ['tests/unit', 'tests/integration']
                            for path in Path(directory).rglob('test_*.gd')}
        if not expected_scripts or len(suites) != len(expected_scripts) or {suite.get('name') for suite in suites} != expected_scripts:
            errors.append('incomplete_script_coverage')
        totals = {key: 0 for key in ['tests', 'failures', 'errors', 'skipped']}
        for suite in suites:
            try:
                values = {key: int(suite.get(key, '0')) for key in totals}
                if values['tests'] <= 0 or any(values[key] for key in ['failures', 'errors', 'skipped']):
                    errors.append('suite_not_passing')
                for key, value in values.items():
                    if value < 0: raise ValueError('negative_count')
                    totals[key] += value
            except (ValueError, TypeError): errors.append('invalid_junit_counts')
        summary = read_object(out / 'validation-summary.json', errors, 'standard_summary')
        if summary.get('status') != 'passed' or type(summary.get('exit_code')) is not int or summary.get('exit_code') != 0 or any(type(summary.get(key)) is not int or summary.get(key) != len(expected_scripts) for key in ['scripts_expected', 'scripts_ran']):
            errors.append('standard_summary_not_passing')
        if any(codes): errors.append('command_failed')
        report.update({**totals, 'scripts_expected': len(expected_scripts), 'scripts_ran': len(suites),
                       'standard_summary': summary, 'import_exit': codes[0], 'suite_exit': codes[1], 'record_sync_exit': codes[2]})
    if errors: report['status'] = 'failed'
    return retain(result, report)


def finalize(result, kind, state, runner_exit, cleanup_exit, stage):
    errors = []
    record = read_object(result, errors, 'result_preparation')
    if record.get('status') not in (['passed', 'failed'] if kind == 'full' else ['passed', 'expected_red', 'failed']):
        errors.append('result_status_not_qualified')
    prior = record.get('validation_errors', [])
    if not isinstance(prior, list) or any(not isinstance(value, str) for value in prior):
        prior = []; errors.append('result_errors_not_qualified')
    initial = read_object(Path(str(result) + '.source-start.json'), errors, 'source_start')
    snapshot = initial.get('identity')
    if type(initial.get('schema_version')) is not int or initial.get('schema_version') != 1 or type(initial.get('issue')) is not int or initial.get('issue') != 850 or initial.get('status') != 'passed' or initial.get('validation_errors') != [] or initial.get('result_retention') != 'OBSERVED' or not isinstance(snapshot, dict) or set(snapshot) != {'revision', 'status', 'hashes'}:
        errors.append('source_start_not_qualified'); snapshot = {}
    end = identity(errors)
    if snapshot != end: errors.append('source_changed_during_validation')
    if kind == 'full' and end['status'] != '': errors.append('source_not_clean_at_end')
    try: removed = not state.exists()
    except OSError: removed = 'NOT_OBSERVED'
    if removed is not True or cleanup_exit != 0: errors.append('cleanup_not_observed')
    if runner_exit != 0: errors.append('runner_failed')
    if record.get('status') in ['passed', 'expected_red']:
        required = ['engine', 'tests', 'failures', 'errors', 'skips' if kind == 'focused' else 'skipped', 'observation_files']
        if any(key not in record for key in required) or any(type(record.get(key)) is not int or record[key] < 0 for key in required if key in ['tests', 'failures', 'errors', 'skips', 'skipped']):
            errors.append('result_shape_not_qualified')
        if record.get('engine') in [None, '', 'NOT_OBSERVED']: errors.append('engine_not_observed')
    record.update({'schema_version': 1, 'issue': 850, 'kind': kind, 'stage': stage,
                   'engine': record.get('engine', 'NOT_OBSERVED'), 'revision': snapshot.get('revision', 'NOT_OBSERVED'), 'source_start': snapshot or 'NOT_OBSERVED',
                   'source_end': end, 'owned_xdg_removed': removed, 'cleanup_verified': removed is True and cleanup_exit == 0,
                   'runner_exit': runner_exit, 'cleanup_exit': cleanup_exit, 'validation_errors': prior + errors})
    if errors or prior: record['status'] = 'failed'
    return retain(result, record)


def main():
    action, filename, kind = sys.argv[1:4]
    result = Path(filename)
    if action == 'start': return start(result, kind)
    if action == 'collect':
        label, expected, mode, codes, state = sys.argv[4:9]
        return collect(result, kind, label, int(expected), mode, [int(code) for code in codes.split(',')], Path(state))
    if action == 'finalize':
        state, runner_exit, cleanup_exit, stage = sys.argv[4:8]
        return finalize(result, kind, Path(state), int(runner_exit), int(cleanup_exit), stage)
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
