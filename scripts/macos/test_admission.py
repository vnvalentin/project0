"""Mac-only controls for the bounded, unauthenticated admission diagnostic (#1353)."""
import argparse
from copy import deepcopy
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import platform
import signal
import socket
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_module(name):
    spec = importlib.util.spec_from_file_location("macos_" + name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AdmissionPlanTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-admission-plan-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.admission = load_module("admission")
        self.preflight = load_module("preflight")
        self.plan = {
            "schema_version": 1,
            "kind": "component",
            "issue": "https://github.com/vnvalentin/project0/issues/1353",
            "steps": [{
                "suite": "macos-admission",
                "platform": "macos",
                "host": "Philips-MacBook-Pro-2",
                "command": "python3 scripts/macos/admission.py --godot build/tools/godot/Godot.app/Contents/MacOS/Godot --version 0.12.0 --plan .scratch/macos-client/admission-plan-1353.json --report build/validation/macos/admission-control.json",
                "dependencies": ["godot-client", "python", "git"],
                "tests": ["scripts/macos/admission.py", "scripts/macos/admission_probe.gd"],
                "artifacts": ["build/validation/macos/admission-control.json"],
            }],
        }
        self.manifest = {
            "schema_version": 1,
            "hosts": {"macos": ["Philips-MacBook-Pro-2"], "linux": ["192.168.1.254"]},
            "server_dependencies": ["sqlite", "canon", "ollama"],
            "suites": {
                "macos-admission": {
                    "platform": "macos", "owner": "macos-client",
                    "dependencies": ["godot-client", "python", "git"],
                    "tests": ["scripts/macos/admission.py", "scripts/macos/admission_probe.gd"],
                },
                "macos-tooling": {
                    "platform": "macos", "owner": "macos-tooling",
                    "dependencies": ["python", "git"],
                    "tests": ["scripts/macos/test_*.py"],
                },
            },
        }
        self.args = argparse.Namespace(
            godot=self.root / "build/tools/godot/Godot.app/Contents/MacOS/Godot",
            version="0.12.0",
            plan=self.root / ".scratch/macos-client/admission-plan-1353.json",
            report=self.root / "build/validation/macos/admission-control.json",
        )
        for path, contents in (
            (self.args.godot, b"owned tool fixture, never executed\n"),
            (self.root / "scripts/macos/admission.py", b"# owned coordinator fixture, never executed\n"),
            (self.root / "scripts/macos/admission_probe.gd", b"extends SceneTree\n"),
            (self.args.plan, json.dumps(self.plan).encode()),
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)

    def check(self, plan=None, manifest=None, operating_system="Darwin", host="Philips-MacBook-Pro-2.local"):
        return self.preflight.validate_plan(
            self.root, manifest if manifest is not None else self.manifest,
            plan if plan is not None else self.plan, operating_system, host,
        )

    def test_exact_invocation_and_literal_owned_plan_are_accepted(self):
        self.admission.validate_invocation(self.root, self.plan, self.args)
        self.assertEqual(self.check(), [])

    def test_tooling_steps_do_not_change_the_bound_admission_invocation(self):
        plan = deepcopy(self.plan)
        plan["steps"].insert(0, {
            "suite": "macos-tooling", "platform": "macos", "host": "Philips-MacBook-Pro-2",
            "command": "python3 scripts/macos/test_admission.py --report build/validation/macos/controls.json",
            "dependencies": ["python", "git"], "tests": ["scripts/macos/test_admission.py"],
            "artifacts": ["build/validation/macos/controls.json"],
        })
        self.admission.validate_invocation(self.root, plan, self.args)

    def test_changed_tool_version_plan_or_report_is_refused(self):
        for field, value in {
            "godot": self.root / "build/tools/godot/unplanned-editor",
            "version": "0.12.1",
            "plan": self.root / ".scratch/macos-client/unplanned.json",
            "report": self.root / "build/validation/macos/unplanned.json",
        }.items():
            with self.subTest(field=field):
                args = deepcopy(self.args)
                setattr(args, field, value)
                with self.assertRaises(ValueError):
                    self.admission.validate_invocation(self.root, self.plan, args)

    def test_endpoint_authentication_and_shell_arguments_cannot_expand_the_plan(self):
        for suffix in (
            " --host 127.0.0.1", " --port 9998", " --assertion synthetic-fixture",
            " --password synthetic-fixture", " ; echo chained", " $(echo substituted)",
        ):
            with self.subTest(suffix=suffix):
                plan = deepcopy(self.plan)
                plan["steps"][0]["command"] += suffix
                self.assertTrue(self.check(plan))

    def test_non_mac_or_paired_or_server_dependent_plans_are_refused(self):
        for operating_system, host in (("Linux", "Philips-MacBook-Pro-2"), ("Darwin", "Unassigned-Mac")):
            with self.subTest(os=operating_system, host=host):
                self.assertTrue(self.check(operating_system=operating_system, host=host))
        plan = deepcopy(self.plan)
        plan["kind"] = "paired-runtime"
        self.assertTrue(self.check(plan))
        plan = deepcopy(self.plan)
        plan["steps"][0]["dependencies"].append(" SQLite ")
        self.assertTrue(self.check(plan))

    def test_incomplete_duplicate_or_changed_admission_arguments_are_refused(self):
        command = self.plan["steps"][0]["command"]
        commands = (
            command.replace(" --version 0.12.0", ""),
            command + " --version 0.12.0",
            command.replace("--version 0.12.0", "--version 0.12.1"),
            command.replace("--report build/validation/macos/admission-control.json",
                            "--report build/validation/macos/unplanned.json"),
            command.replace("--plan .scratch/macos-client/admission-plan-1353.json",
                            "--plan ../unowned-plan.json"),
        )
        for changed in commands:
            with self.subTest(command=changed):
                plan = deepcopy(self.plan)
                plan["steps"][0]["command"] = changed
                self.assertTrue(self.check(plan))
        for missing in ("scripts/macos/admission.py", "scripts/macos/admission_probe.gd"):
            with self.subTest(missing=missing):
                plan = deepcopy(self.plan)
                plan["steps"][0]["tests"].remove(missing)
                self.assertTrue(self.check(plan))

    def test_output_escape_and_duplicate_test_ownership_are_refused(self):
        plan = deepcopy(self.plan)
        plan["steps"][0]["command"] = plan["steps"][0]["command"].replace(
            "build/validation/macos/admission-control.json", "../escaped.json")
        plan["steps"][0]["artifacts"] = ["../escaped.json"]
        self.assertTrue(self.check(plan))
        manifest = deepcopy(self.manifest)
        manifest["suites"]["linux-control"] = {
            "platform": "linux", "dependencies": ["python"],
            "tests": ["scripts/macos/admission_probe.gd"],
        }
        self.assertTrue(self.check(manifest=manifest))

    def prepare_coordinator_fixture(self):
        files = {
            "project.godot": 'config_version=5\n[application]\nconfig/name="Fixture"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
            "shared/client_build_version.gd": 'extends RefCounted\nconst CLIENT_BUILD_VERSION: String = "1.2.3"\n',
            "scripts/macos/offline_probe.gd": "extends SceneTree\n",
            "scripts/macos/package.py": "# owned metadata fixture\n",
            "scripts/macos/preflight.py": "# owned metadata fixture\n",
            "scripts/validation_ownership.json": json.dumps(self.manifest),
        }
        for name, contents in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)

        def git_fixture(command, **options):
            if "ls-files" in command:
                return b"project.godot\0shared/client_build_version.gd\0"
            if "rev-parse" in command:
                return "owned-fixture-source-revision\n"
            if "status" in command:
                return b""
            raise AssertionError("unexpected fixture source query")

        return git_fixture

    def arguments(self, version="0.12.0"):
        return ["--godot", str(self.args.godot), "--version", version,
                "--plan", str(self.args.plan), "--report", str(self.args.report)]

    def test_invalid_invocation_retains_safe_failure_evidence_without_launching(self):
        git_fixture = self.prepare_coordinator_fixture()
        with mock.patch.object(self.admission, "ROOT", self.root), \
                mock.patch.object(self.admission.subprocess, "check_output", side_effect=git_fixture), \
                mock.patch.object(self.admission.subprocess, "Popen") as launch, redirect_stdout(io.StringIO()):
            result = self.admission.main(self.arguments(version="invalid-synthetic-input"))
        self.assertEqual(result, 1)
        launch.assert_not_called()
        report = json.loads(self.args.report.read_text())
        self.assertFalse(report["passed"])
        self.assertEqual(report["error_type"], "ValueError")
        self.assertIn("source_hashes", report)
        self.assertEqual(report["target"], {"host": "192.69.180.236", "port": 9999})
        self.assertNotIn("invalid-synthetic-input", json.dumps(report))
        self.assertFalse(report["raw_engine_output_captured"])

    def test_existing_report_is_preserved_and_cannot_launch_a_diagnostic(self):
        self.args.report.parent.mkdir(parents=True)
        self.args.report.write_bytes(b"existing evidence is preserved\n")
        with mock.patch.object(self.admission, "ROOT", self.root), \
                mock.patch.object(self.admission.subprocess, "Popen") as launch, redirect_stdout(io.StringIO()):
            result = self.admission.main(self.arguments())
        self.assertEqual(result, 1)
        launch.assert_not_called()
        self.assertEqual(self.args.report.read_bytes(), b"existing evidence is preserved\n")

    def test_failed_native_import_retains_status_and_cleans_only_owned_state(self):
        git_fixture = self.prepare_coordinator_fixture()
        fake_home = self.root / "fixture-home"
        support = fake_home / "Library/Application Support"
        support.mkdir(parents=True)
        existing = support / "existing-profile.txt"
        existing.write_bytes(b"existing user state is preserved\n")
        process = mock.Mock(pid=1353, returncode=7)
        process.wait.return_value = 7
        fixture_os = SimpleNamespace(
            environ={"HOME": str(fake_home)}, killpg=mock.Mock(side_effect=ProcessLookupError),
        )
        with mock.patch.object(self.admission, "ROOT", self.root), \
                mock.patch.object(self.admission, "os", fixture_os), \
                mock.patch.object(self.admission.package, "os", SimpleNamespace(environ={"HOME": str(fake_home)})), \
                mock.patch.object(self.admission.subprocess, "check_output", side_effect=git_fixture), \
                mock.patch.object(self.admission.subprocess, "Popen", return_value=process) as launch, \
                redirect_stdout(io.StringIO()):
            result = self.admission.main(self.arguments())
        self.assertEqual(result, 1)
        report = json.loads(self.args.report.read_text())
        self.assertEqual(report["terminal_stage"], "cold_import", json.dumps({
            "terminal_stage": report["terminal_stage"], "error_type": report.get("error_type"),
        }))
        self.assertTrue(report["preflight_passed"])
        self.assertEqual(launch.call_count, 1)
        self.assertFalse(report["passed"])
        self.assertEqual(report["error_type"], "RuntimeError")
        self.assertEqual(report["commands"][0]["exit_code"], 7)
        self.assertEqual(report["commands"][0]["phase"], "cold_import")
        self.assertTrue(report["temporary_state_removed"])
        stage = Path(launch.call_args.kwargs["cwd"])
        self.assertFalse(stage.exists())
        self.assertEqual(list(support.iterdir()), [existing])
        self.assertEqual(existing.read_bytes(), b"existing user state is preserved\n")


