"""Build the standalone Mac client from an isolated client-only project (#1353)."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import shlex
import subprocess
import tempfile
import uuid


VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
ROOT = Path(__file__).resolve().parents[2]
ENGINE_VERSION = "4.7.2"


def stage_project(root: Path, destination: Path, version: str) -> None:
    """Prepare a new client tree without importing or changing the source checkout."""
    if not VERSION.fullmatch(version):
        raise ValueError("version must be canonical MAJOR.MINOR.PATCH")
    if destination.exists():
        raise ValueError("staging destination already exists")
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "client", "shared", "project.godot", "server/starting_town_hub_fixture.gd", "addons/com.heroiclabs.nakama", "docs/third-party/nakama-godot-v3.4.0/LICENSE"]).decode().split("\0")
    resources = [name for name in tracked if name and name != "shared/local_llm_client.gd"
                 and (Path(name).suffix in (".gd", ".tscn", ".tres", ".json", ".uid", ".godot")
                      or name == "docs/third-party/nakama-godot-v3.4.0/LICENSE")]
    resources.append("scripts/macos/offline_probe.gd")
    for name in resources:
        source = root / name
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError("source must be a regular repository resource: " + name)
    destination.mkdir(parents=True)
    for name in resources:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, target)
    contract = destination / "shared/client_build_version.gd"
    text, count = re.subn(r'^const CLIENT_BUILD_VERSION: String = "[^"\n]*"',
                         'const CLIENT_BUILD_VERSION: String = "' + version + '"',
                         contract.read_text(), flags=re.MULTILINE)
    if count != 1:
        raise ValueError("client version contract must contain exactly one version assignment")
    contract.write_text(text)
    project = destination / "project.godot"
    text = re.sub(r"\[editor_plugins\][\s\S]*?(?=\n\[|\Z)", "", project.read_text())
    text = text.replace('PackedStringArray("4.3", "Forward Plus")', 'PackedStringArray("4.7", "GL Compatibility")')
    text = text.replace('[rendering]', '[rendering]\ntextures/vram_compression/import_etc2_astc=true')
    project.write_text(text)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1048576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_hashes(root: Path, paths: list[Path]) -> dict[str, str]:
    """Establish custody for every source before reading any evidence bytes."""
    for path in paths:
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("source evidence requires regular repository resources")
    return {path.relative_to(root).as_posix(): sha256(path) for path in paths}


def run(command: list[str], cwd: Path, log: Path, timeout: int = 120) -> str:
    """Bound and retain one owned process group; never evaluate a shell command."""
    environment = {key: value for key, value in os.environ.items()
                   if key in ("HOME", "PATH", "TMPDIR", "LANG", "LC_ALL")}
    with log.open("xb") as handle:
        process = subprocess.Popen(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT,
                                   env=environment, start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
    text = log.read_text(errors="replace")
    diagnostics = text
    if "--log-file" in command:
        engine_log = Path(command[command.index("--log-file") + 1])
        if not engine_log.is_file():
            raise RuntimeError(f"engine did not retain its explicit log: {engine_log}")
        diagnostics += engine_log.read_text(errors="replace")
    if status != 0 or "ERROR:" in diagnostics or "Parse Error:" in diagnostics:
        raise RuntimeError(f"command failed (exit {status}); see {log}")
    return text.strip()


def validate_invocation(root: Path, plan: dict, args: argparse.Namespace) -> None:
    """Bind the actual package operation to the statically reviewed command."""
    steps = [step for step in plan["steps"] if step["suite"] == "macos-client"]
    if len(steps) != 1:
        raise ValueError("exactly one Mac client command is required")
    tokens = shlex.split(steps[0]["command"])[2:]
    if not args.verify or tokens.count("--verify") != 1:
        raise ValueError("reviewed package verification is required")
    tokens.remove("--verify")
    expected = dict(zip(tokens[::2], tokens[1::2]))
    for flag in ("godot", "template", "output", "report"):
        if getattr(args, flag).resolve() != (root / expected["--" + flag]).resolve():
            raise ValueError("package invocation differs from reviewed --" + flag)
    if args.version != expected["--version"]:
        raise ValueError("package invocation differs from reviewed --version")


@contextmanager
def owned_state(report: dict):
    """Create fresh engine/user state and prove its teardown on every exit."""
    temporary = tempfile.TemporaryDirectory(prefix="project0-macos-")
    owned = Path(temporary.name)
    data_name = "Project0MacValidation-" + uuid.uuid4().hex
    data = Path(os.environ["HOME"]) / "Library/Application Support" / data_name
    report["temporary_state_removed"] = False
    created = False
    try:
        data.mkdir(exist_ok=False)
        created = True
        yield owned, data, data_name
    finally:
        try:
            if created:
                shutil.rmtree(data)
        finally:
            try:
                temporary.cleanup()
            finally:
                report["temporary_state_removed"] = not owned.exists() and (not created or not data.exists())


def isolated_settings(name: str) -> str:
    return '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=' + json.dumps(name) + '\n'


def write_preset(stage: Path, template: Path, version: str) -> None:
    template_literal = json.dumps(str(template))
    (stage / "export_presets.cfg").write_text(f'''[preset.0]
name="macOS"
platform="macOS"
runnable=true
export_filter="all_resources"
include_filter="*.json,docs/third-party/nakama-godot-v3.4.0/LICENSE"
exclude_filter="override.cfg"
script_export_mode=2

[preset.0.options]
custom_template/release={template_literal}
custom_template/debug={template_literal}
binary_format/architecture="universal"
application/bundle_identifier="vip.valentin.project0"
application/short_version="{version}"
application/version="{version}"
application/signature="P0MC"
application/app_category="public.app-category.games"
application/min_macos_version_x86_64="10.15"
application/min_macos_version_arm64="11.0"
codesign/codesign=1
notarization/notarization=0
texture_format/s3tc_bptc=true
texture_format/etc2_astc=true
''')


def build(args: argparse.Namespace, report: dict, evidence: Path) -> None:
    import preflight
    manifest = json.loads((ROOT / "scripts/validation_ownership.json").read_text())
    plan = json.loads((ROOT / ".scratch/macos-client/validation-plan.json").read_text())
    errors = preflight.validate_plan(ROOT, manifest, plan, preflight.platform.system(), preflight.socket.gethostname())
    if errors:
        raise ValueError("Mac ownership preflight failed: " + "; ".join(errors))
    validate_invocation(ROOT, plan, args)
    if not VERSION.fullmatch(args.version) or not args.verify:
        raise ValueError("canonical version and --verify are required")
    editor, template = args.godot.resolve(), args.template.resolve()
    output = args.output.resolve()
    if output.exists():
        raise ValueError("package output already exists; choose a new directory")
    if not output.is_relative_to((ROOT / "dist/macos").resolve()):
        raise ValueError("package output must remain beneath dist/macos")
    if not editor.is_file() or not template.is_file():
        raise ValueError("explicit Godot editor and matching Mac template are required")
    report["ownership_sha256"] = sha256(ROOT / "scripts/validation_ownership.json")
    report["plan_sha256"] = sha256(ROOT / ".scratch/macos-client/validation-plan.json")
    report["tools"] = {"editor_sha256": sha256(editor), "template_sha256": sha256(template)}
    version = run([str(editor), "--version"], evidence, evidence / "engine-version.log")
    if not version.startswith(ENGINE_VERSION + ".stable."):
        raise ValueError("Godot 4.7.2 stable editor is required")
    report["tools"]["engine"] = version
    report["source_commit"] = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    report["source_tree_dirty"] = bool(subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain"]))
    sources = []
    for directory in (ROOT / "client", ROOT / "shared", ROOT / "scripts/macos", ROOT / "addons/com.heroiclabs.nakama"):
        if directory.is_symlink() or not directory.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError("source directory must remain inside the repository")
        for source in sorted(directory.rglob("*")):
            if source.is_file() and source.suffix in (".gd", ".tscn", ".tres", ".json", ".py"):
                sources.append(source)
    sources.extend([ROOT / "project.godot", ROOT / "server/starting_town_hub_fixture.gd", ROOT / "docs/third-party/nakama-godot-v3.4.0/LICENSE"])
    report["source_hashes"] = source_hashes(ROOT, sources)
    with owned_state(report) as (owned, user_data, user_data_name):
        portable_app = owned / "editor/Godot.app"
        shutil.copytree(editor.parents[2], portable_app, symlinks=True)
        editor = portable_app / "Contents/MacOS/Godot"
        (editor.parent / "_sc_").touch(exist_ok=False)
        if sha256(editor) != report["tools"]["editor_sha256"]:
            raise ValueError("portable editor copy differs from the qualified tool")
        stage = owned / "client"
        stage_project(ROOT, stage, args.version)
        (stage / "override.cfg").write_text(isolated_settings(user_data_name + "/editor"))
        write_preset(stage, template, args.version)
        staged = owned / "export/Project0.app"
        staged.parent.mkdir()
        run([str(editor), "--headless", "--path", str(stage), "--import", "--log-file", str(evidence / "import-engine.log")],
            stage, evidence / "import.log", 180)
        run([str(editor), "--headless", "--path", str(stage), "--export-release", "macOS", str(staged),
             "--log-file", str(evidence / "export-engine.log")], stage, evidence / "export.log", 180)
        executable = staged / "Contents/MacOS/Project0"
        if not executable.is_file():
            raise ValueError("Godot did not produce a standalone app executable")
        architectures = run(["/usr/bin/lipo", "-archs", str(executable)], owned, evidence / "architectures.log")
        if set(architectures.split()) != {"x86_64", "arm64"}:
            raise ValueError("Mac app must contain both Apple silicon and Intel architectures")
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged)], owned, evidence / "codesign.log")
        packs = list(staged.rglob("*.pck"))
        if len(packs) != 1:
            raise ValueError("app must contain exactly one client PCK")
        inspector = owned / "inspector"
        inspector.mkdir()
        (inspector / "project.godot").write_text('config_version=5\n' + isolated_settings(user_data_name + "/inspector") + 'config/name="Project0 Mac Package Inspector"\n')
        shutil.copyfile(ROOT / "scripts/macos/package_inventory.gd", inspector / "package_inventory.gd")
        inventory_path = evidence / "inventory.json"
        run([str(editor), "--headless", "--path", str(inspector), "--script", "package_inventory.gd", "--",
             str(packs[0]), str(inventory_path), str(ROOT / "scripts/validation_ownership.json"), ENGINE_VERSION],
            inspector, evidence / "inventory.log")
        inventory = json.loads(inventory_path.read_text())
        if inventory.get("passed") is not True or inventory.get("client_files", 0) <= 0:
            raise ValueError("client package inventory failed")
        probe_path = evidence / "offline-probe.json"
        override = executable.parent / "override.cfg"
        override.write_text(isolated_settings(user_data_name + "/probe") + 'run/main_loop_type="MacOfflineProbe"\nrun/main_scene=""\n')
        try:
            run([str(executable), "--log-file", str(evidence / "probe-engine.log"), "--",
                 "--evidence=" + str(probe_path), "--expected-version=" + args.version,
                 "--expected-user-data=" + str(user_data / "probe")], staged.parent, evidence / "offline-probe.log", 60)
        finally:
            override.unlink()
        probe = json.loads(probe_path.read_text())
        if probe.get("passed") is not True or probe.get("paired_runtime_acceptance") is not False:
            raise ValueError("native offline probe failed")
        override.write_text(isolated_settings(user_data_name + "/startup"))
        try:
            run([str(executable), "--quit-after", "90", "--log-file", str(evidence / "startup-engine.log")],
                staged.parent, evidence / "startup.log", 60)
        finally:
            override.unlink()
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged)], owned, evidence / "codesign-after-probe.log")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.mkdir()
        app = output / "Project0.app"
        shutil.copytree(staged, app, symlinks=True)
        archive = output / f"Project0-client-macos-universal-{args.version}.zip"
        run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)],
            output, evidence / "archive.log")
        report.update({"architectures": sorted(architectures.split()), "app": str(app),
                       "archive": str(archive), "archive_sha256": sha256(archive),
                       "executable_sha256": sha256(app / "Contents/MacOS/Project0"),
                       "pck_sha256": sha256(packs[0]), "inventory_sha256": sha256(inventory_path),
                       "probe_sha256": sha256(probe_path), "codesign": "ad-hoc verified; not notarized",
                       "native_offline_probe_passed": True, "native_account_startup_passed": True})
    report["passed"] = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    report_path = args.report.resolve()
    if not report_path.is_relative_to((ROOT / "build/validation/macos").resolve()) or report_path.exists():
        parser.error("report requires a new path beneath build/validation/macos")
    evidence = report_path.with_suffix("")
    if evidence.exists():
        parser.error("evidence directory already exists")
    evidence.mkdir(parents=True)
    report = {"schema_version": 1, "issue": 1353, "passed": False, "version": args.version,
              "timestamp_utc": datetime.now(timezone.utc).isoformat(), "command": os.sys.argv,
              "platform": "macos", "host": os.uname().nodename, "paired_acceptance": False,
              "intel_runtime_acceptance": False, "full_regression": "awaiting Linux and Windows access"}
    try:
        build(args, report, evidence)
    except Exception as error:
        report["error"] = str(error)
    finally:
        report["evidence_hashes"] = {path.name: sha256(path) for path in evidence.iterdir() if path.is_file()}
        with report_path.open("x") as handle:
            json.dump(report, handle, indent=2)
            handle.write("\n")
    print(json.dumps({key: report[key] for key in ("passed", "version", "platform", "full_regression")}))
    if not report["passed"]:
        print(report.get("error", "build failed"))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
