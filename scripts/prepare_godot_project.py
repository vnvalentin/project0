#!/usr/bin/env python3
"""Prepare an owned Linux Godot source copy; the caller owns its lifecycle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import selectors
import shutil
import signal
import stat
import subprocess
import threading
import time

EXTENSION = 'addons/godot-sqlite/gdsqlite.gdextension'
REGISTRY = ('res://' + EXTENSION + '\n').encode()
GUT_ENABLED = 'enabled=PackedStringArray("res://addons/gut/plugin.cfg")'
GUT_DISABLED = 'enabled=PackedStringArray()'
LOGGING = '\n[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n'
EXCLUDED = {'.git', '.godot', '.scratch', '.aws', '.codex', '.ssh', '.env',
            '.auth', '.config', '.cache', '.local', 'private', 'secrets', 'credentials', 'build', 'logs',
            '__pycache__', '.pytest_cache', '.venv', 'node_modules', '.preparation-runtime'}
SCRIPT_MARKERS = ('SCRIPT ERROR', 'Parse Error', 'Compile Error', 'Failed to load script')


class PreparationError(ValueError):
    """A fixed, non-secret diagnostic category defined by this helper."""


def excluded(path):
    name = path.name.lower()
    return (any(part.lower() in EXCLUDED for part in path.parts) or
            name.startswith('.env.') or name in {
                'id_rsa', 'id_ecdsa', 'id_ed25519', 'authorized_keys', '.netrc',
                '.git-credentials', '.npmrc', '.pypirc', 'auth.json', 'credentials.json',
                'credentials.toml', 'token.json', 'tokens.json', 'secrets.json'} or
            name.endswith(('.env', '.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.log')) or
            re.search(r'\.(db|sqlite|sqlite3)(-(wal|shm|journal))?$', name) is not None)


def ordinary(path):
    return stat.S_ISREG(path.lstat().st_mode)


def git_read(root, *arguments, check=True):
    command = [shutil.which('git', path='/usr/bin:/bin'), '-C', str(root),
               '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null', *arguments]
    environment = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8',
                   'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                   'GIT_OPTIONAL_LOCKS': '0', 'GIT_TERMINAL_PROMPT': '0'}
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          env=environment, timeout=15, check=check)


def git_index(root):
    entries = {}
    for record in git_read(root, 'ls-files', '--stage', '-z').stdout.split(b'\0'):
        if record:
            metadata, name = record.split(b'\t', 1)
            mode, blob, stage = metadata.decode('ascii').split()
            path = Path(os.fsdecode(name))
            if path in entries or stage != '0':
                raise PreparationError('source_index_conflict')
            entries[path] = (mode, blob)
    return entries


def check_override(root):
    override = root / 'override.cfg'
    if override.exists() or override.is_symlink():
        raise PreparationError('configuration_override_unknown_edit_preserved')


def verify_source(root, revision, hashes, committed):
    check_override(root)
    if committed is not None:
        if git_read(root, 'rev-parse', '--verify', 'HEAD').stdout.decode('ascii').strip() != revision:
            raise PreparationError('source_revision_changed')
        index = git_index(root)
    for name, expected in hashes.items():
        path = root / name
        if path.is_symlink() or not ordinary(path):
            raise PreparationError('source_custody_failed')
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != expected:
            raise PreparationError('source_changed_during_preparation')
        if committed is not None:
            relative = Path(name)
            blob = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
            if index.get(relative) != committed[relative] or blob != committed[relative][1]:
                raise PreparationError('source_tracked_dirt')


def source_inventory(root, revision, prepared):
    git = shutil.which('git', path='/usr/bin:/bin')
    head = None
    committed = None
    if git:
        probe = git_read(root, 'rev-parse', '--verify', 'HEAD', check=False)
        if probe.returncode == 0:
            head = probe.stdout.decode('ascii').strip()
    if head is not None:
        if head != revision:
            raise PreparationError('source_revision_conflict')
        top = git_read(root, 'rev-parse', '--show-toplevel').stdout
        if Path(os.fsdecode(top).strip()).resolve() != root:
            raise PreparationError('source_root_not_checkout_root')
        index = git_index(root)
        committed = {}
        for record in git_read(root, 'ls-tree', '-rz', '--full-tree', revision).stdout.split(b'\0'):
            if record:
                metadata, name = record.split(b'\t', 1)
                mode, kind, blob = metadata.decode('ascii').split()
                path = Path(os.fsdecode(name))
                if not excluded(path):
                    if kind != 'blob' or mode not in {'100644', '100755'}:
                        raise PreparationError('source_not_regular')
                    committed[path] = (mode, blob)
        paths = list(set(index) | set(committed))
    else:
        if (root / '.git').exists() or (root / '.git').is_symlink():
            raise PreparationError('source_git_identity_unavailable')
        paths = []
        excluded_stage = prepared.parent if prepared.parent != root else prepared
        for directory, directories, files in os.walk(root, followlinks=False):
            parent = Path(directory)
            directories[:] = [name for name in directories
                              if parent / name != excluded_stage and
                              not excluded((parent / name).relative_to(root))]
            for name in directories:
                if (parent / name).is_symlink():
                    raise PreparationError('source_symlink_present')
            paths.extend((parent / name).relative_to(root) for name in files)
    selected = []
    for relative in sorted(set(paths)):
        if relative.is_absolute() or '..' in relative.parts:
            raise PreparationError('source_path_invalid')
        if relative.name == 'override.cfg':
            raise PreparationError('source_override_present')
        if excluded(relative):
            continue
        # lstat every component before opening a selected source file.
        target = root
        for component in relative.parts:
            target /= component
            if target.is_symlink():
                raise PreparationError('source_symlink_present')
        if not ordinary(target):
            raise PreparationError('source_not_regular')
        if committed is not None:
            if relative not in committed or index.get(relative) != committed[relative]:
                raise PreparationError('source_index_differs_from_revision')
            content = target.read_bytes()
            blob = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
            if blob != committed[relative][1]:
                raise PreparationError('source_tracked_dirt')
        selected.append(relative)
    if Path('project.godot') not in selected or Path(EXTENSION) not in selected:
        raise PreparationError('required_source_missing')
    return selected, committed


def check_registry(root):
    cache = root / '.godot'
    registry = cache / 'extension_list.cfg'
    if cache.is_symlink() or registry.is_symlink():
        raise PreparationError('registry_symlink_present')
    if registry.exists():
        if not ordinary(registry):
            raise PreparationError('registry_not_regular')
        with registry.open('rb') as stream:
            if stream.read(len(REGISTRY) + 1) != REGISTRY:
                raise PreparationError('registry_unknown')


def configurations(original):
    text = original.decode('utf-8')
    sections = list(re.finditer(r'^\[editor_plugins\]\s*$', text, re.MULTILINE))
    if len(sections) != 1 or re.search(r'^\[debug\]\s*$', text, re.MULTILINE):
        raise PreparationError('configuration_unknown')
    body = re.split(r'^\[', text[sections[0].end():], maxsplit=1, flags=re.MULTILINE)[0].strip()
    if body != GUT_ENABLED or text.count(GUT_ENABLED) != 1 or re.search(r'^\s*(?:config/)?project_settings_override\s*=', text, re.MULTILINE):
        raise PreparationError('configuration_unknown')
    return ((text.replace(GUT_ENABLED, GUT_DISABLED, 1) + LOGGING).encode(),
            original + LOGGING.encode())


def verify_copy(root, hashes, expected_config):
    check_override(root)
    for name, expected in hashes.items():
        path = root / name
        if path.is_symlink() or not ordinary(path):
            raise PreparationError('prepared_source_custody_failed')
        content = path.read_bytes()
        if name == 'project.godot':
            valid = content == expected_config
        else:
            valid = hashlib.sha256(content).hexdigest() == expected
        if not valid:
            raise PreparationError('prepared_source_custody_failed')
    check_registry(root)
    if not (root / '.godot/extension_list.cfg').exists():
        raise PreparationError('prepared_registry_missing')


def child_limits():
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def import_phase(root, engine, timeout_command, seconds, environment, log):
    result = {'status': 'failed', 'exit_code': None, 'timed_out': False,
              'script_error_observed': False, 'non_script_error_observed': False,
              'output_valid': True, 'log': str(log)}
    process = None
    selector = selectors.DefaultSelector()
    pending = bytearray()
    discard = False
    total_bytes = 0

    def classify(raw):
        try:
            line = raw.decode('utf-8')
        except UnicodeError:
            result['output_valid'] = False
            return
        if '\x00' in line:
            result['output_valid'] = False
        if any(marker in line for marker in SCRIPT_MARKERS):
            result['script_error_observed'] = True
        elif 'ERROR:' in line:
            result['non_script_error_observed'] = True

    try:
        if threading.active_count() != 1:
            raise PreparationError('single_thread_launch_required')
        process = subprocess.Popen([timeout_command, '--kill-after=15s', str(seconds) + 's',
                                    engine, '--headless', '--import'], cwd=root,
                                   env=environment, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True, preexec_fn=child_limits)
        os.set_blocking(process.stdout.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + seconds + 20
        while selector.get_map() and time.monotonic() < deadline:
            for key, _ in selector.select(0.1):
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    if pending and not discard:
                        classify(bytes(pending))
                    selector.unregister(key.fileobj)
                    continue
                total_bytes += len(chunk)
                if total_bytes > 16 * 1024 * 1024:
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
        if selector.get_map():
            result['timed_out'] = True
        else:
            try:
                process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                result['timed_out'] = True
        if result['timed_out']:
            os.killpg(process.pid, signal.SIGKILL)
        result['exit_code'] = process.wait(timeout=5)
        result['timed_out'] |= result['exit_code'] in (124, 137)
        if result['exit_code'] == 0 and not result['timed_out'] and result['output_valid'] and not result['script_error_observed']:
            result['status'] = 'passed'
    finally:
        selector.close()
        if process is not None:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            process.stdout.close()
        # Canonical markers only: unknown raw stdout is never persisted.
        lines = []
        if result['script_error_observed']:
            lines.append('SCRIPT ERROR: preparation script error observed')
        if result['non_script_error_observed']:
            lines.append('ERROR: non-script engine error observed')
        lines.append('PREPARATION: ' + json.dumps({key: value for key, value in result.items() if key != 'log'}, sort_keys=True))
        if log.is_symlink():
            raise PreparationError('marker_log_path_unavailable')
        log.write_text('\n'.join(lines) + '\n')
    return result


def save_report(path, report):
    if path.is_symlink() or not path.parent.is_dir():
        raise PreparationError('report_path_unavailable')
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('x', encoding='utf-8') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')
    os.replace(temporary, path)


def prepare(args):
    source = Path(args.source_root).absolute()
    prepared = Path(args.prepared_root).absolute()
    report_path = Path(args.report).absolute()
    report = {'schema_version': 1, 'status': 'failed', 'stage': 'source',
              'source_revision': args.source_revision, 'prepared_root': str(prepared),
              'bootstrap': 'NOT_OBSERVED', 'qualification': 'NOT_OBSERVED',
              'configuration_restored': False, 'source_custody_qualified': False,
              'configuration_custody_lost': False,
              'prepared_root_created': False}
    original = None
    known_configs = set()
    hashes = {}
    committed = None
    exit_code = 2
    save_report(report_path, report)
    try:
        if threading.active_count() != 1 or threading.current_thread() is not threading.main_thread():
            raise PreparationError('single_thread_launch_required')
        # Clear inherited SIG_IGN/SA_NOCLDWAIT before even the Git subprocesses.
        signal.signal(signal.SIGCHLD, signal.SIG_DFL)
        if not re.fullmatch('[0-9a-f]{40}', args.source_revision) or not 1 <= args.timeout_seconds <= 86400:
            raise PreparationError('preparation_identity_invalid')
        if source.is_symlink() or not source.is_dir() or prepared.exists() or prepared.is_symlink():
            raise PreparationError('preparation_roots_invalid')
        if source.resolve() == prepared.resolve() or prepared.resolve() in source.resolve().parents:
            raise PreparationError('preparation_roots_overlap')
        if (source / 'override.cfg').exists() or (source / 'override.cfg').is_symlink():
            raise PreparationError('source_override_present')
        check_registry(source)
        inventory, committed = source_inventory(source.resolve(), args.source_revision, prepared)
        engine = shutil.which(args.godot)
        timeout_command = shutil.which('timeout', path='/usr/bin:/bin')
        if not engine or not timeout_command:
            raise PreparationError('preparation_dependency_unavailable')
        engine = str(Path(engine).absolute())
        report['stage'] = 'staging'
        prepared.mkdir(mode=0o700)
        report['prepared_root_created'] = True
        for relative in inventory:
            incoming = source / relative
            target = prepared / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with incoming.open('rb') as reader, target.open('xb') as writer:
                shutil.copyfileobj(reader, writer)
            target.chmod(stat.S_IMODE(incoming.stat().st_mode) | stat.S_IRUSR | stat.S_IWUSR)
            hashes[str(relative)] = hashlib.sha256(target.read_bytes()).hexdigest()
        verify_source(source, args.source_revision, hashes, committed)
        report['source_sha256'] = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
        report['source_manifest'] = hashes
        report['source_inventory_kind'] = 'git-tracked' if committed is not None else 'gitless-artifact'
        report['source_files'] = len(hashes)
        configuration = prepared / 'project.godot'
        original_candidate = configuration.read_bytes()
        bootstrap_config, qualification_config = configurations(original_candidate)
        original = original_candidate
        report['configuration_original_sha256'] = hashlib.sha256(original).hexdigest()
        known_configs = {original, bootstrap_config, qualification_config}
        cache = prepared / '.godot'
        cache.mkdir()
        (cache / 'extension_list.cfg').write_bytes(REGISTRY)
        runtime = prepared / '.preparation-runtime'
        runtime.mkdir(mode=0o700)
        environment = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8',
                       'M4_SOURCE_REVISION': args.source_revision}
        for variable, name in (('HOME', 'home'), ('XDG_DATA_HOME', 'data'),
                               ('XDG_CACHE_HOME', 'cache'), ('XDG_CONFIG_HOME', 'config')):
            directory = runtime / name
            directory.mkdir(mode=0o700)
            environment[variable] = str(directory)
        for phase, content in (('bootstrap', bootstrap_config), ('qualification', qualification_config)):
            report['stage'] = phase
            verify_source(source, args.source_revision, hashes, committed)
            verify_copy(prepared, hashes, original if phase == 'bootstrap' else bootstrap_config)
            configuration.write_bytes(content)
            verify_copy(prepared, hashes, content)
            save_report(report_path, report)
            exit_code = 1
            report[phase] = import_phase(prepared, engine, timeout_command, args.timeout_seconds,
                                         environment, report_path.parent / ('prepare-' + phase + '.log'))
            if report[phase]['script_error_observed']:
                print('SCRIPT ERROR: preparation script error observed', flush=True)
            verify_copy(prepared, hashes, content)
            save_report(report_path, report)
            if report[phase]['status'] != 'passed':
                break
        else:
            report['status'] = 'passed'
            exit_code = 0
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError) as error:
        report['failure_class'] = str(error) if isinstance(error, PreparationError) else type(error).__name__
        report['status'] = 'failed'
    finally:
        if original is not None:
            try:
                configuration = prepared / 'project.godot'
                check_override(prepared)
                if configuration.is_symlink() or not ordinary(configuration) or configuration.read_bytes() not in known_configs:
                    report['configuration_custody_lost'] = True
                    raise PreparationError('configuration_unknown_edit_preserved')
                configuration.write_bytes(original)
                verify_copy(prepared, hashes, original)
                verify_source(source, args.source_revision, hashes, committed)
                report['configuration_restored'] = True
                report['source_custody_qualified'] = True
            except (OSError, ValueError) as error:
                report['status'] = 'failed'
                # The caller preserves an unqualified stage for review rather
                # than deleting potentially unknown changes after custody loss.
                report['configuration_custody_lost'] = True
                report['failure_class'] = str(error) if isinstance(error, PreparationError) else type(error).__name__
                exit_code = 1
        report['exit_code'] = exit_code
        save_report(report_path, report)
    return exit_code


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-root', 'prepared-root', 'godot', 'source-revision', 'report'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--timeout-seconds', required=True, type=int)
    arguments = parser.parse_args()
    try:
        raise SystemExit(prepare(arguments))
    except (OSError, ValueError):
        # Evidence failure itself cannot produce a passing preparation result.
        raise SystemExit(2)
