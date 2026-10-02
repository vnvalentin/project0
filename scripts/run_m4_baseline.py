#!/usr/bin/env python3
"""Owned setup/run/evidence/teardown for #1376. No production configuration."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import re
import tarfile
import socket
import subprocess
import tempfile
import time

from m4_baseline_report import evaluate, audit_worker_probe

ROOT = Path(__file__).resolve().parents[1]
ERROR_MARKERS = ('SCRIPT ERROR:', 'Parse Error:', 'Compile Error:', 'Failed to load script')


def write_json(path, value):
    pending = path.with_suffix(path.suffix + '.pending')
    pending.write_text(json.dumps(value, indent=2) + '\n')
    pending.replace(path)


def available_port(kind):
    with socket.socket(socket.AF_INET, kind) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def competing_engines():
    """Allowlisted comm and cwd only; never process argv or environment."""
    results = []
    for item in Path('/proc').iterdir():
        if not item.name.isdigit():
            continue
        try:
            name = (item / 'comm').read_text().strip()
            if not name.lower().startswith('godot'):
                continue
            cwd = (item / 'cwd').resolve()
            if str(cwd).startswith('/data/code/project0'):
                results.append({'pid': int(item.name), 'cwd': str(cwd), 'comm': name})
        except (OSError, PermissionError):
            continue
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ticks', type=int, choices=(60, 1000), default=1000)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--server-image', required=True, help='Immutable locally cached sha256 image ID')
    args = parser.parse_args()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', args.server_image):
        parser.error('server-image must be an immutable SHA-256 image ID')
    os.chdir(ROOT)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'logs/experiments' / ('m4-1-' + stamp)
    folder.mkdir(parents=True, exist_ok=False)
    report_path = ROOT / 'logs/experiments' / ('exp_m4_1_baseline_' + stamp + '.json')
    report = {'issue': 1376, 'kind': 'smoke' if args.ticks == 60 else 'baseline',
              'started_utc': stamp, 'host': socket.gethostname(), 'requested_ticks': args.ticks,
              'command': ['python3', 'scripts/run_m4_baseline.py', '--ticks', str(args.ticks), '--server-image', args.server_image],
              'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
              'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True)),
              'engine': None,
              'competing_engines_before': competing_engines(), 'errors': [], 'artifacts': str(folder.relative_to(ROOT))}
    report['source_hashes'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in [ROOT / 'scripts/m4_load_server.gd', ROOT / 'scripts/m4_load_peer.gd',
                                         ROOT / 'scripts/run_m4_baseline.py', ROOT / 'scripts/m4_baseline_report.py']}
    report['structural_audit'] = audit_worker_probe((ROOT / 'scripts/m4_load_server.gd').read_text())
    owned = []
    files = []
    private = None
    container_name = 'project0-m4-1376-' + stamp.lower()
    container_created = False
    observation = {}
    try:
        if not report['structural_audit']['passed']:
            raise RuntimeError('structural_probe_failed')
        report['engine'] = subprocess.check_output([args.godot, '--version'], text=True).strip()
        if report['competing_engines_before']:
            raise RuntimeError('competing_project_engines')
        if report['source_dirty']:
            raise RuntimeError('uncommitted_source_cannot_define_runtime_artifact')
        private = Path(tempfile.mkdtemp(prefix='project0-m4-1376-'))
        private.chmod(0o700)
        env = {key: os.environ[key] for key in ('PATH', 'HOME', 'USER', 'LANG') if key in os.environ}
        env.update({'XDG_DATA_HOME': str(private / 'xdg-server'), 'DASHBOARD_RESULTS_DIR': str(private / 'dashboard'),
                    'PROJECT0_ASSERTION_SECRET': os.urandom(32).hex(), 'PROJECT0_ACCOUNTS_DB_PATH': 'm4-accounts.db',
                    'PROJECT0_CANON_DB_PATH': 'm4-canon.db', 'PROJECT0_SERVER_BIND_ADDRESS': '127.0.0.1',
                    'PROJECT0_SERVER_HOST': '127.0.0.1', 'PROJECT0_SERVER_PORT': str(available_port(socket.SOCK_DGRAM)),
                    'PROJECT0_OPERATOR_CONTROL_PORT': '0', 'PROJECT0_TICK_RATE': '30',
                    'PROJECT0_LLM_TOWN_AT_BOOT': '0', 'PROJECT0_CLIENT_LOGIN_SPLIT': '0', 'PROJECT0_CLIENT_HTTPS_LOGIN': '0',
                    'M4_PRIVATE': str(private), 'M4_HTTP_PORT': str(available_port(socket.SOCK_STREAM)),
                    'M4_TICKS': str(args.ticks), 'M4_STOP': str(private / 'stop'),
                    'M4_OBSERVATION': str(folder / 'server-observation.json')})
        archive = folder / 'source.tar'
        subprocess.run(['git', 'archive', '--format=tar', '--output=' + str(archive), report['source']], check=True)
        source = private / 'source'
        source.mkdir()
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                if Path(member.name).is_absolute() or '..' in Path(member.name).parts or member.issym() or member.islnk():
                    raise RuntimeError('unsafe_source_archive_member')
            bundle.extractall(source)
        report['source_archive_sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
        import_env = env | {'XDG_DATA_HOME': str(private / 'import-xdg')}
        for attempt in range(2):
            with (folder / ('artifact-import-%d.log' % attempt)).open('wb') as output:
                subprocess.run([args.godot, '--headless', '--path', str(source), '--import'], env=import_env,
                               stdout=output, stderr=subprocess.STDOUT, timeout=60, check=True)
        if any(marker in (folder / 'artifact-import-1.log').read_text(errors='replace') for marker in ERROR_MARKERS):
            raise RuntimeError('artifact_import_failed')
        runtime_archive = folder / 'runtime-artifact.tar'
        with tarfile.open(runtime_archive, 'w') as bundle:
            bundle.add(source, arcname='app')
        report['runtime_artifact_sha256'] = hashlib.sha256(runtime_archive.read_bytes()).hexdigest()
        report['container'] = {'image_id': args.server_image, 'cpus': 4, 'memory_bytes': 2147483648,
                               'entrypoint': 'tini -- godot --headless -s scripts/m4_load_server.gd',
                               'source_mount': 'immutable committed archive plus qualified import cache',
                               'peer_runtime': '10 headless host processes outside server cgroup'}
        # Every runtime path goes to this fresh private tree; no production env inheritance.
        def spawn(name, script, child_env, debug=False):
            stream = (folder / (name + '.log')).open('wb')
            files.append(stream)
            command = [args.godot, '--headless', '--path', str(ROOT), '--max-fps', '120']
            if debug:
                command += ['--debug']
            command += ['-s', script]
            process = subprocess.Popen(command, env=child_env, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True, stdin=subprocess.DEVNULL)
            owned.append(process)
            return process
        container_env = env | {'XDG_DATA_HOME': '/state/xdg-server', 'M4_PRIVATE': '/state',
                               'M4_OBSERVATION': '/evidence/server-observation.json',
                               'PROJECT0_SERVER_BIND_ADDRESS': '0.0.0.0', 'PROJECT0_HEALTH_FILE': '/state/health.json'}
        env_file = private / 'server.env'
        env_file.write_text(''.join(key + '=' + value + '\n' for key, value in container_env.items()
                                    if key not in ('PATH', 'HOME', 'USER', 'LANG')))
        env_file.chmod(0o600)
        user = str(os.getuid()) + ':' + str(os.getgid())
        engine = subprocess.check_output(['docker', 'run', '--rm', '--network', 'none', '--read-only',
                   '--cpus', '1', '--memory', '256m', '--user', user, '--entrypoint', 'godot', args.server_image, '--version'], text=True).strip()
        if engine != report['engine']:
            raise RuntimeError('container_and_peer_engine_mismatch')
        report['container']['engine'] = engine
        command = ['docker', 'run', '--name', container_name, '--rm', '--read-only', '--no-healthcheck',
                   '--cpus', '4', '--memory', '2g', '--pids-limit', '512', '--user', user,
                   '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                   '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m', '--env-file', str(env_file),
                   '--publish', '127.0.0.1:' + env['PROJECT0_SERVER_PORT'] + ':' + env['PROJECT0_SERVER_PORT'] + '/udp',
                   '--mount', 'type=bind,src=' + str(source) + ',dst=/app,readonly',
                   '--mount', 'type=bind,src=' + str(private) + ',dst=/state',
                   '--mount', 'type=bind,src=' + str(folder) + ',dst=/evidence',
                   '--entrypoint', '/usr/bin/tini', args.server_image, '--', 'godot', '--headless',
                   '--path', '/app', '--max-fps', '120', '--debug', '-s', 'scripts/m4_load_server.gd']
        stream = (folder / 'server.log').open('wb')
        files.append(stream)
        server = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                  start_new_session=True)
        owned.append(server)
        container_created = True
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            observation = read_json(folder / 'server-observation.json')
            if observation.get('status') == 'setup_ready':
                break
            if server.poll() is not None:
                raise RuntimeError('server_setup_exited')
            time.sleep(.05)
        else:
            raise RuntimeError('server_setup_deadline')
        for index in range(10):
            peer_env = {k: v for k, v in env.items() if k != 'PROJECT0_ASSERTION_SECRET'}
            peer_env.update({'XDG_DATA_HOME': str(private / ('xdg-peer-%d' % index)),
                             'M4_ASSERTION_PATH': str(private / ('assertion-%d' % index)),
                             'M4_PEER_RESULT': str(folder / ('peer-%d.json' % index))})
            spawn('peer-%d' % index, 'scripts/m4_load_peer.gd', peer_env)
        deadline = time.monotonic() + 140
        competition_check = time.monotonic()
        report['competing_engines_during'] = []
        while server.poll() is None and time.monotonic() < deadline:
            if any(peer.poll() is not None for peer in owned[1:]):
                raise RuntimeError('load_peer_exited_before_server')
            if time.monotonic() >= competition_check:
                others = [p for p in competing_engines() if p['pid'] not in {item.pid for item in owned}]
                report['competing_engines_during'].extend(others)
                if others:
                    raise RuntimeError('competing_project_engines_during_run')
                competition_check = time.monotonic() + 1
            time.sleep(.05)
        if server.poll() is None:
            raise RuntimeError('runtime_deadline')
        report['server_exit'] = server.returncode
        (private / 'stop').touch()
        for peer in owned[1:]:
            peer.wait(timeout=10)
        report['peer_exits'] = [peer.returncode for peer in owned[1:]]
        observation = read_json(folder / 'server-observation.json')
        report['peers'] = [read_json(folder / ('peer-%d.json' % index)) for index in range(10)]
        if server.returncode != 0 or any(peer.returncode != 0 for peer in owned[1:]):
            raise RuntimeError('runtime_nonzero_exit')
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        # Fixed reason/class only; no captured environments, token values or argv dumps.
        report['errors'].append(str(error) if isinstance(error, RuntimeError) else type(error).__name__)
    finally:
        if private is not None:
            (private / 'stop').touch(exist_ok=True)
        if container_created:
            for command in (['docker', 'stop', '--time', '3', container_name], ['docker', 'rm', '-f', container_name]):
                try:
                    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
                except (OSError, subprocess.SubprocessError):
                    report['errors'].append('container_cleanup_command_failed')
        for process in owned:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)
        for stream in files:
            stream.close()
        observation = read_json(folder / 'server-observation.json') or observation
        for log in [folder / 'server.log', *folder.glob('peer-*.log')]:
            if not log.exists():
                continue
            content = log.read_text(errors='replace')
            if any(marker in content for marker in ERROR_MARKERS):
                report['errors'].append('runtime_script_error:' + log.name)
        if private is not None:
            try:
                shutil.rmtree(private)
            except OSError:
                report['errors'].append('private_cleanup_failed')
        try:
            inventory = subprocess.run(['docker', 'container', 'ls', '--all', '--filter', 'name=^/' + container_name + '$', '--format', '{{.Names}}'], capture_output=True, text=True, timeout=10)
            container_absent = inventory.returncode == 0 and not inventory.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            container_absent = False
        cleanup = container_absent and all(process.poll() is not None for process in owned) and (private is None or not private.exists())
        report['cleanup'] = {'container_removed': container_absent, 'processes_stopped': all(p.poll() is not None for p in owned),
                             'private_tree_removed': private is None or not private.exists(), 'verified': cleanup}
        observation.setdefault('isolation', {})['structural_nonblocking_verified'] = report['structural_audit']['passed']
        report['observation'] = observation
        if report['errors']:
            observation.setdefault('errors', []).extend(report['errors'])
        report['evaluation'] = evaluate(observation, cleanup)
        report['passed'] = report['evaluation']['passed'] and not report['errors'] and args.ticks == 1000
        report['completed_utc'] = datetime.now(timezone.utc).isoformat()
        write_json(report_path, report)
        if not report['passed']:
            write_json(ROOT / 'logs/experiments' / ('exp_m4_1_FAIL_trace_' + stamp + '.json'), report)
        print(json.dumps({'report': str(report_path.relative_to(ROOT)), 'passed': report['passed'],
                          'samples': len(observation.get('samples', [])), 'errors': report['errors'],
                          'failed_checks': report['evaluation']['failed_checks'], 'cleanup': cleanup}))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
