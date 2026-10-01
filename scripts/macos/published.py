"""Create a Mac shell around the exact published 0.14.20 client pack (#1353)."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import socket
import stat
import subprocess
import time
import urllib.request
import zipfile

import admission
import package
import preflight


ROOT = Path(__file__).resolve().parents[2]
VERSION = "0.14.20"
BASE_URL = "https://project0.valentin.vip/patches/downloads/0.14.20/"
MANIFEST_URL = BASE_URL + "deployment-manifest.json"
ARCHIVE_NAME = "Project0-client-windows-x64-0.14.20.zip"
ARCHIVE_URL = BASE_URL + ARCHIVE_NAME
ARCHIVE_RECORD = {"name": ARCHIVE_NAME, "bytes": 39750225,
                  "sha256": "B6B723935797F0388A18D2C7A60185FD3723103DEDBE21A5CCB773462A130BCC"}
MEMBER_RECORDS = [
    {"name": "Project0.exe", "bytes": 109268480, "sha256": "806CD5D973EF6E0B4FAE2791C3CD9D7327908866FF590336810189A83C018F42"},
    {"name": "Project0.pck", "bytes": 624120, "sha256": "1F75603889ED79412286FC2CC8C79636244E05ACBDBE16D6FF1CFD1FDA31F94A"},
]
MAX_TOTAL_BYTES = 160 * 1024 * 1024
MAX_COMPRESSION_RATIO = 400
QUALIFIED_TOOL_HASHES = {
    "editor": "c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf",
    "template": "88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792",
}
NAKAMA_LICENSE = "docs/third-party/nakama-godot-v3.4.0/LICENSE"
SELECTED = {"scripts/macos/published.py", "scripts/macos/published_inventory.gd", "scripts/macos/published_admission_probe.gd"}


def validate_invocation(root: Path, plan: dict, args: argparse.Namespace) -> None:
    steps = [step for step in plan.get("steps", []) if isinstance(step, dict) and step.get("suite") == "macos-published"]
    if len(steps) != 1:
        raise ValueError("one exact published-client step is required")
    step = steps[0]
    command = step.get("command", "")
    if not isinstance(command, str) or any(character in command for character in ";&|<>$`\n\r"):
        raise ValueError("published-client command is invalid")
    tokens = shlex.split(command)
    flags = {"--godot", "--template", "--version", "--output", "--plan", "--report"}
    values: dict[str, str] = {}
    if len(tokens) != 14 or tokens[:2] != ["python3", "scripts/macos/published.py"]:
        raise ValueError("published-client entry point is invalid")
    for flag, value in zip(tokens[2::2], tokens[3::2]):
        if flag not in flags or flag in values or not value or value.startswith("--"):
            raise ValueError("published-client flags are invalid")
        values[flag] = value
    if set(values) != flags or values["--version"] != VERSION or args.version != VERSION:
        raise ValueError("published-client version is not the pinned release")
    tests = step.get("tests", [])
    if not isinstance(tests, list) or len(tests) != 3 or not all(isinstance(test, str) for test in tests) or set(tests) != SELECTED:
        raise ValueError("published-client selections are not exact")
    for flag, prefix in (("godot", "build/tools/godot/"), ("template", "build/tools/godot/"),
                         ("output", "dist/macos/"), ("plan", ".scratch/macos-client/"),
                         ("report", "build/validation/macos/")):
        planned = values["--" + flag]
        if not preflight.repository_path(root, planned) or not planned.startswith(prefix):
            raise ValueError("published-client path leaves its owned boundary")
        if Path(getattr(args, flag)).resolve() != (root / planned).resolve():
            raise ValueError("published-client invocation differs from its plan")
    if step.get("artifacts") != [values["--report"]]:
        raise ValueError("published-client report differs from its plan")


def _record(record: object) -> bool:
    return (isinstance(record, dict) and set(record) == {"name", "bytes", "sha256"}
            and isinstance(record["name"], str) and type(record["bytes"]) is int
            and 0 < record["bytes"] <= MAX_TOTAL_BYTES
            and isinstance(record["sha256"], str) and re.fullmatch(r"[0-9a-fA-F]{64}", record["sha256"]) is not None)


def validate_manifest(manifest: dict) -> None:
    required = {"package", "version", "built_at_utc", "source_commit", "source_tree_dirty", "godot_export_exit_code",
                "godot_version", "release_eligible", "export_error_lines", "archive", "archive_contents"}
    if not isinstance(manifest, dict) or set(manifest) != required:
        raise ValueError("published manifest fields are invalid")
    if (manifest["package"] != "standalone-windows-client" or manifest["version"] != VERSION
            or manifest["release_eligible"] is not True or type(manifest["godot_export_exit_code"]) is not int
            or manifest["godot_export_exit_code"] != 0 or manifest["export_error_lines"] != []
            or manifest["godot_version"] != "4.7.2.stable.official.ed1daf0bf"):
        raise ValueError("published manifest is not the qualified release")
    if (not isinstance(manifest["source_commit"], str) or not re.fullmatch(r"[0-9a-f]{40}", manifest["source_commit"])
            or type(manifest["source_tree_dirty"]) is not bool or not isinstance(manifest["built_at_utc"], str)
            or re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,7})?(?:Z|\+00:00)", manifest["built_at_utc"]) is None):
        raise ValueError("published manifest source metadata is invalid")
    if not _record(manifest["archive"]) or manifest["archive"] != ARCHIVE_RECORD:
        raise ValueError("published archive custody differs from the observed release")
    members = manifest["archive_contents"]
    if not isinstance(members, list) or len(members) != 2 or not all(_record(member) for member in members):
        raise ValueError("published archive member records are invalid")
    if sorted(members, key=lambda member: member["name"]) != sorted(MEMBER_RECORDS, key=lambda member: member["name"]):
        raise ValueError("published member custody differs from the observed release")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("published download redirects are forbidden")


def _fetch(url: str, maximum: int) -> bytes:
    if url not in {MANIFEST_URL, ARCHIVE_URL} or type(maximum) is not int or not 0 < maximum <= MAX_TOTAL_BYTES:
        raise ValueError("only fixed anonymous published downloads are permitted")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
    request = urllib.request.Request(url, headers={"Accept": "application/octet-stream", "User-Agent": "Project0MacClient/0.14.20"}, method="GET")
    deadline = time.monotonic() + 90
    pieces: list[bytes] = []
    size = 0
    with opener.open(request, timeout=15) as response:
        if response.status != 200 or response.geturl() != url:
            raise ValueError("published download status or location is invalid")
        while True:
            if time.monotonic() > deadline:
                raise TimeoutError("published download deadline exceeded")
            chunk = response.read(min(1024 * 1024, maximum + 1 - size))
            if not chunk:
                break
            size += len(chunk)
            if size > maximum:
                raise ValueError("published download exceeds its byte bound")
            pieces.append(chunk)
    return b"".join(pieces)


def download(url: str, destination: Path, expected_bytes: int, expected_sha256: str | None = None) -> None:
    if destination.exists() or destination.is_symlink():
        raise ValueError("published download destination is occupied")
    if expected_sha256 is not None and (not isinstance(expected_sha256, str) or re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha256) is None):
        raise ValueError("published download hash record is invalid")
    payload = _fetch(url, expected_bytes)
    if len(payload) != expected_bytes or (expected_sha256 is not None and hashlib.sha256(payload).hexdigest().lower() != expected_sha256.lower()):
        raise ValueError("published download custody differs from the expected record")
    with destination.open("xb") as handle:
        handle.write(payload)


def extract_archive(archive: Path, destination: Path, expected_archive: dict, expected_members: list[dict]) -> dict[str, Path]:
    if archive.is_symlink() or not archive.is_file() or destination.exists() or destination.is_symlink():
        raise ValueError("archive source or extraction destination is not clean")
    if not _record(expected_archive) or not isinstance(expected_members, list) or len(expected_members) != 2 or not all(_record(member) for member in expected_members):
        raise ValueError("archive custody records are invalid")
    records = {member["name"]: member for member in expected_members}
    if set(records) != {"Project0.exe", "Project0.pck"} or sum(member["bytes"] for member in records.values()) > MAX_TOTAL_BYTES:
        raise ValueError("archive must contain exactly the two bounded client members")
    if archive.stat().st_size != expected_archive["bytes"] or package.sha256(archive).lower() != expected_archive["sha256"].lower():
        raise ValueError("archive source custody is invalid")
    created = False
    try:
        with zipfile.ZipFile(archive) as source:
            members = source.infolist()
            if len(members) != 2 or {member.filename for member in members} != set(records):
                raise ValueError("archive paths or member count are invalid")
            for member in members:
                mode = member.external_attr >> 16
                if (member.is_dir() or member.flag_bits & 1 or stat.S_ISLNK(mode)
                        or (stat.S_IFMT(mode) not in {0, stat.S_IFREG})
                        or member.file_size != records[member.filename]["bytes"]
                        or member.file_size > max(1, member.compress_size) * MAX_COMPRESSION_RATIO):
                    raise ValueError("archive member type, length or compression bound is invalid")
            destination.mkdir(parents=True, exist_ok=False)
            created = True
            result: dict[str, Path] = {}
            for member in members:
                record = records[member.filename]
                target = destination / member.filename
                digest = hashlib.sha256()
                size = 0
                with source.open(member) as input_file, target.open("xb") as output_file:
                    while True:
                        chunk = input_file.read(min(1024 * 1024, record["bytes"] + 1 - size))
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > record["bytes"]:
                            raise ValueError("archive member exceeded its declared size")
                        digest.update(chunk)
                        output_file.write(chunk)
                if size != record["bytes"] or digest.hexdigest().lower() != record["sha256"].lower():
                    raise ValueError("archive member custody is invalid")
                result[member.filename] = target
            return result
    except Exception:
        if created:
            shutil.rmtree(destination)
        raise


def _settings(name: str, inert: Path | None = None) -> str:
    text = package.isolated_settings(name)
    if inert is not None:
        text += "run/main_scene=" + json.dumps(str(inert)) + "\n"
    return text + '[debug]\nfile_logging/enable_file_logging=false\nsettings/stdout/print_to_stdout=false\nsettings/stdout/print_to_stderr=false\n'


@contextmanager
def pack_boot_settings(pack: Path, settings: str):
    """Own the external override where main-pack startup resolves its project."""
    override = pack.parent / "override.cfg"
    with override.open("x") as output:
        output.write(settings)
    try:
        yield override
    finally:
        override.unlink(missing_ok=True)


def qualify_preboot(editor: Path, owned: Path, user_data_name: str, user_data: Path, evidence: Path, report: dict) -> None:
    """Prove the route's pre-autoload overrides with an inline harmless PCK."""
    fixture = owned / "preboot-fixture"
    source = fixture / "source"
    packer_project = fixture / "packer"
    runtime = fixture / "runtime"
    for directory in (source, packer_project, runtime):
        directory.mkdir(parents=True, exist_ok=False)
    receipt_path = evidence / "published-preboot.json"
    inert = runtime / "preboot_entry.tscn"
    inert.write_text('[gd_scene format=3]\n[node name="QualifiedPrebootEntry" type="Node"]\n')
    expected_data = user_data / "preboot-qualified"
    baseline = (package.isolated_settings(user_data_name + "/preboot-baseline")
                + 'run/main_scene="res://baseline.tscn"\n'
                + '[autoload]\nPrebootWitness="*res://preboot_witness.gd"\n'
                + '[debug]\nfile_logging/enable_file_logging=true\nsettings/stdout/print_to_stdout=true\nsettings/stdout/print_to_stderr=true\n')
    (source / "project.godot").write_text('config_version=5\n' + baseline)
    (source / "baseline.tscn").write_text('[gd_scene format=3]\n[node name="OpposedBaselineEntry" type="Node"]\n')
    witness = '''extends Node
const RECEIPT: String = %s
const EXPECTED_DATA: String = %s
const EXPECTED_INERT: String = %s
func _init() -> void:
	var result: Dictionary = {
		"schema_version": 1,
		"check": "macos-published-preboot-isolation",
		"earliest_callback": "init",
		"user_data_isolated": OS.get_user_data_dir().simplify_path() == EXPECTED_DATA.simplify_path(),
		"startup_scene_inert": ProjectSettings.get_setting("application/run/main_scene", "") == EXPECTED_INERT,
		"file_logging_disabled": ProjectSettings.get_setting("debug/file_logging/enable_file_logging", true) == false,
		"stdout_disabled": ProjectSettings.get_setting("debug/settings/stdout/print_to_stdout", true) == false,
		"stderr_disabled": ProjectSettings.get_setting("debug/settings/stdout/print_to_stderr", true) == false,
		"network_attempted": false,
		"user_storage_read": false,
	}
	var output: FileAccess = FileAccess.open(RECEIPT, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result))
		output.close()
''' % (json.dumps(str(receipt_path)), json.dumps(str(expected_data)), json.dumps(str(inert)))
    (source / "preboot_witness.gd").write_text(witness)
    (packer_project / "project.godot").write_text('config_version=5\n' + _settings(user_data_name + "/preboot-packer"))
    packer = packer_project / "make_fixture.gd"
    packer.write_text('''extends SceneTree
func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 2 or not arguments[0].is_absolute_path() or not arguments[1].is_absolute_path():
		quit(1)
		return
	var packer: PCKPacker = PCKPacker.new()
	if packer.pck_start(arguments[1]) != OK:
		quit(1)
		return
	for name: String in ["project.godot", "preboot_witness.gd", "baseline.tscn"]:
		if packer.add_file("res://" + name, arguments[0].path_join(name)) != OK:
			quit(1)
			return
	quit(0 if packer.flush() == OK else 1)
''')
    pack = fixture / "preboot.pck"
    pack_command = [str(editor), "--headless", "--path", str(packer_project), "--script", str(packer), "--", str(source), str(pack)]
    receipt = {"passed": False, "base_settings_opposed": True, "pack_command": pack_command}
    report["preboot_qualification"] = receipt
    receipt["pack_process"] = admission.run_suppressed(pack_command, packer_project, 30)
    if (receipt["pack_process"]["timeout"] or receipt["pack_process"]["exit_code"] != 0
            or not receipt["pack_process"]["process_group_removed"] or pack.is_symlink()
            or not pack.is_file() or not 0 < pack.stat().st_size <= 131072):
        raise RuntimeError("harmless preboot fixture could not be packed")
    receipt["fixture_pck_sha256"] = package.sha256(pack)
    settings = _settings(user_data_name + "/preboot-qualified", inert)
    (runtime / "project.godot").write_text('config_version=5\n' + settings)
    probe = runtime / "preboot_probe.gd"
    probe.write_text('''extends SceneTree
func _initialize() -> void:
	call_deferred("_finish")
func _finish() -> void:
	quit(0 if root.get_node_or_null("PrebootWitness") != null else 1)
''')
    command = [str(editor), "--headless", "--path", str(runtime), "--main-pack", str(pack), "--script", str(probe), "--",
               "--evidence=" + str(receipt_path), "--expected-user-data=" + str(expected_data), "--expected-inert-scene=" + str(inert)]
    receipt["command"] = command
    with pack_boot_settings(pack, settings):
        receipt["process"] = admission.run_suppressed(command, runtime, 30)
    receipt["override_location"] = "pack_directory"
    receipt["override_removed"] = not (pack.parent / "override.cfg").exists()
    if (receipt["process"]["timeout"] or receipt["process"]["exit_code"] != 0
            or not receipt["process"]["process_group_removed"] or not receipt_path.is_file()
            or receipt_path.is_symlink() or receipt_path.stat().st_size > 4096):
        raise RuntimeError("harmless preboot qualification evidence is missing")
    observed = json.loads(receipt_path.read_text())
    checks = {"user_data_isolated", "startup_scene_inert", "file_logging_disabled", "stdout_disabled", "stderr_disabled"}
    fields = checks | {"schema_version", "check", "earliest_callback", "network_attempted", "user_storage_read"}
    if (not isinstance(observed, dict) or set(observed) != fields or observed["schema_version"] != 1
            or observed["check"] != "macos-published-preboot-isolation" or observed["earliest_callback"] != "init"
            or observed["network_attempted"] is not False or observed["user_storage_read"] is not False
            or not all(observed[check] is True for check in checks)):
        raise ValueError("preboot isolation was not active before the harmless autoload")
    receipt.update({"passed": True, "earliest_autoload": observed, "evidence_sha256": package.sha256(receipt_path)})


