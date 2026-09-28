import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).with_name("check_validation_ownership.py")


class ValidationOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.write("client/main.gd", "extends Node\n")
        self.write("tests/integration/test_canon.gd", "extends GutTest\n")

    def write(self, name, contents):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")

    def run_check(self, plan=None):
        command = [sys.executable, str(CHECKER), "--root", str(self.root)]
        if plan is not None:
            self.write("plan.json", json.dumps(plan))
            command.extend(["--plan", str(self.root / "plan.json")])
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertIn(result.returncode, (0, 1), result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(result.returncode == 0, report["passed"])
        self.assertFalse(report["runtime_executed"])
        return report

    def plan(self):
        return {
            "schema_version": 1,
            "kind": "component",
            "steps": [{
                "suite": "godot-server",
                "host": "192.168.1.254",
                "platform": "linux",
                "command": "scripts/run_gut_validation.sh",
                "dependencies": ["godot", "sqlite"],
                "tests": ["tests/integration/test_canon.gd"],
                "artifacts": ["build/validation/gut.xml"],
            }],
        }

    def test_linux_server_plan_passes_without_executing_runtime(self):
        self.assertTrue(self.run_check(self.plan())["passed"])

    def test_wrong_linux_host_is_rejected(self):
        plan = self.plan()
        plan["steps"][0]["host"] = "local-wsl"
        self.assertIn("192.168.1.254", " ".join(self.run_check(plan)["errors"]))

    def test_missing_or_incomplete_dependencies_are_rejected(self):
        for dependencies in (None, [], ["godot"]):
            plan = self.plan()
            plan["steps"][0]["dependencies"] = dependencies
            self.assertFalse(self.run_check(plan)["passed"])

    def test_windows_plan_cannot_target_linux_host(self):
        self.write("scripts/test_client.ps1", "exit 0\n")
        plan = self.plan()
        plan["steps"] = [{
            "suite": "windows-client", "platform": "windows", "host": "192.168.1.254",
            "command": "pwsh -File scripts/test_client.ps1",
            "dependencies": ["powershell", "godot-client"],
            "tests": ["scripts/test_client.ps1"], "artifacts": ["client.json"],
        }]
        self.assertFalse(self.run_check(plan)["passed"])

    def test_missing_artifacts_and_unowned_test_are_rejected(self):
        plan = self.plan()
        del plan["steps"][0]["artifacts"]
        plan["steps"][0]["tests"] = ["../outside.gd"]
        report = self.run_check(plan)
        self.assertFalse(report["passed"])
        self.assertIn("artifact", " ".join(report["errors"]))
        self.assertIn("repository-relative", " ".join(report["errors"]))

    def test_malformed_plan_fails_with_json_diagnostic(self):
        for plan in ([], {"schema_version": 1, "steps": [None]}, {"steps": "bad"}):
            with self.subTest(plan=plan):
                self.assertFalse(self.run_check(plan)["passed"])

    def test_paired_plan_cannot_use_server_evidence_alone(self):
        plan = self.plan()
        plan["kind"] = "paired-runtime"
        self.assertIn("windows-client", " ".join(self.run_check(plan)["errors"]))

    def test_inventory_rejects_unowned_test(self):
        self.write("tests/new/test_unowned.gd", "extends GutTest\n")
        self.assertIn("unowned", " ".join(self.run_check()["errors"]))

    def test_nested_tests_are_not_silently_assigned_to_nonrecursive_gut(self):
        self.write("tests/unit/new/test_unowned.gd", "extends GutTest\n")
        self.assertIn("unowned", " ".join(self.run_check()["errors"]))

    def test_complete_paired_plan_is_only_planning_evidence(self):
        plan = self.plan()
        plan["kind"] = "paired-runtime"
        plan.update({field: "owned-scenario-1243" for field in (
            "scenario_id", "client_build", "server_build", "correlation_id", "setup", "cleanup"
        )})
        self.write("scripts/test_client.ps1", "exit 0\n")
        plan["steps"].append({
            "suite": "windows-client", "host": "SETSUJOKU", "platform": "windows",
            "command": "pwsh -File scripts/test_client.ps1",
            "dependencies": ["powershell", "godot-client"],
            "tests": ["scripts/test_client.ps1"], "artifacts": ["client-evidence.json"],
        })
        report = self.run_check(plan)
        self.assertTrue(report["passed"])
        self.assertEqual(report["runtime_acceptance"], "not evaluated")
        plan["steps"][1]["dependencies"] = ["SQLite"]
        self.assertIn("server dependencies", " ".join(self.run_check(plan)["errors"]))

    def test_server_data_exception_cannot_hide_persistence(self):
        self.write("client/main.gd", 'const Fixture = preload("res://server/starting_town_hub_fixture.gd")\n')
        self.write("server/starting_town_hub_fixture.gd", "extends RefCounted\n")
        self.assertTrue(self.run_check()["passed"])
        self.write("server/starting_town_hub_fixture.gd", "extends RefCounted\nvar database = SQLite.new()\n")
        self.assertFalse(self.run_check()["passed"])

    def test_shared_values_and_comment_only_references_pass(self):
        self.write("client/main.gd", 'extends Node\n# SQLite and res://server/db.gd are forbidden\nconst Values = preload("res://shared/values.gd")\n')
        self.write("shared/values.gd", "extends RefCounted\nconst SPEED = 1\n")
        self.assertTrue(self.run_check()["passed"])

    def test_direct_server_dependency_is_rejected(self):
        self.write("client/main.gd", 'extends Node\nconst Store = preload("res://server/store.gd")\n')
        self.write("server/store.gd", "extends RefCounted\n")
        self.assertIn("server/store.gd", " ".join(self.run_check()["errors"]))

    def test_normalized_sqlite_resource_path_is_rejected(self):
        self.write("client/main.gd", 'const Store = preload("res://./addons//godot-sqlite/gdsqlite.gdextension")\n')
        self.write("addons/godot-sqlite/gdsqlite.gdextension", "[configuration]\n")
        self.assertFalse(self.run_check()["passed"])

    def test_symlink_cannot_hide_server_dependency(self):
        self.write("client/main.gd", 'const Store = preload("res://shared/alias.gd")\n')
        self.write("server/store.gd", "extends RefCounted\n")
        (self.root / "shared").mkdir()
        (self.root / "shared/alias.gd").symlink_to(self.root / "server/store.gd")
        self.assertFalse(self.run_check()["passed"])

    def test_failed_regression_run_still_writes_json(self):
        self.write("test_validation_ownership.py", Path(__file__).read_text(encoding="utf-8"))
        self.write("check_validation_ownership.py", 'print("{}")\n')
        report = self.root / "failure.json"
        result = subprocess.run([
            sys.executable, str(self.root / "test_validation_ownership.py"),
            "--report", str(report),
            "ValidationOwnershipTests.test_canon_test_cannot_be_assigned_to_windows",
        ], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        evidence = json.loads(report.read_text(encoding="utf-8"))
        self.assertFalse(evidence["passed"])
        self.assertEqual(evidence["tests_run"], 1)
        self.assertEqual(len(evidence["failures"]), 1)

    def test_indirect_persistence_dependency_is_rejected(self):
        self.write("client/main.gd", 'extends Node\nconst Values = preload("res://shared/values.gd")\n')
        self.write("shared/values.gd", "extends RefCounted\nvar database = SQLite.new()\n")
        self.assertIn("SQLite", " ".join(self.run_check()["errors"]))

    def test_global_server_type_is_rejected(self):
        self.write("server/store.gd", "extends RefCounted\nclass_name CanonRepository\n")
        self.write("client/main.gd", "extends Node\nvar database = CanonRepository.new()\n")
        self.assertIn("CanonRepository", " ".join(self.run_check()["errors"]))

    def test_negative_resource_probe_is_not_a_dependency(self):
        self.write("client/main.gd", 'extends Node\nfunc probe():\n    return not ResourceLoader.exists("res://server/server_main.gd")\n')
        self.assertTrue(self.run_check()["passed"])

    def test_canon_test_cannot_be_assigned_to_windows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            test_path = root / "tests/integration/test_canon.gd"
            test_path.parent.mkdir(parents=True)
            test_path.write_text('extends GutTest\n', encoding="utf-8")
            plan = root / "plan.json"
            plan.write_text(json.dumps({
                "schema_version": 1,
                "kind": "component",
                "steps": [{
                    "suite": "godot-server",
                    "host": "SETSUJOKU",
                    "platform": "windows",
                    "tests": ["tests/integration/test_canon.gd"],
                }],
            }), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(CHECKER), "--root", str(root), "--plan", str(plan)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            report = json.loads(result.stdout)
            self.assertFalse(report["passed"])
            self.assertIn("requires linux", " ".join(report["errors"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, default=Path("build/validation/ownership-tests.json"))
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    loader = unittest.defaultTestLoader
    suite = (loader.loadTestsFromNames(args.tests, sys.modules[__name__]) if args.tests
             else loader.loadTestsFromTestCase(ValidationOwnershipTests))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({
        "schema_version": 1,
        "passed": result.wasSuccessful() and not result.skipped and result.testsRun > 0,
        "tests_run": result.testsRun,
        "failures": [{"test": str(test), "trace": trace} for test, trace in result.failures],
        "errors": [{"test": str(test), "trace": trace} for test, trace in result.errors],
        "skipped": [{"test": str(test), "reason": reason} for test, reason in result.skipped],
    }, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(int(not result.wasSuccessful() or bool(result.skipped) or result.testsRun == 0))