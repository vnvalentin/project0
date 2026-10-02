"""Mac-only regression at the client staging and packaging seams (#1353)."""
import argparse
import configparser
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import platform
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


class PackageTests(unittest.TestCase):
    def test_staged_client_excludes_server_runtime_and_preserves_source_version(self):
        spec = importlib.util.spec_from_file_location("macos_package", Path(__file__).with_name("package.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        source_version = (ROOT / "shared/client_build_version.gd").read_bytes()
        with tempfile.TemporaryDirectory(prefix="project0-macos-test-") as temporary:
            stage = Path(temporary) / "client"
            module.stage_project(ROOT, stage, "0.12.0")
            self.assertTrue((stage / "client/account_gate.tscn").is_file())
            self.assertTrue((stage / "server/starting_town_hub_fixture.gd").is_file())
            self.assertFalse((stage / "server/server_main.gd").exists())
            self.assertFalse((stage / "addons/godot-sqlite").exists())
            self.assertFalse((stage / "addons/gut").exists())
            self.assertTrue((stage / "addons/com.heroiclabs.nakama/Nakama.gd").is_file())
            self.assertTrue((stage / "docs/third-party/nakama-godot-v3.4.0/LICENSE").is_file())
            self.assertFalse((stage / "shared/local_llm_client.gd").exists())
            self.assertFalse((stage / "native").exists())
            self.assertFalse((stage / "tests").exists())
            self.assertEqual((ROOT / "shared/client_build_version.gd").read_bytes(), source_version)


class StagingControlTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-stage-control-")
        self.addCleanup(temporary.cleanup)
        self.temporary = Path(temporary.name)
        self.source = self.temporary / "source"
        self.stage = self.temporary / "client"
        self.source.mkdir()
        self.package = load_module("package")
        self.files = {
            "project.godot": 'config_version=5\n[application]\nconfig/name="Fixture"\nconfig/features=PackedStringArray("4.3", "Forward Plus")\n[editor_plugins]\nenabled=PackedStringArray("res://addons/gut/plugin.cfg")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
            "client/account_gate.tscn": '[gd_scene format=3]\n[node name="Gate" type="Control"]\n',
            "shared/client_build_version.gd": 'extends RefCounted\nconst CLIENT_BUILD_VERSION: String = "1.2.3"\n',
            "shared/local_llm_client.gd": "# server-only fixture\n",
            "server/starting_town_hub_fixture.gd": "extends RefCounted\n",
            "server/server_main.gd": "# authoritative server fixture\n",
            "addons/gut/plugin.cfg": "[plugin]\nname=\"Fixture\"\n",
            "addons/godot-sqlite/gdsqlite.gdextension": "[configuration]\nentry_symbol=\"fixture_sqlite\"\n",
            "addons/com.heroiclabs.nakama/Nakama.gd": "extends RefCounted\n",
            "addons/com.heroiclabs.nakama/bin/native.dylib": "owned negative-control bytes\n",
            "addons/com.heroiclabs.nakama/native.gdextension": "[configuration]\nentry_symbol=\"fixture_native\"\n",
            "docs/third-party/nakama-godot-v3.4.0/LICENSE": "Fixture SDK license notice retained.\n",
            ".godot/extension_list.cfg": 'res://addons/godot-sqlite/gdsqlite.gdextension\n',
            "scripts/macos/offline_probe.gd": "extends SceneTree\n",
        }
        for name, contents in self.files.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")
        subprocess.run(["git", "-c", "init.templateDir=", "init", "-q", str(self.source)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.source), "-c", "core.fsmonitor=false", "add", "--force", "--", *self.files], check=True, capture_output=True)

    def source_bytes(self):
        return {name: (self.source / name).read_bytes() for name in self.files}

    def test_malformed_versions_reject_without_creating_stage_or_changing_source(self):
        before = self.source_bytes()
        for version in ("", "1.2", "01.2.3", "1.2.3-beta", "1.2.3\n", "-1.2.3"):
            with self.subTest(version=version):
                with self.assertRaises(ValueError):
                    self.package.stage_project(self.source, self.stage, version)
                self.assertFalse(self.stage.exists())
                self.assertEqual(self.source_bytes(), before)

    def test_occupied_stage_preserves_existing_files_and_source(self):
        self.stage.mkdir()
        sentinel = self.stage / "keep.txt"
        sentinel.write_bytes(b"existing package is preserved\n")
        before = self.source_bytes()
        with self.assertRaises(ValueError):
            self.package.stage_project(self.source, self.stage, "4.5.6")
        self.assertEqual(sentinel.read_bytes(), b"existing package is preserved\n")
        self.assertEqual(list(self.stage.iterdir()), [sentinel])
        self.assertEqual(self.source_bytes(), before)

    def test_symlink_source_is_rejected_before_staging(self):
        external = self.temporary / "external-fixture.txt"
        external.write_bytes(b"owned symlink target\n")
        gate = self.source / "client/account_gate.tscn"
        gate.unlink()
        gate.symlink_to(external)
        with self.assertRaises(ValueError):
            self.package.stage_project(self.source, self.stage, "4.5.6")
        self.assertFalse(self.stage.exists())
        self.assertTrue(gate.is_symlink())
        self.assertEqual(external.read_bytes(), b"owned symlink target\n")

    def test_changed_staged_version_preserves_every_source_resource(self):
        before = self.source_bytes()
        self.package.stage_project(self.source, self.stage, "4.5.6")
        self.assertIn('const CLIENT_BUILD_VERSION: String = "4.5.6"', (self.stage / "shared/client_build_version.gd").read_text())
        self.assertEqual((self.source / "shared/client_build_version.gd").read_text(), 'extends RefCounted\nconst CLIENT_BUILD_VERSION: String = "1.2.3"\n')
        self.assertEqual(self.source_bytes(), before)

    def test_staged_project_keeps_pure_sdk_without_editor_or_server_extensions(self):
        self.package.stage_project(self.source, self.stage, "4.5.6")
        project = (self.stage / "project.godot").read_text()
        self.assertNotIn("[editor_plugins]", project)
        self.assertNotIn("res://addons/gut/plugin.cfg", project)
        self.assertTrue((self.stage / "addons/com.heroiclabs.nakama/Nakama.gd").is_file())
        for name in (
            "addons/gut", "addons/godot-sqlite", ".godot/extension_list.cfg",
            "server/server_main.gd", "shared/local_llm_client.gd",
            "addons/com.heroiclabs.nakama/bin/native.dylib",
            "addons/com.heroiclabs.nakama/native.gdextension",
        ):
            with self.subTest(resource=name):
                self.assertFalse((self.stage / name).exists())

    def test_mac_export_settings_use_explicit_universal_release_template(self):
        before = self.source_bytes()
        template = self.temporary / "qualified templates" / "macos.zip"
        template.parent.mkdir()
        template.write_bytes(b"owned template-path fixture\n")
        self.package.stage_project(self.source, self.stage, "4.5.6")
        self.package.write_preset(self.stage, template, "4.5.6")
        preset = configparser.ConfigParser(interpolation=None)
        preset.read(self.stage / "export_presets.cfg")
        options = preset["preset.0.options"]
        self.assertEqual(json.loads(options.get("custom_template/debug", '""')), str(template))
        self.assertEqual(json.loads(options.get("custom_template/release", '""')), str(template))
        self.assertEqual(options.get("binary_format/architecture"), '"universal"')
        self.assertEqual(options.get("application/app_category"), '"public.app-category.games"')
        self.assertEqual(preset["preset.0"].get("script_export_mode"), "2")
        self.assertTrue(options.getboolean("texture_format/etc2_astc", fallback=False))
        project = configparser.ConfigParser(interpolation=None)
        project_source = (self.stage / "project.godot").read_text()
        self.assertTrue(project_source.startswith("config_version=5\n"))
        project.read_string(project_source.removeprefix("config_version=5\n"))
        self.assertTrue(project.getboolean("rendering", "textures/vram_compression/import_etc2_astc", fallback=False))
        self.assertEqual(self.source_bytes(), before)

    def test_sdk_license_is_retained_and_included_in_the_package_preset(self):
        self.package.stage_project(self.source, self.stage, "4.5.6")
        license_path = "docs/third-party/nakama-godot-v3.4.0/LICENSE"
        self.assertEqual((self.stage / license_path).read_text(), "Fixture SDK license notice retained.\n")
        self.package.write_preset(self.stage, self.temporary / "macos.zip", "4.5.6")
        preset = configparser.ConfigParser(interpolation=None)
        preset.read(self.stage / "export_presets.cfg")
        include_filter = json.loads(preset["preset.0"]["include_filter"])
        self.assertIn(license_path, include_filter.split(","))


class PreflightTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-plan-control-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.preflight = load_module("preflight")
        self.manifest = json.loads((ROOT / "scripts/validation_ownership.json").read_text())
        for name in ("scripts/macos/test_package.py", "scripts/macos/package_inventory.gd", "scripts/macos/offline_probe.gd"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# owned fixture\n", encoding="utf-8")
        self.plan = {
            "schema_version": 1, "kind": "component",
            "steps": [
                {
                    "suite": "macos-tooling", "platform": "macos", "host": "Philips-MacBook-Pro-2",
                    "command": "python3 scripts/macos/test_package.py --report build/validation/macos/unit.json",
                    "dependencies": ["python", "git"], "tests": ["scripts/macos/test_package.py"],
                    "artifacts": ["build/validation/macos/unit.json"],
                },
                {
                    "suite": "macos-client", "platform": "macos", "host": "Philips-MacBook-Pro-2",
                    "command": "python3 scripts/macos/package.py --godot build/tools/godot/Godot.app/Contents/MacOS/Godot --template build/tools/godot/templates/macos.zip --version 0.12.0 --output dist/macos/control --verify --report build/validation/macos/client.json",
                    "dependencies": ["godot-client", "python", "git"],
                    "tests": ["scripts/macos/package_inventory.gd", "scripts/macos/offline_probe.gd"],
                    "artifacts": ["build/validation/macos/client.json"],
                },
            ],
        }

    def check(self, plan=None, manifest=None, host="Philips-MacBook-Pro-2.local", operating_system="Darwin"):
        return self.preflight.validate_plan(self.root, self.manifest if manifest is None else manifest, self.plan if plan is None else plan, operating_system, host)

    def test_actual_agreed_mac_plan_passes_static_validation(self):
        plan = json.loads((ROOT / ".scratch/macos-client/validation-plan.json").read_text())
        errors = self.preflight.validate_plan(ROOT, self.manifest, plan, "Darwin", "Philips-MacBook-Pro-2.local")
        self.assertEqual(errors, [])

    def test_literal_mac_component_fixture_passes(self):
        self.assertEqual(self.check(), [])

    def test_unassigned_observed_or_planned_host_is_refused(self):
        self.assertTrue(self.check(host="Unassigned-Mac"))
        self.assertTrue(self.check(operating_system="Linux"))
        plan = deepcopy(self.plan)
        plan["steps"][0]["host"] = "Unassigned-Mac"
        self.assertTrue(self.check(plan))

    def test_linux_suite_cannot_move_to_the_mac(self):
        plan = deepcopy(self.plan)
        plan["steps"][0]["suite"] = "linux-tooling"
        self.assertTrue(self.check(plan))

    def test_server_dependencies_are_refused_even_with_spaces_and_case(self):
        for dependency in ("sqlite", "canon", "ollama", " SQLite ", " CANON ", " Ollama "):
            with self.subTest(dependency=dependency):
                plan = deepcopy(self.plan)
                plan["steps"][1]["dependencies"].append(dependency)
                self.assertTrue(self.check(plan))

    def test_missing_required_dependencies_are_refused(self):
        plan = deepcopy(self.plan)
        plan["steps"][1]["dependencies"] = ["python", "git"]
        self.assertTrue(self.check(plan))

    def test_paired_runtime_cannot_be_claimed_from_mac_components(self):
        plan = deepcopy(self.plan)
        plan["kind"] = "paired-runtime"
        self.assertTrue(self.check(plan))

    def test_shell_chaining_and_substitutions_are_refused(self):
        for suffix in (" ; echo chained", " && echo chained", " | echo chained", " $(echo substituted)", " `echo substituted`"):
            with self.subTest(suffix=suffix):
                plan = deepcopy(self.plan)
                plan["steps"][0]["command"] += suffix
                self.assertTrue(self.check(plan))

    def test_evidence_cannot_escape_owned_mac_validation_paths(self):
        for path in ("../escaped.json", "build/validation/linux/control.json", "build/validation/macos/*.json"):
            with self.subTest(path=path):
                plan = deepcopy(self.plan)
                plan["steps"][0]["artifacts"] = [path]
                plan["steps"][0]["command"] = "python3 scripts/macos/test_package.py --report " + path
                self.assertTrue(self.check(plan))

    def test_conflicting_test_ownership_is_refused(self):
        manifest = deepcopy(self.manifest)
        manifest["suites"]["linux-tooling"]["tests"].append("scripts/macos/test_package.py")
        self.assertTrue(self.check(manifest=manifest))


class PackageInvocationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-invocation-control-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.package = load_module("package")
        killpg = mock.patch.object(self.package.os, "killpg", side_effect=ProcessLookupError)
        self.killpg = killpg.start()
        self.addCleanup(killpg.stop)
        self.plan = {
            "schema_version": 1, "kind": "component",
            "steps": [{
                "suite": "macos-client", "platform": "macos", "host": "Philips-MacBook-Pro-2",
                "command": "python3 scripts/macos/package.py --godot build/tools/godot/Godot.app/Contents/MacOS/Godot --template build/tools/godot/templates/macos.zip --version 0.12.0 --output dist/macos/control --verify --report build/validation/macos/client.json",
                "dependencies": ["godot-client", "python", "git"],
                "tests": ["scripts/macos/package_inventory.gd", "scripts/macos/offline_probe.gd"],
                "artifacts": ["build/validation/macos/client.json"],
            }],
        }
        self.args = argparse.Namespace(
            godot=self.root / "build/tools/godot/Godot.app/Contents/MacOS/Godot",
            template=self.root / "build/tools/godot/templates/macos.zip",
            version="0.12.0", output=self.root / "dist/macos/control", verify=True,
            report=self.root / "build/validation/macos/client.json",
        )
        for tool in (self.args.godot, self.args.template):
            tool.parent.mkdir(parents=True, exist_ok=True)
            tool.write_bytes(b"owned tool-path fixture, never executed\n")

    def test_exact_package_invocation_matches_the_reviewed_plan(self):
        self.package.validate_invocation(self.root, self.plan, self.args)

    def test_changed_package_inputs_or_evidence_are_refused_before_launch(self):
        changes = {
            "godot": self.root / "build/tools/godot/other-editor",
            "template": self.root / "build/tools/godot/templates/other.zip",
            "version": "0.12.1",
            "output": self.root / "dist/macos/unplanned",
            "report": self.root / "build/validation/macos/unplanned.json",
            "verify": False,
        }
        for field, value in changes.items():
            with self.subTest(field=field):
                args = deepcopy(self.args)
                setattr(args, field, value)
                with self.assertRaises(ValueError):
                    self.package.validate_invocation(self.root, self.plan, args)

    def test_generic_engine_error_rejects_even_a_zero_process_exit(self):
        log = self.root / "engine-error.log"

        def fixture_process(command, **options):
            options["stdout"].write(b"ERROR: Failed to open the export template.\n")
            options["stdout"].flush()
            process = mock.Mock()
            process.pid = 43123
            process.wait.return_value = 0
            return process

        with mock.patch.object(self.package.subprocess, "Popen", side_effect=fixture_process) as launch:
            with self.assertRaises(RuntimeError):
                self.package.run(["owned-fixture-engine"], self.root, log)
        self.assertEqual(launch.call_count, 1)
        self.assertEqual(log.read_bytes(), b"ERROR: Failed to open the export template.\n")

    def test_successful_fixture_process_retains_its_log_and_returns_output(self):
        log = self.root / "engine-success.log"

        def fixture_process(command, **options):
            options["stdout"].write(b"Fixture export completed.\n")
            options["stdout"].flush()
            process = mock.Mock()
            process.pid = 43123
            process.wait.return_value = 0
            return process

        with mock.patch.object(self.package.subprocess, "Popen", side_effect=fixture_process) as launch:
            output = self.package.run(["owned-fixture-engine"], self.root, log)
        self.assertEqual(launch.call_count, 1)
        self.assertEqual(output, "Fixture export completed.")
        self.assertEqual(log.read_bytes(), b"Fixture export completed.\n")

    def test_error_only_in_explicit_engine_log_rejects_a_zero_process_exit(self):
        stdout_log = self.root / "stdout.log"
        engine_log = self.root / "explicit-engine.log"

        def fixture_process(command, **options):
            options["stdout"].write(b"Fixture engine exited normally.\n")
            options["stdout"].flush()
            engine_log.write_bytes(b"ERROR: Engine resource loading failed.\n")
            process = mock.Mock()
            process.pid = 43123
            process.wait.return_value = 0
            return process

        with mock.patch.object(self.package.subprocess, "Popen", side_effect=fixture_process) as launch:
            with self.assertRaises(RuntimeError):
                self.package.run(["owned-fixture-engine", "--log-file", str(engine_log)], self.root, stdout_log)
        self.assertEqual(launch.call_count, 1)
        self.assertEqual(stdout_log.read_bytes(), b"Fixture engine exited normally.\n")
        self.assertEqual(engine_log.read_bytes(), b"ERROR: Engine resource loading failed.\n")

    def test_owned_state_cleans_up_after_failure_and_preserves_existing_state(self):
        fake_home = self.root / "fixture-home"
        application_support = fake_home / "Library/Application Support"
        application_support.mkdir(parents=True)
        existing = application_support / "existing-profile.txt"
        existing.write_bytes(b"existing user state is preserved\n")
        report = {}
        fixture_os = SimpleNamespace(environ={"HOME": str(fake_home)})
        with mock.patch.object(self.package, "os", fixture_os):
            with self.assertRaisesRegex(ValueError, "owned fixture failure"):
                with self.package.owned_state(report) as (owned, user_data, name):
                    (owned / "temporary.txt").write_text("owned staging fixture\n")
                    (user_data / "temporary.txt").write_text("owned user-state fixture\n")
                    self.assertTrue(user_data.is_relative_to(application_support))
                    self.assertEqual(user_data.name, name)
                    raise ValueError("owned fixture failure")
        self.assertTrue(report["temporary_state_removed"])
        self.assertFalse(owned.exists())
        self.assertFalse(user_data.exists())
        self.assertEqual(existing.read_bytes(), b"existing user state is preserved\n")

    def test_source_hashing_rejects_symlinks_before_reading_any_selected_bytes(self):
        regular = self.root / "client/known.gd"
        regular.parent.mkdir()
        regular.write_bytes(b"abc")
        linked = self.root / "client/linked.gd"
        linked.symlink_to(regular)
        with mock.patch.object(self.package, "sha256", wraps=self.package.sha256) as digest:
            with self.assertRaises(ValueError):
                self.package.source_hashes(self.root, [regular, linked])
            digest.assert_not_called()
        self.assertEqual(self.package.source_hashes(self.root, [regular]), {
            "client/known.gd": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        })


class PackageProcessCleanupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-process-control-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.package = load_module("package")
        self.log = self.root / "fixture.log"
        self.process = mock.Mock(pid=43123)

    def launch(self, command, **options):
        options["stdout"].write(b"Owned synthetic process output.\n")
        options["stdout"].flush()
        return self.process

    def removed_group(self, pid, signal):
        if signal == 0:
            raise ProcessLookupError

    def test_normal_parent_exit_kills_and_verifies_the_owned_group_before_returning(self):
        self.process.wait.return_value = 0
        with mock.patch.object(self.package.subprocess, "Popen", side_effect=self.launch) as launch, \
                mock.patch.object(self.package.os, "killpg", side_effect=self.removed_group) as killpg:
            result = self.package.run(["owned-fixture"], self.root, self.log, 3)
        self.assertEqual(result, "Owned synthetic process output.")
        self.assertEqual(killpg.call_args_list, [mock.call(43123, self.package.signal.SIGKILL), mock.call(43123, 0)])
        self.assertEqual(self.process.wait.call_args_list, [mock.call(timeout=3), mock.call(timeout=5)])
        self.assertTrue(launch.call_args.kwargs["start_new_session"])

    def test_nonzero_parent_exit_preserves_status_after_group_cleanup(self):
        self.process.wait.return_value = 7
        with mock.patch.object(self.package.subprocess, "Popen", side_effect=self.launch), \
                mock.patch.object(self.package.os, "killpg", side_effect=self.removed_group) as killpg:
            with self.assertRaisesRegex(RuntimeError, "exit 7"):
                self.package.run(["owned-fixture"], self.root, self.log, 3)
        self.assertEqual(killpg.call_args_list, [mock.call(43123, self.package.signal.SIGKILL), mock.call(43123, 0)])
        self.assertEqual(self.process.wait.call_args_list, [mock.call(timeout=3), mock.call(timeout=5)])
        self.assertEqual(self.log.read_bytes(), b"Owned synthetic process output.\n")

    def test_timeout_and_exceptional_parent_waits_reap_and_verify_before_propagating(self):
        for index, failure in enumerate((subprocess.TimeoutExpired(["owned-fixture"], 3), ValueError("owned fixture failure"), KeyboardInterrupt())):
            with self.subTest(failure=type(failure).__name__):
                self.process.wait.reset_mock()
                self.process.wait.side_effect = [failure, -9]
                with mock.patch.object(self.package.subprocess, "Popen", side_effect=self.launch), \
                        mock.patch.object(self.package.os, "killpg", side_effect=self.removed_group) as killpg:
                    with self.assertRaises(type(failure)) as observed:
                        self.package.run(["owned-fixture"], self.root, self.root / (str(index) + ".log"), 3)
                self.assertIs(observed.exception, failure)
                self.assertEqual(killpg.call_args_list, [mock.call(43123, self.package.signal.SIGKILL), mock.call(43123, 0)])
                self.assertEqual(self.process.wait.call_args_list, [mock.call(timeout=3), mock.call(timeout=5)])

    def test_unverified_group_cleanup_refuses_a_successful_parent_exit(self):
        self.process.wait.return_value = 0
        with mock.patch.object(self.package.subprocess, "Popen", side_effect=self.launch), \
                mock.patch.object(self.package.os, "killpg", return_value=None) as killpg, \
                mock.patch.object(self.package.time, "monotonic", side_effect=[0, 0, 3]), \
                mock.patch.object(self.package.time, "sleep") as sleep:
            with self.assertRaisesRegex(RuntimeError, "process group cleanup"):
                self.package.run(["owned-fixture"], self.root, self.log, 3)
        self.assertEqual(killpg.call_args_list, [mock.call(43123, self.package.signal.SIGKILL), mock.call(43123, 0)])
        self.assertEqual(self.process.wait.call_args_list, [mock.call(timeout=3), mock.call(timeout=5)])
        sleep.assert_called_once_with(0.02)

    def test_signalling_failure_still_reaps_and_refuses_success(self):
        self.process.wait.return_value = 0
        failure = PermissionError("owned synthetic signalling failure")
        with mock.patch.object(self.package.subprocess, "Popen", side_effect=self.launch), \
                mock.patch.object(self.package.os, "killpg", side_effect=failure):
            with self.assertRaises(PermissionError) as observed:
                self.package.run(["owned-fixture"], self.root, self.log, 3)
        self.assertIs(observed.exception, failure)
        self.assertEqual(self.process.wait.call_args_list, [mock.call(timeout=3), mock.call(timeout=5)])


class PackageBuildCleanupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="project0-macos-build-control-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.package = load_module("package")
        self.files = {
            "project.godot": 'config_version=5\n[application]\nconfig/name="Fixture"\n[rendering]\n',
            "client/account_gate.gd": "extends Control\n",
            "shared/client_build_version.gd": 'extends RefCounted\nconst CLIENT_BUILD_VERSION: String = "0.12.0"\n',
            "server/starting_town_hub_fixture.gd": "extends RefCounted\n",
            "docs/third-party/nakama-godot-v3.4.0/LICENSE": "Owned synthetic notice.\n",
            "scripts/macos/offline_probe.gd": "extends SceneTree\n",
            "scripts/macos/package_inventory.gd": "extends SceneTree\n",
        }
        for name, contents in self.files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        self.args = argparse.Namespace(
            godot=self.root / "build/tools/godot/Godot.app/Contents/MacOS/Godot",
            template=self.root / "build/tools/godot/templates/macos.zip", version="0.12.0",
            output=self.root / "dist/macos/control", verify=True,
            report=self.root / "build/validation/macos/client.json",
        )
        for tool in (self.args.godot, self.args.template):
            tool.parent.mkdir(parents=True, exist_ok=True)
            tool.write_bytes(b"Owned synthetic tool, never executed.\n")
        selected = ["scripts/macos/package_inventory.gd", "scripts/macos/offline_probe.gd"]
        manifest = {"schema_version": 1, "hosts": {"macos": ["Philips-MacBook-Pro-2"]},
                    "server_dependencies": ["sqlite", "canon", "ollama"],
                    "suites": {"macos-client": {"platform": "macos", "dependencies": ["godot-client", "python", "git"], "tests": selected}}}
        (self.root / "scripts/validation_ownership.json").write_text(json.dumps(manifest))
        plan = {"schema_version": 1, "kind": "component", "steps": [{
            "suite": "macos-client", "platform": "macos", "host": "Philips-MacBook-Pro-2",
            "command": "python3 scripts/macos/package.py --godot build/tools/godot/Godot.app/Contents/MacOS/Godot --template build/tools/godot/templates/macos.zip --version 0.12.0 --output dist/macos/control --verify --report build/validation/macos/client.json",
            "dependencies": ["godot-client", "python", "git"], "tests": selected,
            "artifacts": ["build/validation/macos/client.json"],
        }]}
        plan_path = self.root / ".scratch/macos-client/validation-plan.json"
        plan_path.parent.mkdir(parents=True)
        plan_path.write_text(json.dumps(plan))
        self.home = self.root / "fixture-home"
        (self.home / "Library/Application Support").mkdir(parents=True)
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()

    def query(self, command, **options):
        if "ls-files" in command:
            return "\0".join(name for name in self.files if not name.startswith("scripts/")).encode()
        if "rev-parse" in command:
            return "f" * 40 + "\n"
        if "status" in command:
            return b""
        self.fail("unexpected synthetic Git query")

    def launch(self, command, **options):
        output = b""
        if "--version" in command:
            output = b"4.7.2.stable.official.ed1daf0bf\n"
        elif "--export-release" in command:
            app = Path(command[command.index("--export-release") + 2])
            executable = app / "Contents/MacOS/Project0"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"Owned synthetic release executable, never executed.\n")
            pack = app / "Contents/Resources/Project0.pck"
            pack.parent.mkdir(parents=True)
            pack.write_bytes(b"Owned synthetic client PCK, never executed.\n")
        elif command[0] == "/usr/bin/lipo":
            output = b"arm64 x86_64\n"
        elif "package_inventory.gd" in command:
            Path(command[command.index("--") + 2]).write_text(json.dumps({"passed": True, "client_files": 1}))
        elif any(value.startswith("--evidence=") for value in command):
            path = next(value.removeprefix("--evidence=") for value in command if value.startswith("--evidence="))
            Path(path).write_text(json.dumps({"passed": True, "paired_runtime_acceptance": False}))
        elif command[0] == "/usr/bin/ditto":
            Path(command[-1]).write_bytes(b"Owned synthetic archive.\n")
        elif "--import" not in command and "--quit-after" not in command and command[0] != "/usr/bin/codesign":
            self.fail("unexpected synthetic native command")
        if "--log-file" in command:
            Path(command[command.index("--log-file") + 1]).write_bytes(b"")
        options["stdout"].write(output)
        options["stdout"].flush()
        process = mock.Mock(pid=43123)
        process.wait.return_value = 0
        return process

    def build(self, report):
        import preflight
        with mock.patch.object(self.package, "ROOT", self.root), \
                mock.patch.dict(self.package.os.environ, {"HOME": str(self.home)}), \
                mock.patch.object(self.package.subprocess, "check_output", side_effect=self.query), \
                mock.patch.object(self.package.subprocess, "Popen", side_effect=self.launch) as launch, \
                mock.patch.object(self.package.os, "killpg", side_effect=ProcessLookupError), \
                mock.patch.object(preflight.platform, "system", return_value="Darwin"), \
                mock.patch.object(preflight.socket, "gethostname", return_value="Philips-MacBook-Pro-2"):
            self.package.build(self.args, report, self.evidence)
        self.assertGreater(launch.call_count, 0)
        self.assertEqual(list((self.home / "Library/Application Support").iterdir()), [])
        self.assertTrue((self.args.output / "Project0.app").is_dir())

    def test_public_build_refuses_an_aggregate_failed_cleanup_after_native_steps_pass(self):
        report = {"passed": False, "cleanup_receipts": [False]}
        self.build(report)
        self.assertTrue(report["native_offline_probe_passed"])
        self.assertTrue(report["native_account_startup_passed"])
        self.assertFalse(report["temporary_state_removed"])
        self.assertEqual(report["cleanup_receipts"], [False, True])
        self.assertFalse(report["passed"])

    def test_public_build_passes_only_with_verified_aggregate_cleanup(self):
        report = {"passed": False, "cleanup_receipts": [True]}
        self.build(report)
        self.assertTrue(report["temporary_state_removed"])
        self.assertEqual(report["cleanup_receipts"], [True, True])
        self.assertTrue(report["passed"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        parser.error("report already exists; choose a new evidence path")
    suites = [unittest.defaultTestLoader.loadTestsFromTestCase(case) for case in (PackageTests, StagingControlTests, PreflightTests, PackageInvocationTests, PackageProcessCleanupTests, PackageBuildCleanupTests)]
    selected = [test.id() for suite in suites for test in suite]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(suites))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    passed = result.wasSuccessful() and not result.skipped and result.testsRun == len(selected)
    with args.report.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps({"issue": 1353, "platform": "macos", "os": platform.system(), "host": socket.gethostname(), "passed": passed,
        "tests_run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
        "skipped": len(result.skipped), "selected_tests": selected, "runtime_acceptance": False}, indent=2) + "\n")
    return int(not passed)


if __name__ == "__main__":
    raise SystemExit(main())