def audit_pack(editor: Path, pack: Path, evidence: Path, owned: Path, user_data_name: str, report: dict | None = None) -> dict:
    inspector = owned / "inspector"
    inspector.mkdir(exist_ok=False)
    (inspector / "project.godot").write_text('config_version=5\n' + _settings(user_data_name + "/inventory"))
    for source in ("package_inventory.gd", "published_inventory.gd"):
        shutil.copyfile(ROOT / "scripts/macos" / source, inspector / source)
    result_path = evidence / "published-inventory.json"
    command = [str(editor), "--headless", "--path", str(inspector), "--script", str(inspector / "published_inventory.gd"), "--",
               str(pack), str(result_path), str(ROOT / "scripts/validation_ownership.json"), "4.7.2"]
    process = admission.run_suppressed(command, inspector, 55)
    receipt = {"command": command, "process": process, "accepted": False}
    if report is not None:
        report["pack_audit"] = receipt
    if (process["timeout"] or process["exit_code"] != 0 or not process["process_group_removed"]
            or not result_path.is_file() or result_path.is_symlink() or result_path.stat().st_size > 4 * 1024 * 1024):
        raise RuntimeError("published PCK data-only audit did not pass")
    result = json.loads(result_path.read_text())
    fields = {"schema_version", "check", "passed", "runtime_acceptance", "platform", "engine", "files", "failures", "client_files"}
    if (not isinstance(result, dict) or set(result) != fields or result["schema_version"] != 1
            or result["check"] != "macos-client-package-boundary" or result["platform"] != "macos"
            or result["engine"] != "4.7.2-stable (official)" or result["passed"] is not True
            or type(result["client_files"]) is not int or result["client_files"] <= 0
            or result["runtime_acceptance"] is not False or result["failures"] != []
            or not isinstance(result["files"], list) or not 0 < len(result["files"]) <= 20000
            or not all(isinstance(path, str) and len(path) <= 4096 for path in result["files"])):
        raise ValueError("published PCK boundary was rejected")
    receipt.update({"accepted": True, "evidence_sha256": package.sha256(result_path), "inventory": result})
    return receipt