def admitted_probe_fixture():
    return {
        "schema_version": 1, "probe": "macos-server-admission", "passed": True,
        "target": {"host": "192.69.180.236", "port": 9999},
        "client_version": "0.12.0", "user_data_isolated": True,
        "startup_scene_inert": True, "connected": True, "admitted": True,
        "terminal_stage": "admitted", "timeout_ms": 20000, "elapsed_msec": 21,
        "phase_durations_ms": {"connect": 1, "admission": 20},
        "connection_events": [
            {"state": "connecting", "elapsed_msec": 0},
            {"state": "connected", "elapsed_msec": 1},
        ],
        "events_truncated": False,
        "rpc_checksum_failed": False,
        "rpc_checksum_failure_count": 0,
        "checksum_classifier_selfcheck_passed": True,
        "version_rejection": {"received": False, "outcome": "", "required_version": ""},
        "assertion_sent": False, "authentication_attempted": False,
        "session_attempted": False, "world_entry_attempted": False,
        "cleanup_disconnect": True, "failures": [],
    }


class AdmissionEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.admission = load_module("admission")

    def test_literal_admitted_and_exact_timeout_records_are_safe_evidence(self):
        self.admission.validate_evidence(admitted_probe_fixture())
        report = admitted_probe_fixture()
        report.update({
            "passed": False, "admitted": False, "terminal_stage": "server_admission_timeout",
            "elapsed_msec": 20001, "phase_durations_ms": {"connect": 1, "admission": 20000},
            "failures": ["server_admission_timeout"],
        })
        self.admission.validate_evidence(report)

    def test_endpoint_or_client_version_drift_is_refused(self):
        for field, value in (("target", {"host": "127.0.0.1", "port": 9999}),
                             ("target", {"host": "192.69.180.236", "port": 9998}),
                             ("client_version", "0.12.1")):
            with self.subTest(field=field, value=value):
                report = admitted_probe_fixture()
                report[field] = value
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)

    def test_authentication_session_assertion_or_world_entry_attempts_are_refused(self):
        for field in ("assertion_sent", "authentication_attempted", "session_attempted", "world_entry_attempted"):
            with self.subTest(field=field):
                report = admitted_probe_fixture()
                report[field] = True
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)

    def test_unknown_fields_or_remote_text_cannot_enter_evidence(self):
        for field, value in (("account_assertion", "synthetic-fixture"), ("raw_error", "untrusted fixture text"),
                             ("rpc_checksum_message", "synthetic diagnostic text"),
                             ("checksum_classifier_inputs", ["synthetic diagnostic text"])):
            with self.subTest(field=field):
                report = admitted_probe_fixture()
                report[field] = value
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)
        for section, field, value in (
            ("target", "description", "untrusted fixture text"),
            ("version_rejection", "detail", "untrusted fixture text"),
            ("version_rejection", "outcome", "unknown remote response"),
            ("version_rejection", "required_version", "0.12.1\nuntrusted fixture text"),
        ):
            with self.subTest(section=section, field=field):
                report = admitted_probe_fixture()
                report[section][field] = value
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)
        report = admitted_probe_fixture()
        report["connection_events"][0]["state"] = "failed: untrusted fixture text"
        with self.assertRaises(ValueError):
            self.admission.validate_evidence(report)

    def test_checksum_flag_and_count_must_be_typed_and_consistent(self):
        for changes in (
            {"rpc_checksum_failed": False, "rpc_checksum_failure_count": 1},
            {"rpc_checksum_failed": True, "rpc_checksum_failure_count": 0},
            {"rpc_checksum_failed": "true", "rpc_checksum_failure_count": 1},
            {"rpc_checksum_failed": False, "rpc_checksum_failure_count": True},
            {"rpc_checksum_failed": False, "rpc_checksum_failure_count": -1},
        ):
            with self.subTest(changes=changes):
                report = admitted_probe_fixture()
                report.update(changes)
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)

    def test_checksum_failure_cannot_be_reported_as_admitted_success(self):
        report = admitted_probe_fixture()
        report["rpc_checksum_failed"] = True
        report["rpc_checksum_failure_count"] = 1
        with self.assertRaises(ValueError):
            self.admission.validate_evidence(report)

    def test_checksum_failure_is_bounded_evidence_without_a_raw_message(self):
        report = admitted_probe_fixture()
        report.update({
            "passed": False, "admitted": False, "terminal_stage": "server_admission_timeout",
            "elapsed_msec": 20003, "phase_durations_ms": {"connect": 3, "admission": 20000},
            "rpc_checksum_failed": True, "rpc_checksum_failure_count": 1,
            "failures": ["server_admission_timeout", "rpc_checksum_failed"],
        })
        self.admission.validate_evidence(report)
        report["rpc_checksum_failure_count"] = 64
        self.admission.validate_evidence(report)
        report["rpc_checksum_failure_count"] = 65
        with self.assertRaises(ValueError):
            self.admission.validate_evidence(report)

    def test_native_classifier_selfcheck_is_required_before_a_success_claim(self):
        report = admitted_probe_fixture()
        report["checksum_classifier_selfcheck_passed"] = False
        with self.assertRaises(ValueError):
            self.admission.validate_evidence(report)
        report["checksum_classifier_selfcheck_passed"] = "true"
        with self.assertRaises(ValueError):
            self.admission.validate_evidence(report)
        report.update({
            "passed": False, "connected": False, "admitted": False,
            "terminal_stage": "setup_failed", "elapsed_msec": 0,
            "phase_durations_ms": {"connect": 0, "admission": 0}, "connection_events": [],
            "checksum_classifier_selfcheck_passed": False,
            "failures": ["checksum_classifier_selfcheck_failed"],
        })
        self.admission.validate_evidence(report)

    def test_unbounded_or_wrong_typed_events_and_durations_are_refused(self):
        for field, value in (("elapsed_msec", 60001), ("elapsed_msec", True),
                             ("timeout_ms", 1), ("connected", "true")):
            with self.subTest(field=field, value=value):
                report = admitted_probe_fixture()
                report[field] = value
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)
        for changes in (
            {"connection_events": [{"state": "connected", "elapsed_msec": 1}] * 65},
            {"phase_durations_ms": {"connect": 25001, "admission": 20}},
            {"phase_durations_ms": {"connect": 1, "admission": -1}},
        ):
            with self.subTest(changes=changes):
                report = admitted_probe_fixture()
                report.update(changes)
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)

    def test_success_cannot_be_claimed_without_admission_isolation_and_cleanup(self):
        for field, value in (("admitted", False), ("connected", False),
                             ("user_data_isolated", False), ("startup_scene_inert", False),
                             ("cleanup_disconnect", False), ("failures", ["server_admission_timeout"]),
                             ("terminal_stage", "server_admission_timeout")):
            with self.subTest(field=field):
                report = admitted_probe_fixture()
                report[field] = value
                with self.assertRaises(ValueError):
                    self.admission.validate_evidence(report)


class AdmissionProcessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-admission-process-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.admission = load_module("admission")

    def test_process_output_is_suppressed_and_only_exit_status_is_returned(self):
        process = mock.Mock(pid=1353, returncode=0)
        process.wait.return_value = 0
        fixture_os = SimpleNamespace(environ={}, killpg=mock.Mock(side_effect=ProcessLookupError))
        with mock.patch.object(self.admission, "os", fixture_os), \
                mock.patch.object(self.admission.subprocess, "Popen", return_value=process) as launch:
            result = self.admission.run_suppressed(["owned-fixture-engine"], self.root)
        self.assertEqual(result, {"exit_code": 0, "timeout": False, "process_group_removed": True})
        options = launch.call_args.kwargs
        self.assertEqual(options["stdout"], subprocess.DEVNULL)
        self.assertEqual(options["stderr"], subprocess.DEVNULL)
        self.assertTrue(options["start_new_session"])
        self.assertEqual(process.wait.call_args_list, [mock.call(timeout=55), mock.call()])

    def test_nonzero_exit_is_retained_as_a_status_without_remote_text(self):
        process = mock.Mock(pid=1353, returncode=7)
        process.wait.return_value = 7
        fixture_os = SimpleNamespace(environ={}, killpg=mock.Mock(side_effect=ProcessLookupError))
        with mock.patch.object(self.admission, "os", fixture_os), \
                mock.patch.object(self.admission.subprocess, "Popen", return_value=process):
            result = self.admission.run_suppressed(["owned-fixture-engine"], self.root, timeout=10)
        self.assertEqual(result, {"exit_code": 7, "timeout": False, "process_group_removed": True})
        self.assertEqual(process.wait.call_args_list, [mock.call(timeout=10), mock.call()])

    def test_child_environment_does_not_inherit_authentication_values(self):
        process = mock.Mock(pid=1353, returncode=0)
        process.wait.return_value = 0
        fixture_os = SimpleNamespace(killpg=mock.Mock(side_effect=ProcessLookupError), environ={
            "HOME": str(self.root), "PATH": "/usr/bin", "LANG": "C",
            "PROJECT0_CLIENT_NAKAMA_LOGIN": "1", "PROJECT0_NAKAMA_SERVER_KEY": "synthetic-fixture",
            "PROJECT0_ACCOUNT_ASSERTION": "synthetic-fixture",
        })
        with mock.patch.object(self.admission, "os", fixture_os), \
                mock.patch.object(self.admission.subprocess, "Popen", return_value=process) as launch:
            self.admission.run_suppressed(["owned-fixture-engine"], self.root)
        environment = launch.call_args.kwargs["env"]
        self.assertNotIn("PROJECT0_CLIENT_NAKAMA_LOGIN", environment)
        self.assertNotIn("PROJECT0_NAKAMA_SERVER_KEY", environment)
        self.assertNotIn("PROJECT0_ACCOUNT_ASSERTION", environment)

    def test_timed_out_owned_process_is_killed_and_reaped_without_raw_diagnostics(self):
        process = mock.Mock(pid=1353, returncode=-9)
        process.wait.side_effect = [subprocess.TimeoutExpired("owned-fixture-engine", 55), -9]
        fixture_os = SimpleNamespace(
            environ={"HOME": str(self.root), "PATH": "/usr/bin"},
            killpg=mock.Mock(side_effect=[None, ProcessLookupError]),
        )
        with mock.patch.object(self.admission, "os", fixture_os), \
                mock.patch.object(self.admission.subprocess, "Popen", return_value=process):
            result = self.admission.run_suppressed(["owned-fixture-engine"], self.root)
        self.assertEqual(result, {"exit_code": -9, "timeout": True, "process_group_removed": True})
        self.assertEqual(fixture_os.killpg.call_args_list, [mock.call(1353, signal.SIGKILL), mock.call(1353, 0)])
        self.assertEqual(process.wait.call_args_list, [mock.call(timeout=55), mock.call()])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        parser.error("report already exists; choose a new evidence path")
    suites = [unittest.defaultTestLoader.loadTestsFromTestCase(case) for case in
              (AdmissionPlanTests, AdmissionEvidenceTests, AdmissionProcessTests)]
    selected = [test.id() for suite in suites for test in suite]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(suites))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    passed = result.wasSuccessful() and not result.skipped and result.testsRun == len(selected)
    with args.report.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps({
            "issue": 1353, "platform": "macos", "os": platform.system(),
            "host": socket.gethostname(), "passed": passed, "tests_run": result.testsRun,
            "failures": len(result.failures), "errors": len(result.errors),
            "skipped": len(result.skipped), "selected_tests": selected,
            "network_executed": False, "runtime_acceptance": False,
        }, indent=2) + "\n")
    return int(not passed)


if __name__ == "__main__":
    raise SystemExit(main())
