"""Linux process-identity and fail-closed controls for run_validation_monitor."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from run_validation_monitor import Process, main, unknown_engines


ROOT = Path(__file__).resolve().parents[1]
MONITOR = ROOT / "scripts/run_validation_monitor.py"


class ValidationProcessMonitorTests(unittest.TestCase):
    def setUp(self):
        if not sys.platform.startswith("linux"):
            self.skipTest("Linux /proc and pidfd behavior")
        self.temporary = tempfile.TemporaryDirectory(prefix="project0-monitor-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "evidence").mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Validation Fixture")
        self.git("config", "user.email", "validation@example.invalid")
        self.write("tracked.txt", "baseline\n")
        self.git("add", "tracked.txt")
        self.git("commit", "-qm", "fixture")
        self.revision = self.git("rev-parse", "HEAD")
        self.report = self.root / "evidence/review-validation.json"

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def invoke(self, command, extra=()):
        return main([
            "--root", str(self.root), "--report", str(self.report),
            "--expected-revision", self.revision, "--timeout-seconds", "2",
            *extra, "--", *command,
        ])

    def result(self):
        return json.loads(self.report.read_text(encoding="utf-8"))

    def cleanup_fixture_process(self, pidfile):
        if not pidfile.is_file():
            return
        fixture = json.loads(pidfile.read_text(encoding="utf-8"))
        pid = fixture["pid"]
        try:
            descriptor = os.pidfd_open(pid, 0)
        except (FileNotFoundError, ProcessLookupError):
            return
        try:
            stat = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
            start_ticks = int(stat[stat.rindex(")") + 1:].split()[19])
            if start_ticks != fixture["start_ticks"]:
                return
            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
            poller = select.poll()
            poller.register(descriptor, select.POLLIN)
            if not poller.poll(1000):
                signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                poller.poll(2000)
            try:
                os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                pass
        finally:
            os.close(descriptor)

    def test_success_records_source_process_and_complete_gut_inventory(self):
        summary = self.write("build/validation/summary.json", json.dumps({
            "runner": "GUT", "status": "passed", "exit_code": 0,
            "scripts_expected": 3, "scripts_ran": 3, "timed_out": False,
            "gut_script_error_observed": False, "gut_log_scan_failed": False,
        }))
        code = self.invoke([sys.executable, "-c", "print('validation complete')"],
                           ["--gut-summary", str(summary)])
        report = self.result()
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["source_revision"], self.revision)
        self.assertTrue(report["source_unchanged"])
        self.assertTrue(report["owned_processes"])
        self.assertTrue(report["cleanup"]["owned_processes_stopped"])

    def test_nonzero_command_exit_is_retained(self):
        code = self.invoke([sys.executable, "-c", "raise SystemExit(7)"])
        self.assertEqual(code, 1)
        self.assertEqual(self.result()["command_exit_code"], 7)

    def test_timeout_kills_owned_command_and_records_forced_recovery(self):
        code = self.invoke([sys.executable, "-c", "import time; time.sleep(30)"])
        report = self.result()
        self.assertEqual(code, 1)
        self.assertTrue(report["timed_out"])
        self.assertTrue(report["forced_recovery"])
        self.assertTrue(report["cleanup"]["owned_processes_stopped"])

    def test_orphaned_descendant_is_adopted_cleaned_and_never_passes(self):
        pidfile = self.root / "child.pid"
        code = self.invoke([sys.executable, "-c",
                            "import subprocess,sys,pathlib,json; child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); stat=pathlib.Path(f'/proc/{child.pid}/stat').read_text(); start=int(stat[stat.rindex(')')+1:].split()[19]); pathlib.Path(sys.argv[1]).write_text(json.dumps({'pid':child.pid,'start_ticks':start}))",
                            str(pidfile)])
        try:
            report = self.result()
            self.assertEqual(code, 1)
            self.assertTrue(report["forced_recovery"])
            self.assertTrue(report["cleanup"]["owned_processes_stopped"])
            self.assertIn("owned_process_survived_command", report["errors"])
        finally:
            self.cleanup_fixture_process(pidfile)

    def test_nested_godot_process_is_owned_after_command_leader_exits(self):
        pidfile = self.root / "godot-child.json"
        engine = "import ctypes,time; ctypes.CDLL(None).prctl(15,b'godot',0,0,0); time.sleep(30)"
        command = (
            "import json,pathlib,subprocess,sys; "
            "child=subprocess.Popen([sys.executable,'-c',sys.argv[2]]); "
            "stat=pathlib.Path(f'/proc/{child.pid}/stat').read_text(); "
            "start=int(stat[stat.rindex(')')+1:].split()[19]); "
            "pathlib.Path(sys.argv[1]).write_text(json.dumps({'pid':child.pid,'start_ticks':start}))"
        )
        code = self.invoke([sys.executable, "-c", command, str(pidfile), engine])
        try:
            report = self.result()
            self.assertEqual(code, 1)
            self.assertIn("owned_process_survived_command", report["errors"])
            self.assertFalse(report["unknown_godot"])
            self.assertTrue(any(item["command"] == "godot" for item in report["owned_processes"]))
            self.assertTrue(report["forced_recovery"])
            self.assertTrue(report["cleanup"]["owned_processes_stopped"])
        finally:
            self.cleanup_fixture_process(pidfile)

    def test_unowned_godot_blocks_run_and_is_not_signaled(self):
        if not hasattr(signal, "SIGTERM"):
            self.skipTest("process signals unavailable")
        foreign = subprocess.Popen([
            sys.executable, "-c",
            "import ctypes,time; ctypes.CDLL(None).prctl(15,b'godot',0,0,0); time.sleep(30)",
        ], start_new_session=True, stdin=subprocess.DEVNULL,
           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                try:
                    if Path(f"/proc/{foreign.pid}/comm").read_text().strip().startswith("godot"):
                        break
                except OSError:
                    pass
                time.sleep(0.01)
            code = self.invoke([sys.executable, "-c", "print('must not run')"],
                               ["--reject-unowned-godot"])
            report = self.result()
            self.assertEqual(code, 1)
            self.assertFalse(report["command_started"])
            self.assertIn("unowned_godot_present_before_run", report["errors"])
            self.assertTrue(any(identity.startswith(f"{foreign.pid}:")
                                for identity in report["baseline_unowned_godot"]))
            self.assertIsNone(foreign.poll(), "foreign engine must not be terminated")
        finally:
            foreign.send_signal(signal.SIGTERM)
            foreign.wait(timeout=3)

    def test_exact_allowed_cgroup_normalizes_procfs_newline_only(self):
        allowed = "0::/system.slice/docker-expected.scope"
        expected = Process(10, 1, 10, 10, 100, "S", "godot", allowed + "\n")
        foreign = Process(11, 1, 11, 11, 101, "S", "godot", "0::/system.slice/docker-other.scope\n")
        self.assertEqual(unknown_engines({10: expected}, {}, {allowed}), [])
        self.assertEqual(unknown_engines({11: foreign}, {}, {allowed}), [foreign])

    def test_source_mutation_and_incomplete_inventory_fail_closed(self):
        summary = self.write("build/validation/summary.json", json.dumps({
            "runner": "GUT", "status": "passed", "exit_code": 0,
            "scripts_expected": 3, "scripts_ran": 2, "timed_out": False,
            "gut_script_error_observed": False, "gut_log_scan_failed": False,
        }))
        code = self.invoke([sys.executable, "-c",
                            "from pathlib import Path; Path('tracked.txt').write_text('mutated\\n')"],
                           ["--gut-summary", str(summary)])
        report = self.result()
        self.assertEqual(code, 1)
        self.assertFalse(report["source_unchanged"])
        self.assertIn("source_changed_during_validation", report["errors"])
        self.assertIn("gut_inventory_or_summary_failed", report["errors"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ValidationProcessMonitorTests)
    )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({
        "schema_version": 1,
        "passed": result.wasSuccessful() and not result.skipped and result.testsRun > 0,
        "tests_run": result.testsRun,
        "failures": [{"test": str(test), "trace": trace} for test, trace in result.failures],
        "errors": [{"test": str(test), "trace": trace} for test, trace in result.errors],
        "skipped": [{"test": str(test), "reason": reason} for test, reason in result.skipped],
    }, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(int(not result.wasSuccessful() or result.testsRun == 0))