def _bundle(template: Path, destination: Path) -> Path:
    if destination.exists() or destination.is_symlink():
        raise ValueError("candidate app destination is occupied")
    binary_name = "macos_template.app/Contents/MacOS/godot_macos_release.universal"
    with zipfile.ZipFile(template) as source:
        matches = [member for member in source.infolist() if member.filename == binary_name]
        if len(matches) != 1 or matches[0].file_size > 256 * 1024 * 1024 or stat.S_ISLNK(matches[0].external_attr >> 16):
            raise ValueError("qualified universal release template is absent or invalid")
        executable = destination / "Contents/MacOS/Project0"
        executable.parent.mkdir(parents=True, exist_ok=False)
        (destination / "Contents/Resources").mkdir()
        with source.open(matches[0]) as input_file, executable.open("xb") as output_file:
            shutil.copyfileobj(input_file, output_file, 1024 * 1024)
        executable.chmod(0o755)
        for resource_name in ("icon.icns", "PrivacyInfo.xcprivacy"):
            resource_path = "macos_template.app/Contents/Resources/" + resource_name
            resources = [member for member in source.infolist() if member.filename == resource_path]
            if not resources:
                continue
            if (len(resources) != 1 or resources[0].file_size > 2 * 1024 * 1024
                    or stat.S_ISLNK(resources[0].external_attr >> 16) or resources[0].flag_bits & 1):
                raise ValueError("Mac template resource is invalid")
            with source.open(resources[0]) as input_file, (destination / "Contents/Resources" / resource_name).open("xb") as output_file:
                shutil.copyfileobj(input_file, output_file, 1024 * 1024)
        info = {
            "CFBundleExecutable": "Project0", "CFBundleIdentifier": "vip.valentin.project0.macos.compat01420",
            "CFBundleName": "Project0", "CFBundleDisplayName": "Project0", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": VERSION, "CFBundleVersion": VERSION, "CFBundleSignature": "P0MC",
            "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True,
            "LSApplicationCategoryType": "public.app-category.games", "LSMinimumSystemVersion": "10.15",
            "LSMinimumSystemVersionByArchitecture": {"x86_64": "10.15", "arm64": "11.0"},
            "LSArchitecturePriority": ["arm64", "x86_64"],
        }
        if (destination / "Contents/Resources/icon.icns").is_file():
            info["CFBundleIconFile"] = "icon.icns"
        with (destination / "Contents/Info.plist").open("xb") as output_file:
            plistlib.dump(info, output_file)
        (destination / "Contents/PkgInfo").write_bytes(b"APPLP0MC")
    return executable


