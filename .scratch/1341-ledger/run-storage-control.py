#!/usr/bin/env python3
"""Owned diagnostic only; caller holds shared native validation lock through exit."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[2]
os.chdir(PROJECT)
RUN = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'[A-Za-z0-9_-]+', RUN):
    raise SystemExit(2)
RESULT = PROJECT / 'build/validation/1341-ledger' / RUN
if RESULT.exists() or RESULT.is_symlink():
    raise SystemExit(2)
RESULT.mkdir(parents=True, mode=0o700)
PERSISTENT = RESULT / 'user-data'
TMPFS = None
SOURCES = ['server/sqlite_store.gd', 'server/canon_repository.gd',
           'server/canon_generation_coordinator.gd', '.scratch/1341-ledger/canon-timing-probe.gd',
           '.scratch/1341-ledger/run-storage-control.py', '.scratch/1341-ledger/storage-control-validation-plan.json']
report = {'status': 'failed', 'acceptance': 'diagnostic only; tmpfs is excluded from durability/acceptance',
          'host': '192.168.1.254', 'samples': [], 'validation_errors': [],
          'command': 'python3 .scratch/1341-ledger/run-storage-control.py ' + RUN,
          'shared_lock_scope': 'caller must hold shared native validation lock across runner and cleanup',
          'cleanup': {'persistent': 'NOT_OBSERVED', 'tmpfs': 'NOT_OBSERVED'}}


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def hashes():
    return {s: hashlib.sha256(Path(s).read_bytes()).hexdigest() for s in SOURCES}


def filesystem(path):
    return subprocess.check_output(['stat', '-f', '-c', '%T', str(path)], text=True).strip()


def remove_owned(path, parent, prefix):
    if path is None:
        return 'NOT_CREATED'
    if path.parent != parent or not path.name.startswith(prefix) or path.is_symlink():
        return 'NOT_OBSERVED'
    if path.exists():
        shutil.rmtree(path)
    return not path.exists()


try:
    report['revision'] = git('rev-parse', 'HEAD')
    if git('status', '--porcelain'):
        raise ValueError('source_not_clean')
    report['source_sha256'] = hashes()
    preflight = subprocess.run(['python3', 'scripts/check_validation_ownership.py', '--plan',
        '.scratch/1341-ledger/storage-control-validation-plan.json', '--output', str(RESULT / 'preflight.json')],
        capture_output=True, text=True, timeout=30)
    (RESULT / 'preflight.log').write_text(preflight.stdout + preflight.stderr)
    if preflight.returncode != 0:
        raise ValueError('preflight_failed')
    fs = {'persistent': filesystem(RESULT), 'temporary_memory': filesystem('/dev/shm')}
    report['filesystem_classes'] = fs
    if fs['persistent'] not in ('ext2/ext3', 'xfs', 'btrfs') or fs['temporary_memory'] != 'tmpfs':
        raise ValueError('filesystem_precondition_failed')
    PERSISTENT.mkdir(mode=0o700)
    TMPFS = Path(tempfile.mkdtemp(prefix='project0-m3-1341-ab.', dir='/dev/shm'))
    if TMPFS.is_symlink() or TMPFS.parent != Path('/dev/shm'):
        raise ValueError('tmpfs_target_guard_failed')
    report['engine'] = subprocess.check_output(['godot', '--version'], text=True).strip()
    for pair, order in enumerate([['persistent', 'temporary_memory'], ['temporary_memory', 'persistent'],
                                  ['persistent', 'temporary_memory']]):
        for position, kind in enumerate(order):
            target = PERSISTENT if kind == 'persistent' else TMPFS
            if any(target.iterdir()):
                raise ValueError('fixture_target_not_empty')
            stem = f'pair-{pair}-{position}-{kind}'
            sample_dir = RESULT / stem
            sample_dir.mkdir(mode=0o700)
            environment = os.environ.copy()
            environment['XDG_DATA_HOME'] = str(target)
            environment['DASHBOARD_RESULTS_DIR'] = str(sample_dir / 'dashboard')
            command = ['godot', '--headless', '--path', '.', '-s',
                       '.scratch/1341-ledger/canon-timing-probe.gd', '--', str(sample_dir / 'probe.json'), '1']
            item = {'pair': pair, 'order': position, 'storage_class': kind, 'command': command,
                    'exit_code': 'NOT_OBSERVED', 'probe': 'NOT_OBSERVED', 'fixture_removed': 'NOT_OBSERVED'}
            report['samples'].append(item)
            with (sample_dir / 'probe.log').open('w') as output:
                try:
                    item['exit_code'] = subprocess.run(command, env=environment, stdout=output,
                        stderr=subprocess.STDOUT, timeout=45).returncode
                except subprocess.TimeoutExpired:
                    item['exit_code'] = 'TIMEOUT'
            text = (sample_dir / 'probe.log').read_text()
            if re.search(r'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script', text):
                raise ValueError('script_error')
            probe = json.loads((sample_dir / 'probe.json').read_text())
            item['probe'] = probe
            if item['exit_code'] != 0 or probe.get('status') != 'passed' or len(probe.get('samples', [])) != 1:
                raise ValueError('probe_incomplete')
            if any(p.is_file() or p.is_symlink() for p in target.rglob('test_canon_timing_*')):
                raise ValueError('fixture_files_remain')
            # Godot may leave empty app_userdata directories; remove only this fresh owned root.
            for child in list(target.iterdir()):
                if child.is_symlink() or not child.is_dir():
                    raise ValueError('unexpected_fixture_state')
                shutil.rmtree(child)
            item['fixture_removed'] = not any(target.iterdir())
    settings = [s['probe']['samples'][0]['sqlite_settings'] for s in report['samples']]
    if len(settings) != 6 or any(s != settings[0] for s in settings):
        raise ValueError('sqlite_settings_changed')
    report['sqlite_settings'] = settings[0]
    if git('rev-parse', 'HEAD') != report['revision'] or hashes() != report['source_sha256'] or git('status', '--porcelain'):
        raise ValueError('source_changed')
    report['status'] = 'passed'
except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
    report['validation_errors'].append(str(error) if isinstance(error, ValueError) else type(error).__name__)
finally:
    for key, target, parent, prefix in [('persistent', PERSISTENT, RESULT, 'user-data'),
                                         ('tmpfs', TMPFS, Path('/dev/shm'), 'project0-m3-1341-ab.')]:
        try:
            report['cleanup'][key] = remove_owned(target, parent, prefix)
        except OSError:
            report['cleanup'][key] = 'NOT_OBSERVED'
    if report['cleanup']['persistent'] not in (True, 'NOT_CREATED') or report['cleanup']['tmpfs'] not in (True, 'NOT_CREATED'):
        report['status'] = 'failed'
        report['validation_errors'].append('cleanup_not_observed')
    (RESULT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
raise SystemExit(0 if report['status'] == 'passed' else 1)
