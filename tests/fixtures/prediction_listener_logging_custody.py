"""Root-owned copied filesystem custody controls; no engine, child or socket."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
import types

CONSUMER = None
CONSUMER_SHA = 'e6e843400b254a39e1c9365e942d04fa683d359090b55473234a5513aa844f74'


class LoggingCustodyControls(unittest.TestCase):
    def setUp(self):
        acquired = tempfile.TemporaryDirectory(prefix='project0-1450-log-custody.')
        custody = {'chain': None}
        # The callback binds this acquisition, never later mutable self state.
        self.addCleanup(self.cleanup_case, acquired, custody)
        self.case = Path(acquired.name)
        custody['chain'] = self.case_chain(self.case)
        self.root = self.case / 'runtime'
        self.user_relative = Path('data/godot/app_userdata/Project0')
        self.root.mkdir(mode=0o700)
        self.created = {self.root: CONSUMER.directory_identity(self.root)}
        for relative in ('home', 'data', 'config', 'cache', 'ready',
                         'data/godot', 'data/godot/app_userdata',
                         'data/godot/app_userdata/Project0',
                         'data/godot/app_userdata/Project0/logs'):
            directory = self.root / relative
            directory.mkdir(mode=0o700)
            self.created[directory] = CONSUMER.directory_identity(directory)
        self.logs = self.root / self.user_relative / 'logs'
        self.log = self.logs / 'godot.log'
        self.outside = self.case / 'outside'
        self.outside.mkdir(mode=0o700)
        self.sentinel = self.outside / 'known-bytes'
        self.sentinel.write_bytes(b'outside synthetic bytes')

    @staticmethod
    def case_chain(path):
        values = []
        for parent in (*reversed(path.parents), path):
            info = parent.lstat()
            if not stat.S_ISDIR(info.st_mode):
                raise AssertionError('synthetic_custody_unqualified')
            values.append((info.st_dev, info.st_ino, info.st_mode, info.st_uid))
        if path.lstat().st_uid != os.getuid():
            raise AssertionError('synthetic_custody_unqualified')
        return values

    @classmethod
    def cleanup_case(cls, acquired, custody):
        path = Path(acquired.name)
        try:
            if custody['chain'] is None or cls.case_chain(path) != custody['chain']:
                raise AssertionError('synthetic_custody_unqualified')
        except (OSError, AssertionError):
            acquired._finalizer.detach()
            raise
        # Only this declared synthetic case is recovered after preservation
        # assertions; no consumer failure authorizes deletion of real state.
        acquired.cleanup()
        if os.path.lexists(path):
            raise AssertionError('synthetic_cleanup_unqualified')

    def freeze(self):
        return CONSUMER.freeze_runtime(self.root, self.created, self.user_relative)

    def test_exact_owned_log_is_frozen_and_removed_with_the_owned_tree(self):
        self.log.write_bytes(b'known synthetic log')
        try:
            frozen = self.freeze()
        except ValueError:
            frozen = None
        self.assertIsNotNone(frozen, '1450 exact default log is accepted by owned custody')
        self.assertIn(self.log, frozen)
        self.assertTrue(CONSUMER.remove_runtime(self.root, frozen, self.created, self.user_relative))
        self.assertFalse(os.path.lexists(self.root))
        self.assertEqual(self.sentinel.read_bytes(), b'outside synthetic bytes')

    def test_logging_absent_still_qualifies_empty_precreated_directory(self):
        self.assertFalse(os.path.lexists(self.log))
        frozen = self.freeze()
        self.assertTrue(CONSUMER.remove_runtime(self.root, frozen, self.created, self.user_relative))
        self.assertFalse(os.path.lexists(self.root))

    def test_extra_log_member_rejects_and_preserves_all_bytes(self):
        self.log.write_bytes(b'known synthetic log')
        extra = self.logs / 'godot.previous.log'
        extra.write_bytes(b'unknown synthetic member')
        with self.assertRaises(ValueError):
            self.freeze()
        self.assertEqual(extra.read_bytes(), b'unknown synthetic member')
        self.assertEqual(self.log.read_bytes(), b'known synthetic log')

    def test_replaced_precreated_directory_rejects_and_preserves_replacement(self):
        self.logs.rename(self.case / 'known-old-logs')
        self.logs.mkdir(mode=0o700)
        self.log.write_bytes(b'replacement synthetic bytes')
        with self.assertRaises(ValueError):
            self.freeze()
        self.assertEqual(self.log.read_bytes(), b'replacement synthetic bytes')
        self.assertTrue((self.case / 'known-old-logs').is_dir())

    def test_symlink_log_file_rejects_and_preserves_outside_bytes(self):
        self.log.symlink_to(self.sentinel)
        with self.assertRaises(ValueError):
            self.freeze()
        self.assertTrue(self.log.is_symlink())
        self.assertEqual(self.sentinel.read_bytes(), b'outside synthetic bytes')

    def test_symlink_log_directory_rejects_and_preserves_outside_bytes(self):
        self.logs.rmdir()
        self.logs.symlink_to(self.outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.freeze()
        self.assertTrue(self.logs.is_symlink())
        self.assertEqual(self.sentinel.read_bytes(), b'outside synthetic bytes')

    def test_hardlinked_log_file_rejects_and_preserves_both_links(self):
        os.link(self.sentinel, self.log)
        with self.assertRaises(ValueError):
            self.freeze()
        self.assertEqual(self.log.read_bytes(), b'outside synthetic bytes')
        self.assertEqual(self.sentinel.read_bytes(), b'outside synthetic bytes')
        self.assertEqual(self.sentinel.stat().st_nlink, 2)

    def test_same_basename_in_foreign_namespace_rejects_and_preserves_bytes(self):
        foreign = self.root / 'cache/godot.log'
        foreign.write_bytes(b'foreign synthetic namespace')
        with self.assertRaises(ValueError):
            self.freeze()
        self.assertEqual(foreign.read_bytes(), b'foreign synthetic namespace')

    def test_changed_log_after_freeze_rejects_cleanup_and_preserves_tree(self):
        self.log.write_bytes(b'original')
        frozen = self.freeze()
        self.log.write_bytes(b'changed synthetic bytes')
        self.assertFalse(CONSUMER.remove_runtime(self.root, frozen, self.created, self.user_relative))
        self.assertTrue(self.root.is_dir())
        self.assertEqual(self.log.read_bytes(), b'changed synthetic bytes')

    def test_replaced_log_after_freeze_rejects_cleanup_and_preserves_tree(self):
        self.log.write_bytes(b'original')
        frozen = self.freeze()
        replacement = self.logs / 'known-synthetic-replacement'
        replacement.write_bytes(b'replacement')
        replacement.replace(self.log)
        self.assertFalse(CONSUMER.remove_runtime(self.root, frozen, self.created, self.user_relative))
        self.assertTrue(self.root.is_dir())
        self.assertEqual(self.log.read_bytes(), b'replacement')


class QuietResult(unittest.TestResult):
    def __init__(self):
        super().__init__()
        self.failures_seen = 0
        self.errors_seen = 0
        self.skips_seen = 0

    def addFailure(self, test, error):
        self.failures_seen += 1

    def addError(self, test, error):
        self.errors_seen += 1

    def addSkip(self, test, reason):
        self.skips_seen += 1

    def addSubTest(self, test, subtest, error):
        if error is not None:
            if issubclass(error[0], test.failureException):
                self.addFailure(test, error)
            else:
                self.addError(test, error)


def consumer_source_bytes(path):
    parents = LoggingCustodyControls.case_chain(path.parent)
    info = path.lstat()
    identity = (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_nlink,
                info.st_size, info.st_mtime_ns, info.st_ctime_ns)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 \
            or not 0 < info.st_size <= 131072:
        raise ValueError('controls_source_unqualified')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_mode, opened.st_uid, opened.st_nlink,
                opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) != identity:
            raise ValueError('controls_source_unqualified')
        data = stream.read(131073)
        ended = os.fstat(stream.fileno())
        if (ended.st_dev, ended.st_ino, ended.st_mode, ended.st_uid, ended.st_nlink,
                ended.st_size, ended.st_mtime_ns, ended.st_ctime_ns) != identity:
            raise ValueError('controls_source_changed')
    after = path.lstat()
    if len(data) != info.st_size or (after.st_dev, after.st_ino, after.st_mode, after.st_uid,
            after.st_nlink, after.st_size, after.st_mtime_ns, after.st_ctime_ns) != identity \
            or LoggingCustodyControls.case_chain(path.parent) != parents:
        raise ValueError('controls_source_changed')
    return data


def run_logging_custody_controls():
    global CONSUMER
    result = {'schema_version': 1, 'passed': False, 'tests': 0, 'failures': 0,
              'errors': 0, 'skips': 0, 'cleanup_verified': False,
              'source_qualified': False}
    acquired = None
    custody = None
    consumer_bytes = None
    old_tempdir = tempfile.tempdir
    old_bytecode = sys.dont_write_bytecode
    old_out, old_err = sys.stdout, sys.stderr
    saved_fds = []
    operation_qualified = False
    try:
        if len(sys.argv) != 1:
            raise ValueError('fixed_controls_only')
        # Quiet both Python and descriptor output before loading the one
        # pinned local source or running tests; error objects are never saved.
        with open(os.devnull, 'w') as sink:
            try:
                sys.stdout = sys.stderr = sink
                for descriptor in (1, 2):
                    saved_fds.append((descriptor, os.dup(descriptor)))
                    os.dup2(sink.fileno(), descriptor)
                sys.dont_write_bytecode = True
                acquired = tempfile.TemporaryDirectory(prefix='project0-1450-log-controls.')
                parent = Path(acquired.name)
                custody = LoggingCustodyControls.case_chain(parent)
                tempfile.tempdir = str(parent)
                consumer_path = Path(__file__).with_name('prediction_listener_startup.py')
                consumer_bytes = consumer_source_bytes(consumer_path)
                if hashlib.sha256(consumer_bytes).hexdigest() != CONSUMER_SHA:
                    raise ValueError('controls_source_unqualified')
                CONSUMER = types.ModuleType('fixed_listener_custody_consumer')
                CONSUMER.__file__ = str(consumer_path)
                exec(compile(consumer_bytes, '<fixed-listener-custody-consumer>', 'exec'), CONSUMER.__dict__)
                suite = unittest.defaultTestLoader.loadTestsFromTestCase(LoggingCustodyControls)
                if suite.countTestCases() != 10:
                    raise ValueError('controls_inventory_unqualified')
                observed = QuietResult()
                suite.run(observed)
                result.update(tests=observed.testsRun, failures=observed.failures_seen,
                              errors=observed.errors_seen, skips=observed.skips_seen)
                if consumer_source_bytes(consumer_path) != consumer_bytes:
                    raise ValueError('controls_source_changed')
                result['source_qualified'] = True
            finally:
                tempfile.tempdir = old_tempdir
                sys.dont_write_bytecode = old_bytecode
                restored = True
                for descriptor, saved in reversed(saved_fds):
                    try:
                        os.dup2(saved, descriptor)
                    except OSError:
                        restored = False
                    finally:
                        try:
                            os.close(saved)
                        except OSError:
                            restored = False
                sys.stdout, sys.stderr = old_out, old_err
                if not restored:
                    raise ValueError('controls_output_unqualified')
        operation_qualified = True
    except Exception:
        # Boundary output is fixed even for an unexpected setup/test failure.
        # No exception text, trace, file contents or physical paths escape.
        pass
    finally:
        if acquired is not None:
            parent = Path(acquired.name)
            try:
                if custody is None or LoggingCustodyControls.case_chain(parent) != custody:
                    raise ValueError('synthetic_custody_unqualified')
                if any(parent.iterdir()):
                    raise ValueError('synthetic_state_preserved')
                acquired.cleanup()
                result['cleanup_verified'] = not os.path.lexists(parent)
            except Exception:
                acquired._finalizer.detach()
        result['passed'] = (operation_qualified and result['source_qualified'] is True and result['cleanup_verified'] is True
                            and result['tests'] == 10 and result['failures'] == 0
                            and result['errors'] == 0 and result['skips'] == 0)
    return result


if __name__ == '__main__':
    report = run_logging_custody_controls()
    print(json.dumps(report, sort_keys=True, separators=(',', ':')))
    raise SystemExit(0 if report['passed'] else 1)
