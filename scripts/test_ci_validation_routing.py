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
            for name in ("ownership-tests.json", "routing-tests.json", "ownership.json"):
                (directory / name).write_text(json.dumps({"passed": True, "skipped": []}))
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                result = self.routing.seal(plan, "ownership", directory)
                self.assertEqual(result["tests"], plan["expected_tests"]["ownership"])
                (directory / "ownership-tests.json").write_text(json.dumps({"passed": True, "skipped": ["test"]}))
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "ownership", directory)

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
                (directory / "result.json").write_text(json.dumps(result))
            command = [sys.executable, str(ROOT / "scripts/ci_validation_routing.py"), "aggregate",
                       "--plan", str(root / "plan.json"), "--results", str(root), "--output", str(root / "report.json")]
            self.assertEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 0)
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
        for job in ("ownership", "godot", "records", "python"):
            block = re.search(r"^  " + job + r":\n(.*?)(?=^  [a-z]+:|\Z)", text, re.M | re.S).group(1)
            self.assertIn("needs: route", block)
            self.assertIn("if: always()", block)
            self.assertLess(block.index("run: exit 1"), block.index("uses: actions/checkout@v4"))
            self.assertIn("runs-on: [self-hosted, Linux, X64, okami]", block)
            self.assertIn("ref: ${{ needs.route.outputs.linux_ref }}", block)
            self.assertIn("verify-source", block)
        self.assertIn("if: always()\n    needs: [route, ownership, godot, records, python, launcher]", text)

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