def validate_evidence(native: dict) -> None:
    """Reuse the qualified bounded admission schema after checking its new version."""
    if not isinstance(native, dict) or native.get("client_version") != VERSION:
        raise ValueError("published-pack native version evidence differs")
    compatibility = deepcopy(native)
    compatibility["client_version"] = admission.VERSION
    admission.validate_evidence(compatibility)


def verify_archive_pack(archive: Path, expected_bytes: int, expected_sha256: str) -> None:
    """Read the sole bundled PCK as bounded data and verify its exact bytes."""
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("Mac archive custody is invalid")
    with zipfile.ZipFile(archive) as source:
        matches = [member for member in source.infolist() if member.filename.endswith("/Contents/Resources/Project0.pck")]
        if (len(matches) != 1 or matches[0].filename != "Project0.app/Contents/Resources/Project0.pck"
                or matches[0].file_size != expected_bytes or matches[0].flag_bits & 1
                or stat.S_ISLNK(matches[0].external_attr >> 16)):
            raise ValueError("Mac archive does not contain the single exact PCK")
        with source.open(matches[0]) as input_file:
            payload = input_file.read(expected_bytes + 1)
        if len(payload) != expected_bytes or hashlib.sha256(payload).hexdigest().lower() != expected_sha256.lower():
            raise ValueError("Mac archive changed the published PCK bytes")


