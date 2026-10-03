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


def passing_ownership_report(name):
    if name == "hosted-container-tests.json":
        return {
            "passed": True, "tests": 5, "failures": 0, "errors": 0, "skipped": 0,
            "cases": [
                {"name": "reject_privileged", "passed": True, "exit_code": 2},
                {"name": "reject_network_host", "passed": True, "exit_code": 2},
                {"name": "reject_cap_add", "passed": True, "exit_code": 2},
                {"name": "induced_failure_cleanup", "passed": True, "exit_code": 23, "surviving_containers": 0},
                {"name": "host_sealer_success", "passed": True, "exit_code": 0, "surviving_containers": 0},
            ],
        }
    return {"passed": True, "skipped": [], "tests_run": 1, "tests": 1, "failures": [], "errors": []}


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

    def test_scratch_validation_plan_is_linux_owned(self):
        metadata = copy.deepcopy(self.metadata)
        metadata["candidate_tree"][".scratch/1213/validation-plan.json"] = "3" * 40
        plan = self.routing.route(metadata)
        self.assertEqual(plan["linux_ref"], metadata["candidate"])

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

    def test_reviewed_artifact_contract_admits_mixed_client_server_candidate(self):
        metadata = copy.deepcopy(self.metadata)
        metadata["labels"] = ["platform:windows-required"]
        metadata["candidate_tree"]["client/network_client.gd"] = "3" * 40
        metadata["candidate_tree"]["server/detail.gd"] = "4" * 40
        metadata["artifact_contract"] = {
            "schema_version": 1,
            "name": "reviewed",
            "application_source_commit": "a" * 40,
            "client": {"version": "0.14.15", "manifest_sha256": "b" * 64,
                        "archive_sha256": "c" * 64, "pck_sha256": "d" * 64},
            "linux_artifact": {"manifest_sha256": "e" * 64, "source_commit": "f" * 40,
                                "image": "sha256:" + "1" * 64},
            "source_allowlist": ["client/network_client.gd", "server/detail.gd"],
        }
        plan = self.routing.route(metadata)
        self.assertEqual(plan["artifact_contract"], "reviewed")
        # Changed Linux inputs must be validated at the candidate, never the baseline (#1322).
        self.assertEqual(plan["linux_ref"], metadata["candidate"])
        self.assertEqual(plan["input_digest"], self.routing.digest(
            {path: blob for path, blob in metadata["candidate_tree"].items()}))
        metadata["candidate_tree"]["tests/integration/test_new_seam.gd"] = "6" * 40
        plan = self.routing.route(metadata)
        self.assertIn("tests/integration/test_new_seam.gd",
                      self.routing.planned_expected_tests(metadata, plan)["godot"],
                      "a candidate-validated plan expects the candidate's own tests (#1345)")

    def test_contract_with_identical_linux_inputs_may_reuse_baseline(self):
        metadata = copy.deepcopy(self.metadata)
        metadata["labels"] = ["platform:windows-required"]
        metadata["baseline_tree"] = {"server/main.gd": "1" * 40}
        metadata["candidate_tree"]["client/network_client.gd"] = "3" * 40
        metadata["baseline_tree"]["client/network_client.gd"] = "3" * 40
        metadata["candidate_tree"]["scripts/run_shared_exploration_validation.ps1"] = "5" * 40
        plan = self.routing.route(metadata)
        self.assertEqual(plan["linux_ref"], metadata["baseline"])
        self.assertEqual(self.routing.planned_expected_tests(metadata, plan),
                         self.routing.expected_tests(metadata["baseline_tree"], True),
                         "a reused-baseline plan expects the baseline's tests")

    def test_client_change_rejects_missing_artifact_contract(self):
        metadata = copy.deepcopy(self.metadata)
        metadata["labels"] = ["platform:windows-required"]
        metadata["candidate_tree"]["client/network_client.gd"] = "3" * 40
        with self.assertRaisesRegex(ValueError, "artifact contract"):
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
            for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json",
                         "hosted-container-tests.json", "ownership.json"):
                (directory / name).write_text(json.dumps(passing_ownership_report(name)))
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                result = self.routing.seal(plan, "ownership", directory)
                self.assertEqual(result["tests"], plan["expected_tests"]["ownership"])
                hosted_path = directory / "hosted-container-tests.json"
                valid_hosted_report = passing_ownership_report(hosted_path.name)
                cases = valid_hosted_report["cases"]
                invalid_case_lists = [
                    cases[:-1],
                    cases + [cases[0]],
                    cases + [{"name": "extra", "passed": False, "exit_code": 1}],
                    [{**cases[0], "passed": False}] + cases[1:],
                    [{**cases[0], "exit_code": 0}] + cases[1:],
                ]
                for invalid_cases in invalid_case_lists:
                    with self.subTest(invalid_cases=invalid_cases):
                        hosted_path.write_text(json.dumps({**valid_hosted_report, "cases": invalid_cases}))
                        with self.assertRaisesRegex(ValueError, "container control evidence"):
                            self.routing.seal(plan, "ownership", directory)
                hosted_path.write_text(json.dumps(passing_ownership_report(hosted_path.name)))
                (directory / "ownership-tests.json").write_text(json.dumps({"passed": True, "skipped": ["test"]}))
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "ownership", directory)

    def test_sealer_binds_nested_result_evidence(self):
        import hashlib
        plan = self.routing.route(self.metadata)
        plan["expected_tests"] = self.routing.expected_tests(self.metadata["candidate_tree"])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json",
                         "hosted-container-tests.json", "ownership.json"):
                (directory / name).write_text(json.dumps(passing_ownership_report(name)))
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
            for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json",
                         "hosted-container-tests.json", "ownership.json"):
                report = passing_ownership_report(name)
                report.pop("tests", None)
                report.pop("tests_run", None)
                (directory / name).write_text(json.dumps(report))
            with patch.object(self.routing, "command", return_value=plan["linux_ref"]):
                with self.assertRaises(ValueError):
                    self.routing.seal(plan, "ownership", directory)
                for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json",
                             "hosted-container-tests.json"):
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

    def test_workflow_routes_hosted_linux_and_retains_required_gates(self):
        import re
        text = (ROOT / ".github/workflows/validation.yml").read_text()
        self.assertNotIn("<<<<<<<", text)
        self.assertIn("  push:\n    branches:\n      - main\n  pull_request:", text)
        self.assertNotIn("types: [labeled]", text)
        for job in ("ownership", "godot", "records", "python"):
            block = re.search(r"^  " + job + r":\n(.*?)(?=^  [a-z]+:|\Z)", text, re.M | re.S).group(1)
            expected_needs = "needs: route" if job == "ownership" else "needs: [route, ownership]"
            self.assertIn(expected_needs, block)
            self.assertIn("if: always()", block)
            self.assertLess(block.index("run: exit 1"), block.index("uses: actions/checkout@v4"))
            self.assertIn("runs-on: ubuntu-latest", block)
            self.assertNotIn("PROJECT0_APPROVED_SOURCE", block)
            self.assertIn("ref: ${{ needs.route.outputs.linux_ref }}", block)
            self.assertIn('$(git rev-parse HEAD)" = "${{ needs.route.outputs.linux_ref }}', block)
            self.assertIn("verify-source", block)
        godot = re.search(r"^  godot:\n(.*?)(?=^  [a-z]+:|\Z)", text, re.M | re.S).group(1)
        self.assertIn("bash scripts/run_hosted_gut_container.sh", godot)
        container = (ROOT / "scripts/run_hosted_gut_container.sh").read_text()
        self.assertIn('--user "$(id -u):$(id -g)"', container)
        self.assertIn("HOME=/tmp/home", container)
        self.assertIn("umask 0002", container)
        self.assertIn("ghcr.io/vnvalentin/project0-godot@sha256:801341", container)
        self.assertIn('docker image inspect "$image" >/dev/null 2>&1', container)
        self.assertIn('docker build --iidfile "$image_id_file" --build-arg "GODOT_IMAGE=$base_image"', container)
        self.assertIn('--tag "$image" "$root/deploy/validation"', container)
        self.assertIn('docker image rm "$image"', container)
        self.assertLess(container.index("trap cleanup EXIT"), container.index("docker build"))
        self.assertIn('"$root/deploy/validation"', container)
        recipe = (ROOT / "deploy/validation/Dockerfile").read_text()
        self.assertIn("FROM ${GODOT_IMAGE}", recipe)
        self.assertIn("--no-install-recommends python3 git", recipe)
        self.assertNotIn("COPY", recipe)
        self.assertNotIn('chmod g+w "$GITHUB_WORKSPACE"', container)
        self.assertIn('install -d -m 2775 "$root/build/validation/runtime" "$root/.godot" "$root/logs/experiments"', container)
        self.assertIn('-v "$root:/app:ro"', container)
        self.assertIn('-v "$root/.godot:/app/.godot"', container)
        self.assertIn('-v "$root/build/validation:/app/build/validation"', container)
        self.assertIn('-v "$root/logs/experiments:/app/logs/experiments"', container)
        self.assertIn("--network none --no-healthcheck --read-only --cap-drop ALL", container)
        self.assertIn("--security-opt no-new-privileges", container)
        self.assertIn("--tmpfs /tmp:rw,nosuid,nodev,exec", container)
        self.assertIn("scripts/.hosted-write-probe", container)
        self.assertIn("PROJECT0_TEST_STATE_DIR=build/validation/runtime", container)
        self.assertIn('stat -c %g "$artifact"', container)
        for unsafe in ("--privileged", "--network host", "--cap-add"):
            self.assertNotIn(unsafe, container)
        for job in ("godot", "records", "python"):
            block = re.search(r"^  " + job + r":\n(.*?)(?=^  [a-z]+:|\Z)", text, re.M | re.S).group(1)
            self.assertIn("needs.ownership.result != 'success'", block)
        ownership = re.search(r"^  ownership:\n(.*?)(?=^  [a-z]+:|\Z)", text, re.M | re.S).group(1)
        self.assertLess(ownership.index("Check test ownership and static client dependencies"),
                        ownership.index("Test hosted GUT container boundary"))
        self.assertLess(ownership.index("Test hosted GUT container boundary"),
                        ownership.index("Bind ownership evidence"))
        self.assertIn("if: always()\n    needs: [route, ownership, godot, records, python, launcher]", text)

    def test_image_workflow_uses_hosted_ephemeral_builder(self):
        images = (ROOT / ".github/workflows/images.yml").read_text()
        self.assertIn("  packages: write", images)
        self.assertIn("  pull_request:\n", images)
        self.assertNotIn("types: [labeled]", images)
        build = images.split("  build:\n", 1)[1]
        self.assertNotIn("needs.route.outputs", images)
        self.assertNotIn("<<<<<<<", images)
        self.assertIn("runs-on: ubuntu-latest", build)
        self.assertNotIn("PROJECT0_APPROVED_SOURCE", build)
        self.assertIn("uses: docker/setup-buildx-action@v3", build)
        self.assertIn("push: ${{ github.event_name != 'pull_request' }}", build)
        self.assertIn("cache-from: type=gha", build)
        self.assertIn('git merge-base --is-ancestor "$GITHUB_SHA" origin/main', build)
        self.assertLess(build.index("git merge-base --is-ancestor"), build.index("docker/login-action@v3"))

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

    def test_pull_request_metadata_uses_rest_and_preserves_source_identity(self):
        candidate = "a" * 40
        approved = "b" * 40
        pull = {
            "state": "open",
            "head": {"sha": candidate, "repo": {"full_name": "owner/repo"}},
            "base": {"sha": approved, "ref": "main", "repo": {"full_name": "owner/repo"}},
            "labels": [{"name": "bug"}, {"name": "technical-debt"}],
        }
        with tempfile.TemporaryDirectory() as temporary:
            event = Path(temporary) / "event.json"
            event.write_text(json.dumps({"number": 42, "pull_request": {"head": {"sha": candidate}}}))
            environment = {
                "GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "owner/repo",
                "GITHUB_SHA": candidate, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/42/merge",
            }
            with patch.dict(self.routing.os.environ, environment), patch.object(self.routing.sys, "platform", "win32"), \
                    patch.object(self.routing, "git_tree", return_value={"server/main.gd": "1" * 40}), \
                    patch.object(self.routing, "command", side_effect=[candidate, approved, json.dumps(pull), ""]) as commands:
                metadata = self.routing.metadata_from_event()

        self.assertEqual(metadata["candidate"], candidate)
        self.assertEqual(metadata["baseline"], approved)
        self.assertEqual(metadata["labels"], ["bug", "technical-debt"])
        calls = [call.args for call in commands.call_args_list]
        self.assertIn(("gh", "api", "repos/owner/repo/pulls/42"), calls)
        self.assertFalse(any(call[:2] == ("gh", "pr") for call in calls))

    def test_pull_request_metadata_rejects_unapproved_rest_identity_before_tree_read(self):
        candidate = "a" * 40
        approved = "b" * 40
        pull = {
            "state": "open",
            "head": {"sha": candidate, "repo": {"full_name": "owner/repo"}},
            "base": {"sha": approved, "ref": "main", "repo": {"full_name": "owner/repo"}},
            "labels": [],
        }
        invalid_pulls = []
        for path, key, value in (
            ((), "state", "closed"),
            (("head",), "sha", "c" * 40),
            (("head", "repo"), "full_name", "fork/repo"),
            (("base",), "sha", "c" * 40),
            (("base",), "ref", "release"),
            (("base", "repo"), "full_name", "other/repo"),
        ):
            changed = copy.deepcopy(pull)
            target = changed
            for part in path:
                target = target[part]
            target[key] = value
            invalid_pulls.append(changed)

        for changed in invalid_pulls:
            with self.subTest(pull=changed), tempfile.TemporaryDirectory() as temporary:
                event = Path(temporary) / "event.json"
                event.write_text(json.dumps({"number": 42, "pull_request": {"head": {"sha": candidate}}}))
                environment = {
                    "GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "owner/repo",
                    "GITHUB_SHA": candidate, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/42/merge",
                }
                with patch.dict(self.routing.os.environ, environment), patch.object(self.routing.sys, "platform", "win32"), \
                        patch.object(self.routing, "git_tree") as trees, \
                        patch.object(self.routing, "command", side_effect=[candidate, approved, json.dumps(changed)]):
                    with self.assertRaisesRegex(ValueError, "stale, foreign, or unapproved PR source identity"):
                        self.routing.metadata_from_event()
                    trees.assert_not_called()

    def test_pull_request_metadata_fails_closed_on_malformed_rest_response(self):
        candidate = "a" * 40
        approved = "b" * 40
        malformed_pulls = [
            [],
            {},
            {"state": "open", "base": {"sha": approved, "ref": "main", "repo": {"full_name": "owner/repo"}},
             "labels": []},
            {"state": "open", "head": {"sha": candidate, "repo": {"full_name": "owner/repo"}},
             "base": {"sha": approved, "ref": "main", "repo": {"full_name": "owner/repo"}}},
            {"state": "open", "head": {"sha": candidate, "repo": {"full_name": "owner/repo"}},
             "base": {"sha": approved, "ref": "main", "repo": {"full_name": "owner/repo"}},
             "labels": [None]},
        ]
        for changed in malformed_pulls:
            with self.subTest(pull=changed), tempfile.TemporaryDirectory() as temporary:
                event = Path(temporary) / "event.json"
                event.write_text(json.dumps({"number": 42, "pull_request": {"head": {"sha": candidate}}}))
                environment = {
                    "GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "owner/repo",
                    "GITHUB_SHA": candidate, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/42/merge",
                }
                with patch.dict(self.routing.os.environ, environment), patch.object(self.routing.sys, "platform", "win32"), \
                        patch.object(self.routing, "git_tree") as trees, \
                        patch.object(self.routing, "command", side_effect=[candidate, approved, json.dumps(changed)]):
                    with self.assertRaises(ValueError):
                        self.routing.metadata_from_event()
                    trees.assert_not_called()

    def test_pull_request_metadata_aborts_when_rest_request_fails(self):
        candidate = "a" * 40
        approved = "b" * 40
        with tempfile.TemporaryDirectory() as temporary:
            event = Path(temporary) / "event.json"
            event.write_text(json.dumps({"number": 42, "pull_request": {"head": {"sha": candidate}}}))
            environment = {
                "GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "owner/repo",
                "GITHUB_SHA": candidate, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/42/merge",
            }
            with patch.dict(self.routing.os.environ, environment), patch.object(self.routing.sys, "platform", "win32"), \
                    patch.object(self.routing, "git_tree") as trees, \
                    patch.object(self.routing, "command", side_effect=[candidate, approved,
                        subprocess.CalledProcessError(1, ["gh", "api", "repos/owner/repo/pulls/42"])]):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.routing.metadata_from_event()
                trees.assert_not_called()

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
