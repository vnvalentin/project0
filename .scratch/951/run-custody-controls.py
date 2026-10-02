#!/usr/bin/env python3
"""#951 copied whole-runner controls; every Godot/Git command is a fixture stub."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

PROJECT = Path(__file__).resolve().parents[2]
os.chdir(PROJECT)
HELPER = PROJECT / '.scratch/951/validation-evidence.py'
SOURCES = ['server/admitted_player_state.gd', 'server/workshop_station_contract.gd',
           'server/workshop_character_sensor.gd', 'server/workshop_station_volume.gd',
           'tests/integration/test_workshop_station_authority.gd', 'server/sqlite_store.gd',
           'server/interior_anchor_repository.gd', '.scratch/951/run-validation.sh',
           '.scratch/951/validation-evidence.py', '.scratch/951/validation-plan.json',
           '.scratch/951/full-validation-plan.json']
CASES = {'valid': None, 'dirty-start': 'source_not_clean_at_start',
         'dirty-end': 'source_not_clean_at_end', 'changed-head': 'revision_changed',
         'changed-source': 'source_changed', 'missing-start-identity': 'initial_revision_not_observed',
         'missing-end-identity': 'final_revision_not_observed', 'missing-end-source': 'source_not_observed:',
         'nonmap-start-json': 'source_start_not_observed', 'truncated-start-json': 'source_start_not_observed',
         'unreadable-start-json': 'source_start_not_observed', 'malformed-start-fields': 'source_start_not_qualified', 'nonmap-summary': 'standard_summary_not_observed',
         'truncated-summary': 'standard_summary_not_observed', 'unreadable-summary': 'standard_summary_not_observed',
         'cleanup-failure': 'cleanup_not_verified', 'retention-failure': 'result_retention_not_observed'}
STUB = r'''#!/usr/bin/env python3
import json,os,sys,tempfile
from pathlib import Path
import xml.etree.ElementTree as E
name=Path(sys.argv[0]).name
case=os.environ['CONTROL_CASE']; root=Path(os.environ['CONTROL_ROOT']); phase=(root/'phase').exists()
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps({'tool':name,'arguments':sys.argv[1:]})+'\n')
if name=='git':
 command=sys.argv[1]
 if command=='rev-parse':
  if case=='missing-start-identity' and not phase or case=='missing-end-identity' and phase:sys.exit(1)
  print(('b' if case=='changed-head' and phase else 'a')*40)
 elif command=='status':
  if case=='dirty-start' and not phase or case=='dirty-end' and phase:print(' M fixture.gd')
 else:sys.exit(2)
elif name=='godot':
 if sys.argv[1:]==['--version']:print('CONTROL_STUB_NO_NATIVE')
 elif '--import' not in sys.argv:sys.exit(99)
elif name=='timeout':
 args=sys.argv[1:]
 while args and args[0].startswith('--'):args=args[1:]
 args=args[1:]
 os.execvp(args[0],args)
elif name=='mktemp':
 p=tempfile.mkdtemp(prefix='project0-951.control.')
 (root/'fixture-path').write_text(p)
 print(p)
elif name=='rm':
 if case=='cleanup-failure':sys.exit(1)
 os.execv('/usr/bin/rm',['rm',*sys.argv[1:]])
elif name=='fake-gut':
 out=Path(os.environ['RESULT_DIR']); tests=json.loads(Path('.scratch/951/full-validation-plan.json').read_text())['steps'][0]['tests']
 document=E.Element('testsuites')
 for test in tests:E.SubElement(document,'testsuite',name=test,tests='1',failures='0',errors='0',skipped='0')
 E.ElementTree(document).write(out/'gut.xml')
 (out/'gut.log').write_text('synthetic whole-runner control; no Godot\n')
 summary={'status':'passed','scripts_expected':len(tests),'scripts_ran':len(tests),'exit_code':0}
 (out/'validation-summary.json').write_text(json.dumps(summary))
 target=out/'source-start.json'
 if case=='malformed-start-fields':
  malformed=json.loads(target.read_text());malformed['source_clean']=False;malformed['schema_version']=True;target.write_text(json.dumps(malformed))
 if case=='nonmap-start-json':target.write_text('[]')
 if case=='truncated-start-json':target.write_text('{')
 if case=='unreadable-start-json':target.unlink();target.mkdir()
 if case=='nonmap-summary':(out/'validation-summary.json').write_text('[]')
 if case=='truncated-summary':(out/'validation-summary.json').write_text('{')
 if case=='unreadable-summary':(out/'validation-summary.json').unlink();(out/'validation-summary.json').mkdir()
 if case=='changed-source':Path('server/workshop_station_contract.gd').write_text('changed copied source')
 if case=='missing-end-source':Path('server/workshop_station_contract.gd').unlink()
 if case=='retention-failure':(out/'result.json').mkdir()
 (root/'phase').write_text('end')
else:sys.exit(2)
'''


def source_hashes():
    return {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in SOURCES}


def run():
    identity = uuid.uuid4().hex[:12]
    output = PROJECT / 'build/validation/951' / ('custody-controls-' + identity)
    output.mkdir(parents=True)
    before = source_hashes()
    records = []
    context = Path(tempfile.mkdtemp(prefix='project0-951-custody-controls.'))
    cleanup = False
    try:
        tests = json.loads(Path('.scratch/951/full-validation-plan.json').read_text())['steps'][0]['tests']
        for case, expected_error in CASES.items():
            root = context / case
            root.mkdir()
            for source in SOURCES:
                target = root / source
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(PROJECT / source, target)
            for test in tests:
                target = root / test
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():target.write_text('synthetic inventory control\n')
            scripts = root / 'scripts'
            scripts.mkdir(exist_ok=True)
            (scripts / 'check_validation_ownership.py').write_text('print("synthetic preflight; native_runtime_executed=false")\n')
            fake = root / 'bin'
            fake.mkdir()
            for name in ['git', 'godot', 'timeout', 'mktemp', 'rm', 'fake-gut']:
                tool = fake / name
                tool.write_text(STUB)
                tool.chmod(0o700)
            runner = scripts / 'run_gut_validation.sh'
            runner.write_text('#!/usr/bin/env bash\nexec fake-gut\n')
            runner.chmod(0o700)
            environment = os.environ.copy()
            environment.update({'CONTROL_CASE': case, 'CONTROL_ROOT': str(root), 'PATH': str(fake) + ':' + environment['PATH']})
            result = subprocess.run(['bash', '.scratch/951/run-validation.sh', case, 'full'], cwd=root,
                                    env=environment, text=True, capture_output=True, timeout=60)
            retained = list((root / 'build/validation/951').glob('*/result.json'))
            verdict = None
            if retained and retained[0].is_file():
                verdict = json.loads(retained[0].read_text())
            else:
                for line in result.stdout.splitlines():
                    try:value=json.loads(line)
                    except ValueError:continue
                    if isinstance(value, dict) and value.get('issue') == 951 and 'cleanup_verified' in value:verdict=value
            assert isinstance(verdict, dict), (case, 'missing_structured_verdict')
            assert result.returncode == (0 if case == 'valid' else 1), (case, result.returncode)
            assert verdict['status'] == ('passed' if case == 'valid' else 'failed'), case
            if expected_error:
                assert any(e.startswith(expected_error) for e in verdict['evidence_errors']), (case, verdict['evidence_errors'])
            assert verdict['cleanup_verified'] == (case != 'cleanup-failure'), case
            assert verdict['result_retention'] == ('NOT_OBSERVED' if case == 'retention-failure' else 'OBSERVED'), case
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            assert all(c['tool'] in ['git', 'godot', 'timeout', 'mktemp', 'rm', 'fake-gut'] for c in calls)
            fixture_record = root / 'fixture-path'
            if fixture_record.is_file():
                fixture = Path(fixture_record.read_text())
                assert fixture.parent == Path('/tmp') and fixture.name.startswith('project0-951.control.')
                if fixture.exists():shutil.rmtree(fixture)
                assert not fixture.exists()
            record = {'case': case, 'exit_code': result.returncode, 'status': verdict['status'],
                      'evidence_errors': verdict['evidence_errors'], 'cleanup_verified': verdict['cleanup_verified'],
                      'result_retention': verdict['result_retention'], 'verdict_captured': True,
                      'native_runtime_executed': False, 'actual_git_mutated': False,
                      'independent_control_cleanup_verified': True}
            records.append(record)
            (output / (case + '-verdict.json')).write_text(json.dumps(verdict, indent=2) + '\n')
    finally:
        # Teardown also covers a control assertion failing before per-case cleanup.
        for fixture_record in context.glob('*/fixture-path'):
            fixture = Path(fixture_record.read_text())
            if fixture.parent == Path('/tmp') and fixture.name.startswith('project0-951.control.') and not fixture.is_symlink():
                if fixture.exists():shutil.rmtree(fixture)
                assert not fixture.exists()
        shutil.rmtree(context)
        cleanup = not context.exists()
        unchanged = source_hashes() == before
        report = {'schema_version': 1, 'issue': 951, 'passed': len(records) == len(CASES) and cleanup and unchanged,
                  'cases': records, 'copied_context_cleanup_verified': cleanup,
                  'actual_selected_sources_preserved': unchanged, 'native_runtime_executed': False,
                  'actual_git_mutated': False}
        (output / 'control-result.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({'artifact': str(output / 'control-result.json'), 'passed': report['passed'], 'cases': len(records)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(run())