def assemble_pack(editor: Path, template: Path, pack: Path, output: Path, report: dict, evidence: Path) -> None:
    """Qualify an already validated PCK; own every temporary process and state."""
    if output.exists() or output.is_symlink():
        raise ValueError("published-client output is occupied")
    if any(path.is_symlink() or not path.is_file() for path in (editor, template, pack)):
        raise ValueError("published-client payload and tools require regular custody")
    required_sources = SELECTED | {"scripts/macos/package.py", "scripts/macos/admission.py", "scripts/macos/preflight.py",
                                  "scripts/macos/package_inventory.gd", "scripts/validation_ownership.json", NAKAMA_LICENSE}
    source_paths = [ROOT / name for name in sorted(required_sources | set(report.get("source_hashes", {})))]
    source_fingerprints = package.source_hashes(ROOT, source_paths)
    if report.get("source_hashes", source_fingerprints) != source_fingerprints:
        raise ValueError("published-client sources changed before assembly")
    actual_tools = {"editor": package.sha256(editor), "template": package.sha256(template)}
    if report.get("tool_hashes", actual_tools) != actual_tools:
        raise ValueError("published-client tools changed before assembly")
    report["tool_hashes"] = actual_tools
    pack_hash = package.sha256(pack)
    if report.get("published_pck_sha256", pack_hash) != pack_hash:
        raise ValueError("published-client PCK changed before assembly")
    report["published_pck_sha256"] = pack_hash
    with package.owned_state(report) as (owned, user_data, user_data_name):
        portable = owned / "editor/Godot.app"
        shutil.copytree(editor.parents[2], portable, symlinks=True)
        editor_copy = portable / "Contents/MacOS/Godot"
        (editor_copy.parent / "_sc_").touch(exist_ok=False)
        if package.sha256(editor_copy) != report["tool_hashes"]["editor"]:
            raise ValueError("portable editor custody differs")
        report["terminal_stage"] = "data_only_pack_audit"
        report["pack_audit"] = audit_pack(editor_copy, pack, evidence, owned, user_data_name, report)
        if package.sha256(pack) != report["published_pck_sha256"]:
            raise ValueError("published pack changed during audit")
        report["terminal_stage"] = "offline_preboot_qualification"
        qualify_preboot(editor_copy, owned, user_data_name, user_data, evidence, report)
        candidate = owned / "candidate/Project0.app"
        report["terminal_stage"] = "universal_mac_shell"
        executable = _bundle(template, candidate)
        version = package.run([str(executable), "--version"], candidate.parent, evidence / "template-version.log", 10)
        if version != "4.7.2.stable.official.ed1daf0bf":
            raise ValueError("Mac release template engine differs from published pack engine")
        architectures = package.run(["/usr/bin/lipo", "-archs", str(executable)], owned, evidence / "architectures.log", 10)
        if set(architectures.split()) != {"arm64", "x86_64"}:
            raise ValueError("Mac release template is not universal")
        shutil.copyfile(pack, candidate / "Contents/Resources/Project0.pck")
        if any(path.startswith("addons/com.heroiclabs.nakama/") for path in report["pack_audit"]["inventory"]["files"]):
            shutil.copyfile(ROOT / NAKAMA_LICENSE, candidate / "Contents/Resources/Nakama-LICENSE.txt")
            report["nakama_license_retained"] = package.sha256(candidate / "Contents/Resources/Nakama-LICENSE.txt") == source_fingerprints[NAKAMA_LICENSE]
            if not report["nakama_license_retained"]:
                raise ValueError("Nakama notice custody differs")
        if package.sha256(candidate / "Contents/Resources/Project0.pck") != report["published_pck_sha256"]:
            raise ValueError("Mac shell changed the published PCK")
        package.run(["/usr/bin/codesign", "--force", "--sign", "-", str(candidate)], owned, evidence / "codesign.log", 30)
        package.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(candidate)], owned, evidence / "codesign-verify.log", 30)
        runtime = owned / "runtime"
        runtime.mkdir()
        inert = runtime / "published_entry.tscn"
        inert.write_text('[gd_scene format=3]\n[node name="PublishedAdmissionEntry" type="Node"]\n')
        (runtime / "project.godot").write_text('config_version=5\n' + _settings(user_data_name + "/published-probe", inert))
        probe = runtime / "published_admission_probe.gd"
        shutil.copyfile(ROOT / "scripts/macos/published_admission_probe.gd", probe)
        probe_path = evidence / "published-admission.json"
        report["terminal_stage"] = "published_pack_admission"
        command = [str(editor_copy), "--headless", "--path", str(runtime), "--main-pack", str(pack), "--script", str(probe), "--",
                   "--evidence=" + str(probe_path), "--expected-user-data=" + str(user_data / "published-probe"),
                   "--expected-inert-scene=" + str(inert)]
        with pack_boot_settings(pack, _settings(user_data_name + "/published-probe", inert)):
            executed = admission.run_suppressed(command, runtime, 55)
        report["published_override_removed"] = not (pack.parent / "override.cfg").exists()
        report["admission_command"] = command
        report["admission_process"] = executed
        if not probe_path.is_file() or probe_path.is_symlink() or probe_path.stat().st_size > 32768:
            raise RuntimeError("published-pack admission evidence is missing or invalid")
        native = json.loads(probe_path.read_text())
        validate_evidence(native)
        report["native_admission"] = native
        report["native_evidence_sha256"] = package.sha256(probe_path)
        report["terminal_stage"] = native["terminal_stage"]
        report["source_custody_preserved"] = package.source_hashes(ROOT, source_paths) == source_fingerprints
        report["tool_custody_preserved"] = package.sha256(editor) == report["tool_hashes"]["editor"] and package.sha256(template) == report["tool_hashes"]["template"]
        report["pack_custody_preserved"] = package.sha256(pack) == report["published_pck_sha256"] and package.sha256(candidate / "Contents/Resources/Project0.pck") == report["published_pck_sha256"]
        if not all(report[key] for key in ("source_custody_preserved", "tool_custody_preserved", "pack_custody_preserved")):
            raise ValueError("published lifecycle custody changed")
        if not native["passed"] or executed["timeout"] or executed["exit_code"] != 0 or not executed["process_group_removed"]:
            return
        publication = owned / "publication"
        publication.mkdir(exist_ok=False)
        staged_app = publication / "Project0.app"
        shutil.copytree(candidate, staged_app, symlinks=True)
        archive_name = "Project0-client-macos-universal-" + VERSION + ".zip"
        staged_archive = publication / archive_name
        package.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staged_app), str(staged_archive)], publication, evidence / "archive.log", 30)
        verify_archive_pack(staged_archive, pack.stat().st_size, report["published_pck_sha256"])
        if package.sha256(staged_app / "Contents/Resources/Project0.pck") != report["published_pck_sha256"]:
            raise ValueError("published output changed the exact PCK")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.mkdir(exist_ok=False)
        try:
            shutil.copytree(staged_app, output / "Project0.app", symlinks=True)
            with staged_archive.open("rb") as input_file, (output / archive_name).open("xb") as output_file:
                shutil.copyfileobj(input_file, output_file, 1024 * 1024)
            if package.sha256(output / "Project0.app/Contents/Resources/Project0.pck") != report["published_pck_sha256"]:
                raise ValueError("final Mac output changed the published PCK")
            verify_archive_pack(output / archive_name, pack.stat().st_size, report["published_pck_sha256"])
            package.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(output / "Project0.app")],
                        output, evidence / "codesign-final.log", 30)
            report.update({"app": str(output / "Project0.app"), "archive": str(output / archive_name),
                           "archive_sha256": package.sha256(output / archive_name),
                           "executable_sha256": package.sha256(output / "Project0.app/Contents/MacOS/Project0"),
                           "info_plist_sha256": package.sha256(output / "Project0.app/Contents/Info.plist"),
                           "architectures": sorted(architectures.split()), "codesign": "ad-hoc verified; not notarized",
                           "exact_published_pck_preserved": True, "editor_pack_admission_passed": True})
        except Exception:
            shutil.rmtree(output)
            report["failed_output_removed"] = not output.exists()
            raise
    report["passed"] = bool(report.get("editor_pack_admission_passed") and report["temporary_state_removed"])


