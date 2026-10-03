"""Public command controls; substituted engine/container boundaries never run native work."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SourceIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="project0-gut-source-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        for name in ("run_gut_validation.sh", "run_hosted_gut_container.sh", "prepare_godot_project.py"):
            if (ROOT / "scripts" / name).is_file():
                shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        recipe = ROOT / "deploy/validation/Dockerfile"
        if recipe.is_file():
            (self.root / "deploy/validation").mkdir(parents=True)
            shutil.copyfile(recipe, self.root / "deploy/validation/Dockerfile")
        (self.root / "tests/unit").mkdir(parents=True)
        (self.root / "tests/unit/test_fixture.gd").write_text("# Command fixture only\n")
        self.original_project_config = ('config_version=5\n\n[application]\nconfig/name="Fixture"\n\n'
                                        '[autoload]\nPlayerIdentity="*res://client/player_identity.gd"\n'
                                        'NetworkClient="*res://client/network_client.gd"\n\n'
                                        '[editor_plugins]\nenabled=PackedStringArray("res://addons/gut/plugin.cfg")\n')
        (self.root / "project.godot").write_text(self.original_project_config)
        (self.root / "client").mkdir()
        for name in ("player_identity.gd", "network_client.gd"):
            (self.root / "client" / name).write_text("extends Node\n")
        self.extension_registry = "res://addons/godot-sqlite/gdsqlite.gdextension\n"
        extension = self.root / "addons/godot-sqlite/gdsqlite.gdextension"
        extension.parent.mkdir(parents=True)
        extension.write_text('[configuration]\nentry_symbol="fixture"\n')
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.engine_calls = self.root / "engine-calls.jsonl"
        self.docker_calls = self.root / "docker-calls.jsonl"
        self.docker_image_state = self.root / "docker-image-id"
        self.docker_container_state = self.root / "docker-container-state.json"
        self.engine_flags = self.bin / "engine-flags.json"
        self.env = {
            "PATH": str(self.bin) + os.pathsep + "/usr/bin:/bin",
            "HOME": str(self.root / "home"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "TMPDIR": str(self.root),
            "GODOT_BIN": str(self.bin / "godot"),
            "RESULT_DIR": "build/validation",
            "DASHBOARD_RESULTS_DIR": str(self.root / "dashboard"),
            "FAKE_ENGINE_CALLS": str(self.engine_calls),
            "FAKE_DOCKER_CALLS": str(self.docker_calls),
            "FAKE_DOCKER_IMAGE_STATE": str(self.docker_image_state),
            "FAKE_DOCKER_CONTAINER_STATE": str(self.docker_container_state),
        }
        self.write_executable("godot", '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
flags_path = Path(__FLAGS_PATH__)
flags = json.loads(flags_path.read_text()) if flags_path.is_file() else {}
configuration = Path("project.godot")
project_config = configuration.read_text() if configuration.is_file() else None
registry = Path(".godot/extension_list.cfg")
registry_contents = registry.read_text() if registry.is_file() else None
with open(__CALLS_PATH__, "a") as output:
    output.write(json.dumps({"source": os.environ.get("M4_SOURCE_REVISION"), "args": sys.argv[1:], "extension_registry": registry_contents, "project_config": project_config, "cwd": str(Path.cwd()), "excluded_present": [name for name in (".netrc", ".env.fixture", ".aws/fixture.json", "logs/private.json", "build/private.json", "fixtures/creation.db") if Path(name).exists()]}) + "\\n")
if "--import" in sys.argv:
    bootstrap = 'enabled=PackedStringArray()' in project_config
    if flags.get("FAKE_SOURCE_PARENT_LINK") == "1" and bootstrap:
        original_client = Path(__ORIGINAL_CLIENT__)
        original_client.rename(original_client.with_name("detached-source-client"))
        original_client.symlink_to(Path.cwd() / "client", target_is_directory=True)
    if flags.get("FAKE_CLIENT_PARENT_LINK") == "1" and bootstrap:
        Path("client").rename("detached-client")
        Path("client").symlink_to(__ORIGINAL_CLIENT__, target_is_directory=True)
    if flags.get("FAKE_BOOTSTRAP_TIMEOUT") == "1" and bootstrap:
        sys.exit(124)
    if flags.get("FAKE_BOOTSTRAP_EXIT") == "1" and bootstrap:
        sys.exit(7)
    if flags.get("FAKE_QUALIFICATION_EXIT") == "1" and not bootstrap:
        sys.exit(8)
    if flags.get("FAKE_QUALIFICATION_MARKER") == "1" and not bootstrap:
        print("SCRIPT ERROR: synthetic qualification failure")
    if flags.get("FAKE_NON_SCRIPT_ERROR") == "1":
        print("ERROR: synthetic expected SQLite constraint failure")
    if flags.get("FAKE_PROJECT_EDIT") == "1":
        configuration.write_text(project_config + "\\n; unknown fixture edit")
    if flags.get("FAKE_REGISTRY_EDIT") == "1":
        registry.write_text("res://unknown-fixture.gdextension\\n")
if "--import" in sys.argv and flags.get("FAKE_IMPORT_SCRIPT_ERROR") == "1":
    print("SCRIPT ERROR: Parse Error: synthetic preparation failure")
if "-s" in sys.argv and flags.get("FAKE_REMOVE_REPORT") == "1":
    Path(__REPORT_PATH__).unlink()
if "-s" in sys.argv and flags.get("FAKE_EXPERIMENT_ARTIFACT") == "1":
    trace = Path("logs/experiments/control.json")
    trace.parent.mkdir(parents=True)
    trace.write_text('{"fixture":"retained"}')
if "-s" in sys.argv and flags.get("FAKE_GUT_OVERRIDE_EDIT") == "1":
    Path("override.cfg").write_text("; unknown GUT fixture edit")
if "--import" in sys.argv and flags.get("FAKE_OVERRIDE_EDIT") == "1":
    Path("override.cfg").write_text("; unknown fixture edit")
if "-s" in sys.argv and flags.get("FAKE_GUT_SCRIPT_ERROR") == "1":
    print("SCRIPT ERROR: synthetic skipped runtime failure")
for arg in sys.argv:
    if arg.startswith("-gjunit_xml_file="):
        Path(arg.split("=", 1)[1]).write_text('<testsuites><testsuite name="tests/unit/test_fixture.gd" tests="1" failures="0"/></testsuites>')
'''.replace('__ORIGINAL_CLIENT__', repr(str(self.root / 'client'))).replace('__FLAGS_PATH__', repr(str(self.engine_flags))).replace('__CALLS_PATH__', repr(str(self.engine_calls))).replace('__REPORT_PATH__', repr(str(self.root / 'build/validation/preparation-summary.json'))))
        self.write_executable("docker", '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
with open(os.environ["FAKE_DOCKER_CALLS"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
state = Path(os.environ["FAKE_DOCKER_IMAGE_STATE"])
container_state = Path(os.environ["FAKE_DOCKER_CONTAINER_STATE"])
if sys.argv[1:3] == ["container", "ls"]:
    status = int(os.environ.get("FAKE_DOCKER_CONTAINER_LIST_EXIT", "0"))
    if status == 0 and container_state.is_file():
        print(json.loads(container_state.read_text())["name"])
    sys.exit(status)
if sys.argv[1:3] == ["image", "inspect"]:
    if state.is_file():
        print(state.read_text())
        sys.exit(0)
    sys.exit(1)
if sys.argv[1:3] == ["image", "rm"]:
    status = int(os.environ.get("FAKE_DOCKER_REMOVE_IMAGE_EXIT", "0"))
    if status == 0:
        state.unlink(missing_ok=True)
    sys.exit(status)
if sys.argv[1:3] == ["container", "inspect"]:
    if container_state.is_file():
        container = json.loads(container_state.read_text())
        if "--format" in sys.argv:
            print(container["label"])
        sys.exit(0)
    sys.exit(1)
if sys.argv[1:2] == ["rm"]:
    if container_state.is_file():
        container_state.unlink()
    sys.exit(0)
if sys.argv[1:2] == ["build"]:
    status = int(os.environ.get("FAKE_DOCKER_BUILD_EXIT", "0"))
    if status == 0:
        image_id = "sha256:" + "a" * 64
        state.write_text(image_id)
        if os.environ.get("FAKE_DOCKER_IMAGE_ID_MISSING") != "1":
            iidfile = Path(sys.argv[sys.argv.index("--iidfile") + 1])
            iidfile.write_text(image_id)
    sys.exit(status)
if sys.argv[1:2] == ["run"] and os.environ.get("FAKE_DOCKER_REPLACE_IMAGE") == "1":
    state.write_text("sha256:" + "b" * 64)
if sys.argv[1:2] == ["run"] and os.environ.get("FAKE_DOCKER_CONTAINER_RACE") == "1":
    name = sys.argv[sys.argv.index("--name") + 1]
    container_state.write_text(json.dumps({"name": name, "label": "foreign-container"}))
    sys.exit(125)
sys.exit(1 if sys.argv[1:3] == ["container", "inspect"] else 0)
''')
        for args in (["init", "-q"], ["add", "."],
                     ["-c", "user.name=Command Fixture", "-c", "user.email=fixture@example.invalid",
                      "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"]):
            subprocess.run(["git", *args], cwd=self.root, env=self.env,
                           check=True, capture_output=True, timeout=10)
        self.sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root,
                                           env=self.env, text=True, timeout=10).strip()

    def write_executable(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_command(self, name, source=None):
        env = self.env.copy()
        self.engine_flags.write_text(json.dumps({key: self.env.get(key) for key in ("FAKE_IMPORT_SCRIPT_ERROR", "FAKE_GUT_SCRIPT_ERROR", "FAKE_REMOVE_REPORT", "FAKE_EXPERIMENT_ARTIFACT", "FAKE_OVERRIDE_EDIT", "FAKE_GUT_OVERRIDE_EDIT", "FAKE_BOOTSTRAP_EXIT", "FAKE_QUALIFICATION_EXIT", "FAKE_QUALIFICATION_MARKER", "FAKE_NON_SCRIPT_ERROR", "FAKE_PROJECT_EDIT", "FAKE_REGISTRY_EDIT", "FAKE_BOOTSTRAP_TIMEOUT", "FAKE_CLIENT_PARENT_LINK", "FAKE_SOURCE_PARENT_LINK")}))
        if source is not None:
            env["M4_SOURCE_REVISION"] = source
        return subprocess.run(["bash", "scripts/" + name], cwd=self.root, env=env,
                              capture_output=True, text=True, timeout=20)

    def test_ordinary_runner_supplies_checkout_source_to_engine(self):
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(call["source"] == self.sha for call in calls))


    def test_standard_runner_initializes_the_tracked_extension_registry_before_engine_launch(self):
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(call["extension_registry"] == self.extension_registry for call in calls))

    def test_standard_runner_rejects_import_script_errors_before_gut_with_retained_failure(self):
        self.env["FAKE_IMPORT_SCRIPT_ERROR"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["stage"], "import")
        self.assertEqual(summary["exit_code"], 1)
        self.assertTrue(summary["import_script_error_observed"])
        self.assertIn("SCRIPT ERROR", (self.root / summary["import_log"]).read_text())

    def test_standard_runner_rejects_gut_script_error_despite_complete_passing_junit(self):
        self.env["FAKE_GUT_SCRIPT_ERROR"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")
        self.assertTrue(summary["gut_script_error_observed"])
        self.assertEqual(summary["scripts_expected"], summary["scripts_ran"])

    def test_unknown_registry_replaces_stale_pass_with_failed_preparation(self):
        cache = self.root / ".godot"
        cache.mkdir()
        (cache / "extension_list.cfg").write_text("res://unreviewed.gdextension\n")
        summary_path = self.root / "build/validation/validation-summary.json"
        summary_path.parent.mkdir(parents=True)
        summary_path.write_text('{"status":"passed"}')
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 2, result.stderr + result.stdout)
        self.assertFalse(self.engine_calls.exists())
        summary = json.loads(summary_path.read_text())
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["stage"], "bootstrap")
        self.assertEqual(summary["gut_execution"], "NOT_OBSERVED")

    def test_marker_scan_failure_cannot_qualify_import_or_gut(self):
        self.write_executable("grep", '''#!/usr/bin/python3
import os, sys
last = sys.argv[-1]
if "-Eq" in sys.argv and last.endswith(os.environ["FAKE_SCAN_FAILURE"]):
    sys.exit(2)
os.execv("/usr/bin/grep", ["grep", *sys.argv[1:]])
''')
        for log in ("import.log", "gut.log"):
            with self.subTest(log=log):
                self.env["FAKE_SCAN_FAILURE"] = log
                result = self.run_command("run_gut_validation.sh")
                self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
                summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
                self.assertEqual(summary["status"], "failed")
                key = "import_log_scan_failed" if log == "import.log" else "gut_log_scan_failed"
                self.assertTrue(summary[key])

    def test_standard_runner_prepares_in_isolation_then_restores_plugin_before_gut(self):
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertIn('enabled=PackedStringArray()', calls[0]["project_config"])
        self.assertEqual(len(calls), 3)
        self.assertIn('enabled=PackedStringArray("res://addons/gut/plugin.cfg")', calls[1]["project_config"])
        self.assertEqual(calls[2]["project_config"], self.original_project_config)
        self.assertTrue(all(call["cwd"] != str(self.root) for call in calls))
        self.assertEqual((self.root / "project.godot").read_text(), self.original_project_config)
        self.assertFalse(Path(calls[0]["cwd"]).exists())
        self.assertFalse((self.root / ".godot").exists())

    def test_missing_custody_report_fails_and_preserves_staged_source(self):
        self.env["FAKE_REMOVE_REPORT"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertTrue(Path(calls[0]["cwd"]).is_dir())
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")

    def test_experiment_artifact_and_relative_dashboard_survive_staged_cleanup(self):
        self.env["FAKE_EXPERIMENT_ARTIFACT"] = "1"
        self.env["DASHBOARD_RESULTS_DIR"] = "dashboard"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        trace = self.root / "logs/experiments/control.json"
        self.assertEqual(json.loads(trace.read_text()), {"fixture": "retained"})
        summary = json.loads((self.root / "dashboard/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "passed")
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertFalse(Path(calls[0]["cwd"]).exists())

    def test_unknown_override_edit_prevents_qualification_and_preserves_stage(self):
        self.env["FAKE_OVERRIDE_EDIT"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        stage = Path(calls[0]["cwd"])
        self.assertEqual((stage / "override.cfg").read_text(), "; unknown fixture edit")
        summary = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertTrue(summary["configuration_custody_lost"])

    def test_unknown_gut_override_edit_fails_and_preserves_stage(self):
        self.env["FAKE_GUT_OVERRIDE_EDIT"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 3)
        stage = Path(calls[0]["cwd"])
        self.assertEqual((stage / "override.cfg").read_text(), "; unknown GUT fixture edit")
        summary = json.loads((self.root / "dashboard/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")

    def test_changed_tracked_executable_mode_rejects_source_before_engine_launch(self):
        path = self.root / "client/player_identity.gd"
        path.chmod(0o755)
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertFalse(self.engine_calls.exists())
        preparation = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertEqual(preparation["status"], "failed")
        self.assertEqual(preparation["failure_class"], "source_tracked_dirt")

    def test_each_import_phase_rejects_nonzero_and_qualification_script_marker(self):
        for flag, calls_expected, stage in (("FAKE_BOOTSTRAP_EXIT", 1, "bootstrap"),
                                            ("FAKE_QUALIFICATION_EXIT", 2, "qualification"),
                                            ("FAKE_QUALIFICATION_MARKER", 2, "qualification")):
            with self.subTest(flag=flag):
                self.engine_calls.unlink(missing_ok=True)
                self.env[flag] = "1"
                result = self.run_command("run_gut_validation.sh")
                self.env.pop(flag)
                self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
                calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
                self.assertEqual(len(calls), calls_expected)
                self.assertTrue(all("--import" in call["args"] for call in calls))
                report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
                self.assertEqual(report[stage]["status"], "failed")
                self.assertTrue(report["configuration_restored"])
                self.assertFalse(Path(calls[0]["cwd"]).exists())
                summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
                self.assertEqual(summary["gut_execution"], "NOT_OBSERVED")

    def test_expected_non_script_error_observation_does_not_expand_script_gate(self):
        self.env["FAKE_NON_SCRIPT_ERROR"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertTrue(report["bootstrap"]["non_script_error_observed"])
        self.assertFalse(report["bootstrap"]["script_error_observed"])
        self.assertEqual(report["qualification"]["status"], "passed")

    def test_unknown_project_or_registry_edit_prevents_second_import_and_retains_stage(self):
        for flag, filename in (("FAKE_PROJECT_EDIT", "project.godot"),
                               ("FAKE_REGISTRY_EDIT", ".godot/extension_list.cfg")):
            with self.subTest(flag=flag):
                self.engine_calls.unlink(missing_ok=True)
                self.env[flag] = "1"
                result = self.run_command("run_gut_validation.sh")
                self.env.pop(flag)
                self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
                calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
                self.assertEqual(len(calls), 1)
                stage = Path(calls[0]["cwd"])
                self.assertIn("unknown", (stage / filename).read_text())
                report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
                self.assertTrue(report["configuration_custody_lost"])

    def test_private_generated_and_database_inputs_are_excluded_in_git_and_gitless_copies(self):
        names = (".netrc", ".env.fixture", ".aws/fixture.json", "logs/private.json",
                 "build/private.json", "fixtures/creation.db")
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic excluded input")
        for args in (["add", *names], ["-c", "user.name=Command Fixture", "-c", "user.email=fixture@example.invalid",
                                     "-c", "commit.gpgsign=false", "commit", "-qm", "synthetic excluded inputs"]):
            subprocess.run(["git", *args], cwd=self.root, env=self.env, check=True, capture_output=True, timeout=10)
        self.sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, env=self.env, text=True, timeout=10).strip()
        for gitless in (False, True):
            with self.subTest(gitless=gitless):
                if gitless:
                    shutil.rmtree(self.root / ".git")
                self.engine_calls.unlink(missing_ok=True)
                result = self.run_command("run_gut_validation.sh", self.sha)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
                self.assertTrue(all(call["excluded_present"] == [] for call in calls))
                report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
                self.assertTrue(all(name not in report["source_manifest"] for name in names))

    def test_modified_tracked_source_bytes_are_rejected_before_engine_launch(self):
        path = self.root / "client/player_identity.gd"
        path.write_text("extends Node\n# synthetic tracked modification\n")
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertFalse(self.engine_calls.exists())
        report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertEqual(report["failure_class"], "source_tracked_dirt")

    def test_preparation_timeout_is_retained_in_top_level_failure_summary(self):
        self.env["FAKE_BOOTSTRAP_TIMEOUT"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertTrue(summary["timed_out"])
        self.assertEqual(summary["gut_execution"], "NOT_OBSERVED")
        report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertTrue(report["bootstrap"]["timed_out"])
        self.assertEqual(report["qualification"], "NOT_OBSERVED")

    def test_helper_timeout_exit_survives_an_earlier_non_timeout_phase_report(self):
        for code in (124, 137):
            with self.subTest(code=code):
                helper = self.root / "scripts/prepare_godot_project.py"
                helper.write_text('''import json, sys
from pathlib import Path
arguments = dict(zip(sys.argv[1::2], sys.argv[2::2]))
Path(arguments["--report"]).write_text(json.dumps({
    "schema_version": 1,
    "source_revision": arguments["--source-revision"],
    "prepared_root": arguments["--prepared-root"],
    "prepared_root_created": False, "configuration_custody_lost": False,
    "bootstrap": {"timed_out": False}, "qualification": "NOT_OBSERVED"
}))
raise SystemExit(''' + str(code) + ')\n')
                for arguments in (["add", "scripts/prepare_godot_project.py"],
                                  ["-c", "user.name=Command Fixture", "-c", "user.email=fixture@example.invalid",
                                   "-c", "commit.gpgsign=false", "commit", "-qm", "timeout boundary fixture"]):
                    subprocess.run(["git", *arguments], cwd=self.root, env=self.env,
                                   check=True, capture_output=True, timeout=10)
                result = self.run_command("run_gut_validation.sh")
                self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
                self.assertFalse(self.engine_calls.exists())
                summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
                self.assertTrue(summary["preparation_report_valid"])
                self.assertTrue(summary["timed_out"])
                self.assertEqual(summary["gut_execution"], "NOT_OBSERVED")

    def test_changed_parent_link_rejects_before_qualification_and_preserves_stage(self):
        self.env["FAKE_CLIENT_PARENT_LINK"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        stage = Path(calls[0]["cwd"])
        self.assertTrue((stage / "client").is_symlink())
        self.assertTrue((stage / "detached-client/player_identity.gd").is_file())
        report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertTrue(report["configuration_custody_lost"])
        self.assertEqual(report["qualification"], "NOT_OBSERVED")

    def test_changed_source_parent_link_rejects_before_qualification_and_preserves_stage(self):
        self.env["FAKE_SOURCE_PARENT_LINK"] = "1"
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        stage = Path(calls[0]["cwd"])
        self.assertTrue((self.root / "client").is_symlink())
        self.assertTrue((self.root / "detached-source-client/player_identity.gd").is_file())
        self.assertTrue(stage.is_dir())
        report = json.loads((self.root / "build/validation/preparation-summary.json").read_text())
        self.assertTrue(report["configuration_custody_lost"])
        self.assertEqual(report["qualification"], "NOT_OBSERVED")

    def test_standard_runner_rejects_conflicting_source_before_engine_launch(self):
        result = self.run_command("run_gut_validation.sh", "0" * 40)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.engine_calls.exists())

    def test_standard_runner_rejects_malformed_source_before_engine_launch(self):
        for source in ("", "short", "z" * 40, "a" * 41):
            with self.subTest(source=source):
                result = self.run_command("run_gut_validation.sh", source)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.engine_calls.exists())

    def test_source_artifact_requires_explicit_valid_identity(self):
        shutil.rmtree(self.root / ".git")
        result = self.run_command("run_gut_validation.sh")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.engine_calls.exists())
        for source in ("", "short"):
            with self.subTest(source=source):
                result = self.run_command("run_gut_validation.sh", source)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.engine_calls.exists())
        result = self.run_command("run_gut_validation.sh", self.sha)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.engine_calls.read_text().splitlines()]
        self.assertTrue(all(call["source"] == self.sha for call in calls))

    def test_hosted_command_propagates_verified_source_through_empty_environment(self):
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        run = next(call for call in calls if call[0] == "run")
        env_index = run.index("-i")
        self.assertIn("M4_SOURCE_REVISION=" + self.sha, run[env_index + 1:])
        self.assertIn("TMPDIR=/app/.godot", run[env_index + 1:])
        self.assertFalse(self.engine_calls.exists())

    def test_hosted_command_builds_dependency_image_before_consumer_with_only_recipe_context(self):
        image = "project0-gut-validation:test"
        self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = image
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        build = next(call for call in calls if call[0] == "build")
        run = next(call for call in calls if call[0] == "run")
        self.assertLess(calls.index(build), calls.index(run))
        self.assertEqual(build[-1], str(self.root / "deploy/validation"))
        self.assertIn("--iidfile", build)
        self.assertEqual(build[build.index("--tag") + 1], image)
        self.assertIn("GODOT_IMAGE=ghcr.io/vnvalentin/project0-godot@sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602", build)
        self.assertIn(image, run)
        self.assertNotIn("--push", build)
        self.assertFalse(self.docker_image_state.exists())
        self.assertIn(["image", "rm", image], calls)

    def test_hosted_command_reports_unavailable_image_identity_without_unowned_removal(self):
        self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = "project0-gut-validation:missing-id"
        self.env["FAKE_DOCKER_IMAGE_ID_MISSING"] = "1"
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertEqual(self.docker_image_state.read_text(), "sha256:" + "a" * 64)
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        self.assertFalse(any(call[:2] == ["image", "rm"] for call in calls))
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["stage"], "validation-image-cleanup")

    def test_hosted_command_preserves_preexisting_image_tag(self):
        image = "project0-gut-validation:existing"
        image_id = "sha256:" + "b" * 64
        self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = image
        self.docker_image_state.write_text(image_id)
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 2, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        self.assertFalse(any(call[0] in ("build", "run") for call in calls))
        self.assertFalse(any(call[:2] == ["image", "rm"] for call in calls))
        self.assertEqual(self.docker_image_state.read_text(), image_id)

    def test_hosted_command_does_not_remove_foreign_container_created_after_precheck(self):
        self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = "project0-gut-validation:container-race"
        self.env["FAKE_DOCKER_CONTAINER_RACE"] = "1"
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        foreign = json.loads(self.docker_container_state.read_text())
        self.assertEqual(foreign["label"], "foreign-container")
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        self.assertFalse(any(call[:1] == ["rm"] for call in calls))
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["stage"], "validation-image-cleanup")
        self.assertFalse(summary["container_cleanup_verified"])
        self.assertTrue(summary["validation_image_removed"])

    def test_hosted_command_fails_closed_when_container_inventory_is_unavailable(self):
        self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = "project0-gut-validation:container-list-error"
        self.env["FAKE_DOCKER_CONTAINER_LIST_EXIT"] = "2"
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["stage"], "validation-image-cleanup")
        self.assertFalse(summary["container_cleanup_verified"])
        self.assertTrue(summary["validation_image_removed"])

    def test_hosted_command_preserves_replaced_image_and_fails_cleanup(self):
        self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = "project0-gut-validation:replaced"
        self.env["FAKE_DOCKER_REPLACE_IMAGE"] = "1"
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertEqual(self.docker_image_state.read_text(), "sha256:" + "b" * 64)
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["stage"], "validation-image-cleanup")

    def test_hosted_command_rejects_invalid_image_name_before_docker(self):
        for image in ("--network=host", "project0-gut-validation:",
                      "Project0:tag", "repository//name:tag", "repository:invalid tag"):
            with self.subTest(image=image):
                self.env["PROJECT0_GUT_VALIDATION_IMAGE"] = image
                result = self.run_command("run_hosted_gut_container.sh")
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.docker_calls.exists())

    def test_hosted_build_failure_stops_consumer_and_retains_dependency_evidence(self):
        self.env["FAKE_DOCKER_BUILD_EXIT"] = "7"
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 7, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        self.assertTrue(any(call[0] == "build" for call in calls))
        self.assertFalse(any(call[0] == "run" for call in calls))
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["stage"], "validation-image")
        self.assertEqual(summary["dependency"], "validation-image-python-git")
        self.assertEqual(summary["image_build_exit_code"], 7)
        self.assertEqual(summary["gut_execution"], "NOT_OBSERVED")

    def test_hosted_build_failure_has_static_evidence_without_host_reporter(self):
        self.env["FAKE_DOCKER_BUILD_EXIT"] = "7"
        self.env["PYTHON_BIN"] = str(self.root / "missing-python")
        result = self.run_command("run_hosted_gut_container.sh")
        self.assertEqual(result.returncode, 7, result.stderr + result.stdout)
        calls = [json.loads(line) for line in self.docker_calls.read_text().splitlines()]
        self.assertFalse(any(call[0] == "run" for call in calls))
        summary = json.loads((self.root / "build/validation/validation-summary.json").read_text())
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["stage"], "validation-image")
        self.assertEqual(summary["reporter"], "unavailable")
        self.assertEqual(summary["gut_execution"], "NOT_OBSERVED")

    def test_hosted_command_refuses_invalid_or_conflicting_source_before_container_launch(self):
        for source in ("", "short", "0" * 40):
            with self.subTest(source=source):
                result = self.run_command("run_hosted_gut_container.sh", source)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.docker_calls.exists())

    def test_hosted_command_requires_host_checkout_identity(self):
        shutil.rmtree(self.root / ".git")
        result = self.run_command("run_hosted_gut_container.sh", self.sha)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.docker_calls.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SourceIdentityTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({"passed": result.wasSuccessful(), "tests": result.testsRun,
                                      "failures": len(result.failures), "errors": len(result.errors),
                                      "skipped": len(result.skipped)}, indent=2) + "\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
