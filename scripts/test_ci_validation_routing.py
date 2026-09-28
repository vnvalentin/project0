import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class RoutingTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("routing", ROOT / "scripts/ci_validation_routing.py")
        self.routing = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.routing)
        self.metadata = {
            "candidate": "a" * 40, "baseline": "b" * 40, "approved_baseline": "b" * 40,
            "labels": [], "candidate_tree": {"server/main.gd": "1" * 40},
            "baseline_tree": {"server/main.gd": "2" * 40},
        }

    def test_linux_change_preserves_candidate_identity(self):
        plan = self.routing.route(self.metadata)
        self.assertEqual(plan["linux_ref"], "a" * 40)
        self.assertEqual(plan["linux_host"], "192.168.1.254")

    def test_named_windows_probes_preserve_linux_identity(self):
        metadata = copy.deepcopy(self.metadata)
        metadata["labels"] = ["platform:windows-required"]
        metadata["baseline_tree"] = {"server/main.gd": "1" * 40}
        for path in ("scripts/client_package_inventory.gd", "scripts/windows_paired_client.gd",
                     "tests/fixtures/windows_client_packages.gd"):
            metadata["candidate_tree"][path] = "3" * 40
        self.assertEqual(self.routing.route(metadata)["linux_ref"], metadata["baseline"])
        metadata["candidate_tree"]["scripts/unknown_probe.gd"] = "4" * 40
        with self.assertRaises(ValueError):
            self.routing.route(metadata)

    def test_client_reports_require_execution_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "client/package-controls").mkdir(parents=True)
            control = {"check": "windows-client-package-boundary-controls", "passed": True,
                       "cleanup": True, "cases": [{"name": "valid", "passed": True}]}
            path = root / "client/package-controls/result.json"
            path.write_text(json.dumps(control))
            (root / "client/build.json").write_text(json.dumps({"status": "passed", "cleanup": True, "failure_cases": 11}))
            self.assertEqual(self.routing.client_tests(root), ["scripts/test_build_current_deployment.ps1",
                                                               "scripts/test_windows_client_validation.ps1"])
            for change in ({"passed": False}, {"cleanup": False}, {"cases": []},
                           {"cases": [{"name": "valid", "passed": False}]}):
                path.write_text(json.dumps(control | change))
                with self.subTest(change=change), self.assertRaises(ValueError):
                    self.routing.client_tests(root)

    def test_unknown_mixed_missing_and_contradictory_ownership_fail_closed(self):
        for path, labels in [("unclassified/test.dat", []), ("client/player.gd", []),
                             ("native/windows_launcher/main.go", ["platform:windows-required"]),
                             ("scripts/test_package.ps1", []),
                             ("server/new.gd", ["platform:windows-required"])]:
            with self.subTest(path=path):
                metadata = copy.deepcopy(self.metadata)
                metadata["candidate_tree"][path] = "3" * 40
                metadata["labels"] = labels
                with self.assertRaises(ValueError):
                    self.routing.route(metadata)
        for field in ["candidate", "baseline", "labels", "candidate_tree", "baseline_tree", "approved_baseline"]:
            with self.subTest(field=field):
                metadata = copy.deepcopy(self.metadata)
                del metadata[field]
                with self.assertRaises(ValueError):
                    self.routing.route(metadata)

    def test_results_require_exact_identity_coverage_artifacts_and_success(self):
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = {job: [f"{job}/test"] for job in plan["required_jobs"]}
        results = {job: {"schema_version": 1, "candidate": plan["candidate"],
                         "source_ref": plan["windows_ref"] if job == "launcher" else plan["linux_ref"],
                         "input_digest": plan["input_digest"], "status": "success", "skipped": 0,
                         "tests": tests, "artifacts": {"report.json": "1" * 64}}
                   for job, tests in plan["expected_tests"].items()}
        self.assertEqual(self.routing.reconcile(plan, results), [])
        for field, value in [("candidate", "c" * 40), ("source_ref", "c" * 40),
                             ("input_digest", "0" * 64), ("status", "skipped"),
                             ("skipped", 1), ("tests", []), ("artifacts", {})]:
            with self.subTest(field=field):
                broken = copy.deepcopy(results)
                broken["godot"][field] = value
                self.assertTrue(self.routing.reconcile(plan, broken))
        del results["python"]
        self.assertTrue(self.routing.reconcile(plan, results))
        del plan["expected_tests"]["godot"]
        self.assertTrue(self.routing.reconcile(plan, results))

    def test_ownership_adapter_accepts_real_skip_schema_and_rejects_failure(self):
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = self.routing.expected_tests(self.metadata["candidate_tree"])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json", "ownership.json"):
                (directory / name).write_text(json.dumps({"passed": True, "skipped": [],
                    "tests_run": 1, "tests": 1, "failures": [], "errors": []}))
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                result = self.routing.seal(plan, "ownership", directory)
                self.assertEqual(result["tests"], plan["expected_tests"]["ownership"])
                (directory / "ownership-tests.json").write_text(json.dumps({"passed": True, "skipped": ["test"]}))
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "ownership", directory)

    def test_sealer_binds_nested_result_evidence(self):
        import hashlib
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = self.routing.expected_tests(self.metadata["candidate_tree"])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json", "ownership.json"):
                (directory / name).write_text(json.dumps({"passed": True, "skipped": [],
                    "tests_run": 1, "tests": 1, "failures": [], "errors": []}))
            nested = directory / "client/package-controls/result.json"
            nested.parent.mkdir(parents=True)
            nested.write_bytes(b'{"passed":true}')
            (directory / "result.json").write_text("old seal")
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                result = self.routing.seal(plan, "ownership", directory)
            self.assertEqual(result["artifacts"].get("client/package-controls/result.json"),
                             hashlib.sha256(nested.read_bytes()).hexdigest())
            self.assertNotIn("result.json", result["artifacts"])

    def test_ownership_seal_rejects_missing_or_zero_execution(self):
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = self.routing.expected_tests(self.metadata["candidate_tree"])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json", "ownership.json"):
                (directory / name).write_text(json.dumps({"passed": True, "skipped": []}))
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "ownership", directory)
                for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json"):
                    (directory / name).write_text(json.dumps({"passed": True, "skipped": 0,
                        "tests": 0, "tests_run": 0, "failures": 0, "errors": 0}))
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "ownership", directory)

    def test_record_seal_preserves_warning_only_success(self):
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = self.routing.expected_tests(self.metadata["candidate_tree"])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "records.log").write_text("record-sync: 0 error(s), 2 warning(s)\n")
            (directory / "deploy.log").write_text("deploy containers: durable artifact, targeted service, and recovery verified\n")
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                self.assertEqual(self.routing.seal(plan, "records", directory)["status"], "success")
                (directory / "records.log").write_text("record-sync: 1 error(s), 0 warning(s)\n")
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "records", directory)

    def test_cli_failure_retains_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "failure.json"
            result = subprocess.run([sys.executable, str(ROOT / "scripts/ci_validation_routing.py"),
                                     "aggregate", "--plan", str(Path(temporary) / "missing.json"),
                                     "--output", str(output)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            report = json.loads(output.read_text())
            self.assertFalse(report["passed"])
            self.assertTrue(report["errors"])

    def test_windows_report_requires_actual_complete_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            records = []
            packages = {
                "native-package.json": ("project0/windows-launcher", "native_test.go", "TestNative"),
                "fixture-package.json": ("command-line-arguments", "generate_1100_fixture_test.go", "TestFixture"),
            }
            for filename, (package, source, test) in packages.items():
                (directory / filename).write_text(json.dumps({"ImportPath": package,
                    "TestGoFiles": [source], "CollectedTests": [test]}))
                records.extend([{"Action": "run", "Package": package, "Test": test},
                                {"Action": "pass", "Package": package, "Test": test},
                                {"Action": "pass", "Package": package}])
            (directory / "validation-summary.json").write_text(json.dumps({
                "status": "passed", "exit_code": 0, "includes_fixture_preparation": True,
                "os": "Microsoft Windows NT"}))
            marker = "Fixture lifecycle PASS: publication, version/hash/missing/signing rejection, prior evidence preserved, staging removed."
            log = directory / "execution.log"
            good = "\n".join(json.dumps(record) for record in records) + "\n" + marker
            log.write_text(good)
            self.assertEqual(self.routing.launcher_tests(directory), [
                "native/windows_launcher/native_test.go", "scripts/generate_1100_fixture_test.go",
                "scripts/test_prepare_windows_experiment_1100.ps1"])
            for invalid in (marker, good.replace(marker, ""),
                            good + '\n{"Action":"skip","Package":"project0/windows-launcher","Test":"TestNative/child"}',
                            good.replace('"Action": "pass", "Package": "project0/windows-launcher", "Test": "TestNative"',
                                         '"Action": "output", "Package": "project0/windows-launcher", "Test": "TestNative"')):
                log.write_text(invalid)
                with self.subTest(log=invalid), self.assertRaises(ValueError):
                    self.routing.launcher_tests(directory)
            log.write_text(good)
            metadata_path = directory / "native-package.json"
            metadata = json.loads(metadata_path.read_text())
            metadata["CollectedTests"].append("TestExperiment1100RealEngine")
            metadata["SelectedTests"] = ["TestNative"]
            metadata["OptInTests"] = ["TestExperiment1100RealEngine"]
            metadata_path.write_text(json.dumps(metadata))
            self.assertEqual(len(self.routing.launcher_tests(directory)), 3)
            required_omitted = copy.deepcopy(metadata)
            required_omitted["CollectedTests"].append("TestRequired")
            required_omitted["OptInTests"].append("TestRequired")
            metadata_path.write_text(json.dumps(required_omitted))
            with self.assertRaisesRegex(ValueError, "unapproved native test selection"):
                self.routing.launcher_tests(directory)
            metadata["SelectedTests"] = []
            metadata["OptInTests"].append("TestNative")
            metadata_path.write_text(json.dumps(metadata))
            with self.assertRaises(ValueError):
                self.routing.launcher_tests(directory)

    def test_aggregate_checks_actual_artifact_bytes(self):
        import hashlib
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = {job: ["known-test"] for job in plan["required_jobs"]}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "plan.json").write_text(json.dumps(plan))
            for job in plan["required_jobs"]:
                directory = root / job
                directory.mkdir()
                (directory / "proof.txt").write_bytes(b"test evidence")
                result = {"schema_version": 1, "candidate": plan["candidate"],
                          "source_ref": plan["windows_ref"] if job == "launcher" else plan["linux_ref"],
                          "input_digest": plan["input_digest"], "status": "success", "skipped": 0,
                          "tests": ["known-test"], "artifacts": {"proof.txt": hashlib.sha256(b"test evidence").hexdigest()}}
                if job == "launcher":
                    metadata = directory / "native-package.json"
                    metadata.write_text(json.dumps({"OptInTests": ["TestExperiment1100RealEngine"]}))
                    result["artifacts"][metadata.name] = hashlib.sha256(metadata.read_bytes()).hexdigest()
                    result["not_evaluated"] = [{"test": "TestExperiment1100RealEngine",
                        "reason": "explicit opt-in via scripts/run_windows_experiment_1100.ps1"}]
                (directory / "result.json").write_text(json.dumps(result))
            command = [sys.executable, str(ROOT / "scripts/ci_validation_routing.py"), "aggregate",
                       "--plan", str(root / "plan.json"), "--results", str(root), "--output", str(root / "report.json")]
            self.assertEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 0)
            launcher_result = root / "launcher/result.json"
            original = launcher_result.read_text()
            undisclosed = json.loads(original)
            del undisclosed["not_evaluated"]
            launcher_result.write_text(json.dumps(undisclosed))
            self.assertEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 1)
            self.assertIn("opt-in", json.loads((root / "report.json").read_text())["errors"][0])
            launcher_result.write_text(original)
            (root / "godot/proof.txt").write_bytes(b"changed")
            self.assertEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 1)
            self.assertIn("hash mismatch", json.loads((root / "report.json").read_text())["errors"][0])

    def test_gut_adapter_rejects_missing_script_and_skipped_case(self):
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = {"godot": ["tests/unit/test_one.gd", "tests/unit/test_two.gd"]}
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report = directory / "gut.xml"
            report.write_text('<testsuites><testsuite name="tests/unit/test_one.gd"><testcase name="test_one"/></testsuite></testsuites>')
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                with self.assertRaisesRegex(ValueError, "missing"):
                    self.routing.seal(plan, "godot", directory)
                report.write_text('<testsuites><testsuite name="tests/unit/test_one.gd"><testcase name="test_one"><skipped/></testcase></testsuite></testsuites>')
                with self.assertRaisesRegex(ValueError, "skipped"):
                    self.routing.seal(plan, "godot", directory)

    def test_workflow_guards_all_linux_acquisition_and_retains_required_gates(self):
        import re
        text = (ROOT / ".github/workflows/validation.yml").read_text()
        self.assertNotIn("<<<<<<<", text)
        for job in ("ownership", "godot", "records", "python"):
            block = re.search(r"^  " + job + r":\n(.*?)(?=^  [a-z]+:|\Z)", text, re.M | re.S).group(1)
            self.assertIn("needs: route", block)
            self.assertIn("if: always()", block)
            self.assertLess(block.index("run: exit 1"), block.index("uses: actions/checkout@v4"))
            self.assertIn("runs-on: [self-hosted, Linux, X64, okami]", block)
            self.assertLess(block.index("name: Require independent source admission"),
                            block.index("uses: actions/checkout@v4"))
            self.assertIn("ref: ${{ env.PROJECT0_APPROVED_SOURCE_REF }}", block)
            self.assertIn('$(git rev-parse HEAD)" = "$PROJECT0_APPROVED_SOURCE_REF', block)
            self.assertIn('$(git rev-parse \'HEAD^{tree}\')" = "$PROJECT0_APPROVED_SOURCE_TREE', block)
            self.assertIn("verify-source", block)
        self.assertIn("if: always()\n    needs: [route, ownership, godot, records, python, launcher]", text)

    def test_image_workflow_requires_independent_admission(self):
        images = (ROOT / ".github/workflows/images.yml").read_text()
        self.assertIn("  packages: write", images)
        build = images.split("  build:\n", 1)[1]
        self.assertNotIn("needs.route.outputs", images)
        self.assertNotIn("<<<<<<<", images)
        self.assertIn("runs-on: [self-hosted, Linux, X64, okami]", build)
        self.assertLess(build.index("name: Require independent source admission"),
                        build.index("uses: actions/checkout@v4"))
        self.assertIn("ref: ${{ env.PROJECT0_APPROVED_SOURCE_REF }}", build)
        self.assertIn('$(git rev-parse HEAD)" == "$PROJECT0_APPROVED_SOURCE_REF', build)
        self.assertIn('$(git rev-parse \'HEAD^{tree}\')" == "$PROJECT0_APPROVED_SOURCE_TREE', build)
        self.assertNotIn("docker/setup-buildx-action", images)
        self.assertIn("builder: default", build)
        self.assertIn("env.PROJECT0_SOURCE_WINDOWS_REQUIRED == 'false'", build)
        self.assertIn("        env:\n          DOCKER_CONFIG: ${{ runner.temp }}/project0-image-", build)
        self.assertIn("if: always() && steps.docker-config.outputs.owned == 'true'", build)

    def test_manual_image_source_requires_main_ancestry(self):
        with tempfile.TemporaryDirectory() as temporary:
            event = Path(temporary) / "event.json"
            event.write_text("{}")
            environment = {"GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "owner/repo",
                           "GITHUB_SHA": "a" * 40, "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main"}
            with patch.dict(self.routing.os.environ, environment), patch.object(self.routing.sys, "platform", "win32"), \
                    patch.object(self.routing, "git_tree", return_value={"server/main.gd": "1" * 40}), \
                    patch.object(self.routing, "command", side_effect=["a" * 40, "b" * 40, ""]) as commands:
                metadata = self.routing.metadata_from_event()
                self.assertEqual(metadata["candidate"], "a" * 40)
                self.assertEqual(metadata["baseline"], "a" * 40)
                self.assertIn(("git", "merge-base", "--is-ancestor", "a" * 40, "b" * 40), [call.args for call in commands.call_args_list])

    def test_image_sources_reject_unapproved_main_history_before_tree_read(self):
        for event_name, ref in [("workflow_dispatch", "refs/heads/main"), ("push", "refs/tags/v1.0.0")]:
            with self.subTest(event=event_name), tempfile.TemporaryDirectory() as temporary:
                event = Path(temporary) / "event.json"
                event.write_text("{}")
                environment = {"GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "owner/repo",
                               "GITHUB_SHA": "a" * 40, "GITHUB_EVENT_NAME": event_name, "GITHUB_REF": ref}
                with patch.dict(self.routing.os.environ, environment), patch.object(self.routing.sys, "platform", "win32"), \
                        patch.object(self.routing, "git_tree") as trees, \
                        patch.object(self.routing, "command", side_effect=["a" * 40, "b" * 40,
                            subprocess.CalledProcessError(1, ["git", "merge-base", "--is-ancestor"])]) as commands:
                    with self.assertRaises(subprocess.CalledProcessError):
                        self.routing.metadata_from_event()
                    trees.assert_not_called()
                    self.assertEqual(commands.call_args.args, ("git", "merge-base", "--is-ancestor", "a" * 40, "b" * 40))

    def test_windows_candidate_requires_approved_linux_inputs_before_checkout(self):
        spec = importlib.util.spec_from_file_location("routing", ROOT / "scripts/ci_validation_routing.py")
        routing = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(routing)
        metadata = {
            "candidate": "a" * 40,
            "baseline": "b" * 40,
            "labels": ["platform:windows-required"],
            "candidate_tree": {"server/main.gd": "1" * 40, "scripts/test_package.ps1": "2" * 40},
            "baseline_tree": {"server/main.gd": "1" * 40},
        }
        with self.assertRaisesRegex(ValueError, "approved baseline"):
            routing.route(metadata)
        metadata["approved_baseline"] = metadata["baseline"]
        plan = routing.route(metadata)
        self.assertEqual(plan["linux_ref"], metadata["baseline"])
        self.assertNotEqual(plan["linux_ref"], metadata["candidate"])
        self.assertEqual(plan["required_jobs"], ["ownership", "godot", "records", "python", "launcher"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RoutingTests))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({"passed": result.wasSuccessful(), "tests": result.testsRun,
                                      "failures": len(result.failures), "errors": len(result.errors),
                                      "skipped": len(result.skipped)}, indent=2) + "\n")
    raise SystemExit(not result.wasSuccessful())