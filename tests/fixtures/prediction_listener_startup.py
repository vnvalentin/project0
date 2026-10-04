"""Single-purpose owned listener consumer. Emits closed booleans/enums only."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import stat
import subprocess
import sys
import time

class ExpectedListenErrors:
    BEGIN = '1450_LISTENER_ERROR_BEGIN:occupied_default'
    END = '1450_LISTENER_ERROR_END:occupied_default'
    NATIVE_ERROR = "ERROR: Couldn't create an ENet host."
    NATIVE_FRAME = 'at: _create (modules/enet/enet_connection.cpp:318)'
    SERVER_FRAME = 'at: _start_server (res://server/server_main.gd:569)'
    STEP_KEYS = ('begin_seen','native_error_seen','native_frame_seen',
                 'server_error_seen','server_frame_seen','end_seen')
    REJECT_STAGES = ('WAIT_BEGIN','WAIT_NATIVE_ERROR','WAIT_NATIVE_FRAME',
                     'WAIT_SERVER_ERROR','WAIT_SERVER_FRAME','WAIT_END','COMPLETE')
    REJECT_CLASSES = ('NONE','SCRIPT','ERROR','FRAME','PHASE','BOUND','UNKNOWN')

    def __init__(self, held_port):
        if type(held_port) is not int or not 1 <= held_port <= 65535:
            raise ValueError('owned_listener_input_unqualified')
        # Source-pinned literal: loopback and Error.ERR_CANT_CREATE(20).
        self.server_error = 'ERROR: Server failed to listen on 127.0.0.1:%d: 20' % held_port
        self.stage = 0
        self.rejected = False
        self.empty_phase = False
        self.native_frame_qualified = False
        self.server_frame_qualified = False
        self.seen = dict.fromkeys(self.STEP_KEYS, False)
        self.first_reject_stage = 'NONE'
        self.first_reject_class = 'NONE'

    def reject_diagnostic(self, category):
        # Separate observations only; the strict original verdict remains rejected.
        self.rejected = True
        if self.first_reject_class == 'NONE':
            self.first_reject_stage = ('COMPLETE' if self.empty_phase else self.REJECT_STAGES[self.stage])
            self.first_reject_class = category if category in self.REJECT_CLASSES else 'UNKNOWN'

    def diagnostic(self, child_exit, outcome):
        if child_exit not in ('NOT_OBSERVED','EXITED_ONE','EXITED_ZERO','SIGNALLED','OTHER') \
                or outcome not in ('precondition_failed','startup_unqualified','custody_failed','red_observed','listener_ready'):
            raise ValueError('diagnostic_unqualified')
        return {**self.seen,'first_reject_stage':self.first_reject_stage,
                'first_reject_class':self.first_reject_class,'child_exit':child_exit,'outcome':outcome}

    def observe(self, line):
        if type(line) is not str or len(line) > 512:
            self.reject_diagnostic('BOUND')
            return
        text = line.strip()
        expected = (self.BEGIN, self.NATIVE_ERROR, self.NATIVE_FRAME,
                    self.server_error, self.SERVER_FRAME, self.END)
        for key, literal in zip(self.STEP_KEYS, expected):
            if text == literal:
                self.seen[key] = True
        category = ('SCRIPT' if any(value in text for value in ('SCRIPT ERROR','Parse Error','Compile Error'))
                    else 'ERROR' if 'ERROR:' in text else 'FRAME' if text.startswith('at:')
                    else 'PHASE' if text.startswith('1450_LISTENER_ERROR_') else 'UNKNOWN')
        diagnostic = (text.startswith('1450_LISTENER_ERROR_') or 'ERROR:' in text
                      or 'SCRIPT ERROR' in text or 'Parse Error' in text or 'Compile Error' in text
                      or text.startswith('at:'))
        if self.empty_phase:
            if diagnostic:
                self.reject_diagnostic(category)
            return
        if self.stage == 1 and text == self.END:
            self.empty_phase = True
            return
        if self.stage < len(expected) and text == expected[self.stage]:
            if text == self.NATIVE_FRAME:
                self.native_frame_qualified = True
            elif text == self.SERVER_FRAME:
                self.server_frame_qualified = True
            self.stage += 1
            return
        if diagnostic:
            self.reject_diagnostic(category)

    def finish(self, child_exit_code, ready_observed):
        return {'qualified': not self.rejected and not self.empty_phase and self.stage == 6
                and type(child_exit_code) is int and child_exit_code == 1 and ready_observed is False,
                'native_frame_qualified': self.native_frame_qualified,
                'server_frame_qualified': self.server_frame_qualified,
                'phase_complete': self.empty_phase or self.stage == 6,
                'unexpected_error_observed': self.rejected}

SOURCE_FILES = (
    'server/server_main.gd',
    'tests/fixtures/prediction_listener_ready.gd',
    'tests/fixtures/prediction_listener_server.gd',
    'tests/fixtures/prediction_listener_startup.py',
)
READY_MARKER = '1450_LISTENER_READY'
REPORT = {
    'schema_version': 1, 'outcome': 'precondition_failed',
    'source_qualified': False, 'run_qualified': False,
    'held_port_owned': None, 'child_started': None, 'pidfd_qualified': None,
    'ready_observed': None, 'ready_qualified': None,
    'listener_live': None, 'listener_owned': None,
    'capture_qualified': None, 'released_listener_rebound': None,
    'intended_bind_failure': False, 'unexpected_error_observed': False,
    'child_exit': 'NOT_OBSERVED', 'child_reaped': None,
    'resources_released': None, 'temp_removed': None,
    'qualified_red': False, 'qualified_green': False,
    'historical_cause': 'UNKNOWN',
}


class QuietArguments(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError('input_unqualified')


def ordinary_directory(path):
    if not path.is_absolute() or str(path) == '/' or path != Path(os.path.normpath(path)):
        raise ValueError('directory_unqualified')
    for parent in (path, *path.parents):
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError('directory_unqualified')


def ordinary_bytes(path, limit):
    ordinary_directory(path.parent)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= limit:
        raise ValueError('file_unqualified')
    with path.open('rb') as stream:
        data = stream.read(limit + 1)
    now = path.lstat()
    before = (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_uid, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
    after = (now.st_dev, now.st_ino, now.st_mode, now.st_nlink, now.st_uid, now.st_size, now.st_mtime_ns, now.st_ctime_ns)
    if len(data) != info.st_size or before != after:
        raise ValueError('file_changed')
    return data


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('record_unqualified')
        result[key] = value
    return result


def source_matches(project, hashes):
    if type(hashes) is not dict or set(hashes) != set(SOURCE_FILES):
        return False
    for relative in SOURCE_FILES:
        digest = hashes[relative]
        if type(digest) is not str or not re.fullmatch('[0-9a-f]{64}', digest):
            return False
        if hashlib.sha256(ordinary_bytes(project / relative, 1048576)).hexdigest() != digest:
            return False
    return True


def ready_record(path, run_id, revision):
    data = ordinary_bytes(path, 512)
    value = json.loads(data, object_pairs_hook=no_duplicate_keys)
    if type(value) is not dict or set(value) != {'schema_version', 'run_id', 'source_revision', 'state', 'port'}:
        raise ValueError('ready_unqualified')
    if type(value['schema_version']) is not int or value['schema_version'] != 1 \
            or value['run_id'] != run_id or value['source_revision'] != revision or value['state'] != 'ready' \
            or type(value['port']) is not int or not 1 <= value['port'] <= 65535:
        raise ValueError('ready_unqualified')
    canonical = json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    if data != canonical:
        raise ValueError('ready_unqualified')
    return data, value['port']


def exit_label(code):
    if code is None:
        return 'NOT_OBSERVED'
    if code == 0:
        return 'EXITED_ZERO'
    if code == 1:
        return 'EXITED_ONE'
    if code < 0:
        return 'SIGNALLED'
    return 'OTHER'


def directory_identity(path):
    ordinary_directory(path)
    info = path.lstat()
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid)


def freeze_runtime(root, created, user_relative):
    # Closed layout, bounded iterator: no recursive materialization or basename
    # exception that could admit a database in an unrelated directory.
    result = {}
    allowed_files = {Path('ready/ready.json'), Path('ready/ready.pending')}
    for name in ('accounts.db', 'telemetry.db'):
        for suffix in ('', '-wal', '-shm', '-journal'):
            allowed_files.add(user_relative / (name + suffix))
    for directory, identity in created.items():
        if directory_identity(directory) != identity or identity[3] != os.getuid():
            raise ValueError('runtime_changed')
        info = directory.lstat()
        result[directory] = (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns)
        with os.scandir(directory) as entries:
            count = 0
            for entry in entries:
                count += 1
                if count > 32:
                    raise ValueError('runtime_unqualified')
                path = directory / entry.name
                if path in created:
                    if directory_identity(path) != created[path]:
                        raise ValueError('runtime_changed')
                    continue
                relative = path.relative_to(root)
                file_info = path.lstat()
                if relative not in allowed_files or not stat.S_ISREG(file_info.st_mode) \
                        or file_info.st_uid != os.getuid() or file_info.st_nlink != 1:
                    raise ValueError('runtime_unqualified')
                result[path] = (file_info.st_dev, file_info.st_ino, file_info.st_mode, file_info.st_size, file_info.st_mtime_ns)
    return result


def remove_runtime(root, frozen, created, user_relative):
    if freeze_runtime(root, created, user_relative) != frozen:
        return False
    for path in sorted(frozen, key=lambda p: len(p.parts), reverse=True):
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            # Removing owned children changes directory size/time, not identity.
            if (info.st_dev, info.st_ino, info.st_mode) != frozen[path][:3]:
                return False
            path.rmdir()
        else:
            if (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns) != frozen[path]:
                return False
            path.unlink()
    return not os.path.lexists(root)


def retain_diagnostic(parent, parent_identity, args, hashes, result, reducer):
    # One fixed private leaf outside the preserved inner runtime. Unknown state
    # is never traversed, copied or deleted; failed retention preserves it.
    if directory_identity(parent) != parent_identity:
        raise ValueError('diagnostic_parent_unqualified')
    path = parent / '1450-listener-diagnostic.json'
    payload = json.dumps({
        'schema_version':1,'source_revision':args.source_revision,'run_id':args.run_id,
        'source_hashes':hashes,'report':dict(result),
        'diagnostic':reducer.diagnostic(result['child_exit'],result['outcome']),
    },sort_keys=True,separators=(',',':')).encode()
    if len(payload) > 4096:
        raise ValueError('diagnostic_unqualified')
    descriptor = os.open(path,os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,0o600)
    with os.fdopen(descriptor,'wb') as stream:
        if stream.write(payload) != len(payload):
            raise ValueError('diagnostic_unqualified')
        stream.flush()
        os.fsync(stream.fileno())
        info = os.fstat(stream.fileno())
        identity = (info.st_dev,info.st_ino,info.st_mode,info.st_uid,info.st_nlink,
                    info.st_size,info.st_mtime_ns,info.st_ctime_ns)
    if not stat.S_ISREG(identity[2]) or identity[3] != os.getuid() \
            or identity[4] != 1 or stat.S_IMODE(identity[2]) != 0o600 \
            or directory_identity(parent) != parent_identity:
        raise ValueError('diagnostic_unqualified')
    descriptor = os.open(path,os.O_RDONLY | os.O_NOFOLLOW)
    try:
        current = os.fstat(descriptor)
        before = (current.st_dev,current.st_ino,current.st_mode,current.st_uid,current.st_nlink,
                  current.st_size,current.st_mtime_ns,current.st_ctime_ns)
        if before != identity:
            raise ValueError('diagnostic_changed')
        data = os.read(descriptor,4097)
        current = os.fstat(descriptor)
        after = (current.st_dev,current.st_ino,current.st_mode,current.st_uid,current.st_nlink,
                 current.st_size,current.st_mtime_ns,current.st_ctime_ns)
        if data != payload or before != after or directory_identity(parent) != parent_identity:
            raise ValueError('diagnostic_changed')
    finally:
        os.close(descriptor)


def run(args):
    result = dict(REPORT)
    process = None
    pidfd = None
    holder = None
    runtime = None
    reducer = None
    ready_data = None
    ready_port = None
    code = None
    marker_seen = False
    buffer = bytearray()
    total = 0
    failed = False
    created = {}
    user_relative = None
    parent_identity = None
    prerequisite = None
    def observe_line(raw):
        nonlocal marker_seen
        if len(raw) > 512:
            reducer.reject_diagnostic('BOUND')
            raise ValueError('line_unqualified')
        try:
            line = raw.decode('utf-8', errors='strict')
        except UnicodeError:
            reducer.reject_diagnostic('UNKNOWN')
            raise ValueError('line_unqualified')
        if line.strip() == READY_MARKER:
            if marker_seen or not reducer.finish(None, None)['phase_complete']:
                raise ValueError('publication_unqualified')
            marker_seen = True
        reducer.observe(line)

    def observe_available(wait_seconds):
        nonlocal total
        readable, _, _ = select.select([process.stdout], [], [], wait_seconds)
        if not readable:
            return
        data = os.read(process.stdout.fileno(), 4096)
        total += len(data)
        if total > 1048576:
            reducer.reject_diagnostic('BOUND')
            raise ValueError('output_unqualified')
        buffer.extend(data)
        while b'\n' in buffer:
            raw, _, rest = buffer.partition(b'\n')
            buffer[:] = rest
            observe_line(raw)
        if len(buffer) > 512:
            reducer.reject_diagnostic('BOUND')
            raise ValueError('line_unqualified')

    try:
        if sys.platform != 'linux' or not hasattr(os, 'pidfd_open') or not hasattr(signal, 'pidfd_send_signal'):
            raise ValueError('owner_unqualified')
        if not re.fullmatch('[A-Za-z0-9_-]{1,128}', args.run_id):
            raise ValueError('run_unqualified')
        result['run_qualified'] = True
        if not re.fullmatch('[0-9a-f]{40}', args.source_revision) \
                or os.environ.get('M4_SOURCE_REVISION') != args.source_revision:
            raise ValueError('source_unqualified')
        project = Path(args.project_root)
        parent = Path(args.runtime_parent)
        engine = Path(args.godot)
        ordinary_directory(project)
        ordinary_directory(parent)
        parent_identity = directory_identity(parent)
        prerequisite = parent / "1450-listener-prerequisite.json"
        if os.path.lexists(prerequisite):
            raise ValueError("prerequisite_preexists")
        ordinary_directory(engine.parent)
        if not stat.S_ISREG(engine.lstat().st_mode):
            raise ValueError('engine_unqualified')
        if len(args.source_hashes_base64) > 4096 or not re.fullmatch('[A-Za-z0-9_-]{1,128}', args.userdir_leaf):
            raise ValueError('input_unqualified')
        hashes = json.loads(base64.b64decode(args.source_hashes_base64, validate=True), object_pairs_hook=no_duplicate_keys)
        if not source_matches(project, hashes):
            raise ValueError('source_unqualified')
        result['source_qualified'] = True
        runtime = parent / ('prediction-listener-' + args.run_id)
        if os.path.lexists(runtime):
            runtime = None
            raise ValueError('runtime_preexists')
        runtime.mkdir(mode=0o700)
        created[runtime] = directory_identity(runtime)
        for leaf in ('home', 'data', 'config', 'cache', 'ready'):
            (runtime / leaf).mkdir(mode=0o700)
            created[runtime / leaf] = directory_identity(runtime / leaf)
        user_relative = Path('data/godot/app_userdata') / args.userdir_leaf
        for relative in (Path('data/godot'), Path('data/godot/app_userdata'), user_relative):
            (runtime / relative).mkdir(mode=0o700)
            created[runtime / relative] = directory_identity(runtime / relative)
        holder = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        holder.bind(('127.0.0.1', 0))
        held_port = holder.getsockname()[1]
        result['held_port_owned'] = 1 <= held_port <= 65535
        reducer = ExpectedListenErrors(held_port)
        env = {
            'HOME': str(runtime / 'home'), 'XDG_DATA_HOME': str(runtime / 'data'),
            'XDG_CONFIG_HOME': str(runtime / 'config'), 'XDG_CACHE_HOME': str(runtime / 'cache'),
            'PATH': '/usr/local/bin:/usr/bin:/bin', 'LANG': 'C.UTF-8',
            'M4_SOURCE_REVISION': args.source_revision,
            'PROJECT0_OPERATOR_CONTROL_PORT': '0', 'PROJECT0_ACCOUNTS_DB_PATH': 'accounts.db',
            'PROJECT0_TELEMETRY_DB_PATH': 'telemetry.db',
        }
        argv = [str(engine), '--headless', '--path', str(project), '-s',
                'tests/fixtures/prediction_listener_server.gd', '--',
                '--server-bind-address=127.0.0.1', '--server-port=' + str(held_port),
                '--listener-ready-root=' + str(runtime / 'ready'),
                '--listener-run-id=' + args.run_id, '--listener-source-revision=' + args.source_revision,
                '--listener-user-directory=' + str(runtime / user_relative)]
        freeze_runtime(runtime, created, user_relative)
        signal.signal(signal.SIGCHLD, signal.SIG_DFL)
        process = subprocess.Popen(argv, cwd=project, env=env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
                                   start_new_session=True)
        result['child_started'] = True
        pidfd = os.pidfd_open(process.pid)
        result['pidfd_qualified'] = True
        os.set_blocking(process.stdout.fileno(), False)

        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            observe_available(min(0.05, max(0, deadline - time.monotonic())))
            result['ready_observed'] = os.path.lexists(runtime / 'ready' / 'ready.json')
            if marker_seen:
                ready_data, ready_port = ready_record(runtime / 'ready' / 'ready.json', args.run_id, args.source_revision)
                result['ready_qualified'] = True
                result['listener_live'] = not select.select([pidfd], [], [], 0)[0] and process.poll() is None
                if not result['listener_live'] or ready_port == held_port:
                    raise ValueError('listener_unqualified')
                signal.pidfd_send_signal(pidfd, 0)
                probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                try:
                    probe.bind(('127.0.0.1', ready_port))
                    result['listener_owned'] = False
                except OSError as error:
                    result['listener_owned'] = error.errno == 98
                finally:
                    probe.close()
                if not result['listener_owned']:
                    raise ValueError('listener_unqualified')
                if ordinary_bytes(runtime / 'ready' / 'ready.json', 512) != ready_data:
                    raise ValueError('ready_changed')
                if select.select([pidfd], [], [], 0)[0] or process.poll() is not None:
                    result['listener_live'] = False
                    raise ValueError('listener_unqualified')
                signal.pidfd_send_signal(pidfd, 0)
                result['outcome'] = 'listener_ready'
                break
            if process.poll() is not None:
                code = process.wait(timeout=0)
                break
        if not marker_seen and code is None:
            raise ValueError('startup_unqualified')
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        failed = True
        result['outcome'] = 'startup_unqualified'
    finally:
        if process is not None:
            cleanup_deadline = time.monotonic() + 5
            try:
                if process.poll() is None:
                    if pidfd is None:
                        # Still our unreaped direct Popen child. A failed pidfd
                        # acquisition never qualifies the attempt, but must reap.
                        process.terminate()
                    else:
                        signal.pidfd_send_signal(pidfd, signal.SIGTERM)
                    try:
                        code = process.wait(timeout=max(0.01, cleanup_deadline - time.monotonic() - 1))
                    except subprocess.TimeoutExpired:
                        if pidfd is None:
                            process.kill()
                        else:
                            signal.pidfd_send_signal(pidfd, signal.SIGKILL)
                        code = process.wait(timeout=max(0.01, cleanup_deadline - time.monotonic()))
                else:
                    code = process.wait(timeout=0)
                result['child_reaped'] = True
                # EOF after reaping; only bounded known classifications survive.
                while True:
                    data = os.read(process.stdout.fileno(), 4096)
                    if not data:
                        break
                    buffer.extend(data)
                    total += len(data)
                    if total > 1048576:
                        reducer.reject_diagnostic('BOUND')
                        raise ValueError('output_unqualified')
                if buffer:
                    for raw in buffer.splitlines():
                        observe_line(raw)
                    buffer.clear()
                result['capture_qualified'] = not failed
            except (OSError, ValueError, TypeError, subprocess.SubprocessError):
                failed = True
                result['capture_qualified'] = False
                result['outcome'] = 'custody_failed'
            if process.stdout is not None:
                process.stdout.close()
        if pidfd is not None:
            os.close(pidfd)
        result['child_exit'] = exit_label(code)
        if holder is not None:
            holder.close()
        result['resources_released'] = result['child_reaped'] is True and holder is not None and holder.fileno() == -1
        if runtime is not None:
            result['ready_observed'] = os.path.lexists(runtime / 'ready' / 'ready.json')
        if reducer is not None:
            proof = reducer.finish(code, result['ready_observed'])
            result['intended_bind_failure'] = proof['qualified']
            result['unexpected_error_observed'] = proof['unexpected_error_observed']
            result['qualified_red'] = proof['qualified'] and result['source_qualified'] is True \
                and result['run_qualified'] is True and result['held_port_owned'] is True \
                and result['child_started'] is True and result['pidfd_qualified'] is True \
                and result['resources_released'] is True and result['capture_qualified'] is True \
                and result['outcome'] != 'custody_failed'
            result['qualified_green'] = result['ready_qualified'] is True and result['listener_live'] is True \
                and result['listener_owned'] is True and proof['phase_complete'] is True \
                and proof['native_frame_qualified'] is False and proof['server_frame_qualified'] is False \
                and proof['unexpected_error_observed'] is False and result['pidfd_qualified'] is True \
                and result['resources_released'] is True and result['capture_qualified'] is True \
                and code in (0, -signal.SIGTERM) and result['outcome'] == 'listener_ready'
        try:
            if result['source_qualified'] and not source_matches(project, hashes):
                result['source_qualified'] = False
            if ready_data is not None and ordinary_bytes(runtime / 'ready' / 'ready.json', 512) != ready_data:
                raise ValueError('ready_changed')
            if result['source_qualified'] and (result['qualified_red'] or result['qualified_green']):
                if ready_port is not None:
                    released = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    try:
                        result['released_listener_rebound'] = False
                        released.bind(('127.0.0.1', ready_port))
                        result['released_listener_rebound'] = True
                    finally:
                        released.close()
                frozen = freeze_runtime(runtime, created, user_relative)
                if result['qualified_red']:
                    result['outcome'] = 'red_observed'
                private_proof = {
                    'schema_version': 1, 'source_revision': args.source_revision,
                    'run_id': args.run_id, 'source_hashes': hashes,
                    'ready_sha256': hashlib.sha256(ready_data).hexdigest() if ready_data is not None else None,
                    'report': dict(result),
                }
                proof_bytes = json.dumps(private_proof, sort_keys=True, separators=(',', ':')).encode()
                if len(proof_bytes) > 4096 or directory_identity(parent) != parent_identity:
                    raise ValueError('prerequisite_unqualified')
                descriptor = os.open(prerequisite, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(descriptor, 'wb') as stream:
                    if stream.write(proof_bytes) != len(proof_bytes):
                        raise ValueError('prerequisite_unqualified')
                    stream.flush()
                    os.fsync(stream.fileno())
                proof_info = prerequisite.lstat()
                proof_identity = (proof_info.st_dev, proof_info.st_ino, proof_info.st_mode,
                                  proof_info.st_uid, proof_info.st_nlink)
                if not stat.S_ISREG(proof_info.st_mode) or proof_info.st_uid != os.getuid() \
                        or proof_info.st_nlink != 1 or ordinary_bytes(prerequisite, 4096) != proof_bytes \
                        or directory_identity(parent) != parent_identity:
                    raise ValueError('prerequisite_unqualified')
                # Retain the source/run-bound proof outside the deletable inner
                # runtime. Cleanup is an explicit later completion transition.
                result['temp_removed'] = remove_runtime(runtime, frozen, created, user_relative)
                now = prerequisite.lstat()
                if (now.st_dev, now.st_ino, now.st_mode, now.st_uid, now.st_nlink) != proof_identity \
                        or ordinary_bytes(prerequisite, 4096) != proof_bytes \
                        or directory_identity(parent) != parent_identity:
                    raise ValueError('prerequisite_changed')
            if result['temp_removed'] is not True:
                result['qualified_red'] = False
                result['qualified_green'] = False
            if result['qualified_red']:
                result['outcome'] = 'red_observed'
        except (OSError, ValueError, TypeError, KeyError):
            result['qualified_red'] = False
            result['qualified_green'] = False
            result['outcome'] = 'custody_failed'
    # Diagnostic retention is separate from admission and does not change the
    # fixed report or cleanup outcome. Qualified runs never create this leaf.
    if reducer is not None and parent_identity is not None \
            and result['source_qualified'] is True and result['run_qualified'] is True \
            and result['child_started'] is True and prerequisite is not None \
            and not os.path.lexists(prerequisite) and result['temp_removed'] is not True \
            and result['qualified_red'] is False and result['qualified_green'] is False:
        try:
            if source_matches(project,hashes):
                retain_diagnostic(parent,parent_identity,args,hashes,result,reducer)
        except (OSError,ValueError,TypeError,KeyError):
            pass
    return result


def main():
    result = dict(REPORT)
    try:
        parser = QuietArguments(add_help=False)
        for name in ('godot', 'project-root', 'runtime-parent', 'source-revision', 'run-id', 'source-hashes-base64', 'userdir-leaf'):
            parser.add_argument('--' + name, required=True)
        result = run(parser.parse_args())
    except (OSError, ValueError, TypeError, KeyError):
        pass
    print(json.dumps(result, sort_keys=True, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