def diagnose(args: argparse.Namespace, report: dict, evidence: Path) -> None:
    plan_path = args.plan.resolve()
    source_paths = [ROOT / name for name in sorted(SELECTED | {"scripts/macos/package.py", "scripts/macos/admission.py",
                                                            "scripts/macos/preflight.py", "scripts/macos/package_inventory.gd",
                                                            "scripts/validation_ownership.json", NAKAMA_LICENSE})] + [plan_path]
    report["source_hashes"] = package.source_hashes(ROOT, source_paths)
    ownership = json.loads((ROOT / "scripts/validation_ownership.json").read_text())
    plan = json.loads(plan_path.read_text())
    if preflight.validate_plan(ROOT, ownership, plan, platform.system(), socket.gethostname()):
        raise ValueError("published-client ownership preflight failed")
    validate_invocation(ROOT, plan, args)
    report["preflight_passed"] = True
    output = args.output.resolve()
    if output.exists() or args.output.is_symlink():
        raise ValueError("published-client output is occupied")
    for tool in (args.godot, args.template):
        if tool.is_symlink() or not tool.is_file() or not tool.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError("published-client tools require regular repository-local custody")
    editor, template = args.godot.resolve(), args.template.resolve()
    report["tool_hashes"] = {"editor": package.sha256(editor), "template": package.sha256(template)}
    if report["tool_hashes"] != QUALIFIED_TOOL_HASHES:
        raise ValueError("published-client tools differ from the previously qualified official tools")
    report["qualified_tool_hashes"] = QUALIFIED_TOOL_HASHES.copy()
    report["source_commit"] = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    if re.fullmatch(r"[0-9a-f]{40}", report["source_commit"]) is None:
        raise ValueError("local source revision evidence is invalid")
    report["source_tree_dirty"] = bool(subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain"]))
    step = next(step for step in plan["steps"] if step["suite"] == "macos-published")
    report["invocation"] = shlex.split(step["command"])
    with package.owned_state(report) as (owned, user_data, user_data_name):
        report["terminal_stage"] = "published_download"
        manifest_bytes = _fetch(MANIFEST_URL, 131072)
        manifest = json.loads(manifest_bytes.decode("utf-8-sig"))
        validate_manifest(manifest)
        report["published_manifest_sha256"] = hashlib.sha256(manifest_bytes).hexdigest()
        report["published_manifest"] = manifest
        report["published_source_equality_proven"] = False
        archive = owned / ARCHIVE_NAME
        download(ARCHIVE_URL, archive, ARCHIVE_RECORD["bytes"], ARCHIVE_RECORD["sha256"])
        payload = extract_archive(archive, owned / "published", ARCHIVE_RECORD, MEMBER_RECORDS)
        pack = payload["Project0.pck"]
        report["published_archive_sha256"] = package.sha256(archive)
        report["published_pck_sha256"] = package.sha256(pack)
        assemble_pack(editor, template, pack, output, report, evidence)
        if package.source_hashes(ROOT, source_paths) != report["source_hashes"]:
            raise ValueError("published lifecycle source custody changed")
    report["passed"] = bool(report.get("editor_pack_admission_passed") and report["temporary_state_removed"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ("godot", "template", "output", "plan", "report"):
        parser.add_argument("--" + field, type=Path, required=True)
    parser.add_argument("--version", required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        print(json.dumps({"passed": False, "terminal_stage": "invalid_invocation"}))
        return 1
    report_path = args.report.resolve()
    if args.report.is_symlink() or report_path.exists() or not report_path.is_relative_to((ROOT / "build/validation/macos").resolve()):
        print(json.dumps({"passed": False, "terminal_stage": "invalid_evidence_path"}))
        return 1
    report = {"schema_version": 1, "issue": 1353, "check": "macos-exact-published-client", "passed": False,
              "version": VERSION, "platform": "macos", "host": socket.gethostname(), "terminal_stage": "setup",
              "observed_at_utc": datetime.now(timezone.utc).isoformat(), "temporary_state_removed": True,
              "raw_online_engine_output_captured": False, "server_commands_executed": False,
              "windows_executable_executed": False, "normal_standalone_world_entry_accepted": False,
              "intel_runtime_accepted": False, "full_regression": "awaiting Linux and Windows access"}
    try:
        evidence = report_path.with_suffix("")
        evidence.mkdir(parents=True, exist_ok=False)
        diagnose(args, report, evidence)
    except Exception as error:
        report["passed"] = False
        report["error_type"] = type(error).__name__
        if report["terminal_stage"] == "setup":
            report["terminal_stage"] = "setup_failed"
    finally:
        try:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            with report_path.open("x") as output_file:
                json.dump(report, output_file, indent=2)
                output_file.write("\n")
        except OSError:
            report["passed"] = False
        print(json.dumps({"passed": report["passed"], "terminal_stage": report["terminal_stage"],
                          "temporary_state_removed": report["temporary_state_removed"]}))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
