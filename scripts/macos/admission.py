"""Bounded, unauthenticated Mac client admission diagnosis for issue #1353."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time

import package
import preflight


ROOT = Path(__file__).resolve().parents[2]
HOST = "192.69.180.236"
PORT = 9999
VERSION = "0.12.0"
PROBE = "scripts/macos/admission_probe.gd"
COORDINATOR = "scripts/macos/admission.py"
STATES = {"connecting", "connected", "disconnected", "failed", "refused", "unknown"}
TERMINALS = {"setup", "setup_failed", "game_connect_timeout", "server_admission_timeout",
             "version_rejected", "admitted", "runtime_deadline"}
REJECTIONS = {"", "CLIENT_OUTDATED", "MALFORMED", "SERVER_MISCONFIGURED", "UNSUPPORTED", "unknown_rejection"}
FAILURES = {"isolation_mismatch", "inert_scene_missing", "engine_mismatch", "client_version_mismatch",
            "logging_not_disabled", "network_client_missing", "waiter_contract_mismatch",
            "game_connect_timeout", "server_admission_timeout", "version_rejected", "runtime_deadline"}
PROBE_FIELDS = {"schema_version", "probe", "passed", "target", "client_version", "user_data_isolated",
                "startup_scene_inert", "connected", "admitted", "terminal_stage", "timeout_ms",
                "elapsed_msec", "phase_durations_ms", "connection_events", "events_truncated",
                "version_rejection", "assertion_sent", "authentication_attempted", "session_attempted",
                "world_entry_attempted", "cleanup_disconnect", "failures"}


def validate_invocation(root: Path, plan: dict, args: argparse.Namespace) -> None:
    """Require this invocation to equal its one explicitly reviewed admission step."""
    steps = [step for step in plan.get("steps", []) if isinstance(step, dict) and step.get("suite") == "macos-admission"]
    if len(steps) != 1:
        raise ValueError("exactly one admission step is required")
    step = steps[0]
    command = step.get("command", "")
    if not isinstance(command, str) or any(character in command for character in ";&|<>$`\n\r"):
        raise ValueError("reviewed admission command is malformed")
    tokens = shlex.split(command)
    flags = {"--godot", "--version", "--plan", "--report"}
    if len(tokens) != 10 or tokens[:2] != ["python3", COORDINATOR]:
        raise ValueError("reviewed admission entry point is invalid")
    values: dict[str, str] = {}
    for flag, value in zip(tokens[2::2], tokens[3::2]):
        if flag not in flags or flag in values or not value or value.startswith("--"):
            raise ValueError("reviewed admission flags are invalid")
        values[flag] = value
    if set(values) != flags or values["--version"] != VERSION or args.version != VERSION:
        raise ValueError("reviewed admission version is invalid")
    for flag, prefix in (("godot", "build/tools/godot/"), ("plan", ".scratch/macos-client/"),
                         ("report", "build/validation/macos/")):
        planned = values["--" + flag]
        if not preflight.repository_path(root, planned) or not planned.startswith(prefix):
            raise ValueError("reviewed admission path is outside its owned boundary")
        if Path(getattr(args, flag)).resolve() != (root / planned).resolve():
            raise ValueError("actual admission invocation differs from its plan")
    tests = step.get("tests", [])
    if not isinstance(tests, list) or len(tests) != 2 or not all(isinstance(test, str) for test in tests) or set(tests) != {PROBE, COORDINATOR}:
        raise ValueError("admission plan must select its exact coordinator and native probe")
    if values["--report"] not in step.get("artifacts", []):
        raise ValueError("admission report does not match its planned artifact")


def _integer(value: object, maximum: int) -> bool:
    return type(value) is int and 0 <= value <= maximum


def validate_evidence(report: dict) -> None:
    """Validate already allowlisted native evidence; never redact a raw response."""
    if not isinstance(report, dict) or set(report) != PROBE_FIELDS:
        raise ValueError("native admission evidence fields are invalid")
    if type(report["schema_version"]) is not int or report["schema_version"] != 1 or report["probe"] != "macos-server-admission":
        raise ValueError("native admission evidence identity is invalid")
    if report["target"] != {"host": HOST, "port": PORT} or report["client_version"] != VERSION:
        raise ValueError("native admission evidence target or version is invalid")
    for field in ("passed", "user_data_isolated", "startup_scene_inert", "connected", "admitted",
                  "events_truncated", "cleanup_disconnect"):
        if type(report[field]) is not bool:
            raise ValueError("native admission verdict type is invalid")
    for field in ("assertion_sent", "authentication_attempted", "session_attempted", "world_entry_attempted"):
        if report[field] is not False:
            raise ValueError("native admission crossed the unauthenticated boundary")
    if not isinstance(report["terminal_stage"], str) or report["terminal_stage"] not in TERMINALS or report["timeout_ms"] != 20000 or not _integer(report["elapsed_msec"], 60000):
        raise ValueError("native admission stage or deadline is invalid")
    durations = report["phase_durations_ms"]
    if not isinstance(durations, dict) or set(durations) != {"connect", "admission"} or any(not _integer(value, 25000) for value in durations.values()):
        raise ValueError("native admission phase duration is invalid")
    events = report["connection_events"]
    if not isinstance(events, list) or len(events) > 64:
        raise ValueError("native admission event bound is invalid")
    for event in events:
        if not isinstance(event, dict) or set(event) != {"state", "elapsed_msec"} or not isinstance(event["state"], str) or event["state"] not in STATES or not _integer(event["elapsed_msec"], 60000):
            raise ValueError("native admission event is not allowlisted")
    rejection = report["version_rejection"]
    if not isinstance(rejection, dict) or set(rejection) != {"received", "outcome", "required_version"} or type(rejection["received"]) is not bool or not isinstance(rejection["outcome"], str) or rejection["outcome"] not in REJECTIONS:
        raise ValueError("native admission rejection is not allowlisted")
    version = rejection["required_version"]
    if not isinstance(version, str) or len(version) > 32 or (version and not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version)):
        raise ValueError("native admission required version is not allowlisted")
    if not rejection["received"] and (rejection["outcome"] or version):
        raise ValueError("native admission rejection claims an unreceived reply")
    failures = report["failures"]
    if not isinstance(failures, list) or len(failures) > 12 or any(not isinstance(failure, str) or failure not in FAILURES for failure in failures):
        raise ValueError("native admission failures are not allowlisted")
    accepted = (report["admitted"] and report["connected"] and report["user_data_isolated"]
                and report["startup_scene_inert"] and report["cleanup_disconnect"]
                and report["terminal_stage"] == "admitted" and not failures and not rejection["received"])
    if report["passed"] != bool(accepted):
        raise ValueError("native admission verdict is inconsistent")


def run_suppressed(command: list[str], cwd: Path, timeout: int = 55) -> dict:
    """Never capture engine output: server-driven RPC/status fields are untrusted."""
    if type(timeout) is not int or not 0 < timeout <= 90:
        raise ValueError("native operation timeout must remain bounded")
    environment = {key: value for key, value in os.environ.items()
                   if key in {"HOME", "PATH", "TMPDIR", "LANG", "LC_ALL"}}
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, env=environment, start_new_session=True)
    timed_out = False
    removed = False
    try:
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            removed = True
        process.wait()
        deadline = time.monotonic() + 2
        while not removed and time.monotonic() < deadline:
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                removed = True
            if not removed:
                time.sleep(0.02)
    return {"exit_code": process.returncode, "timeout": timed_out, "process_group_removed": removed}


def _inputs(root: Path, plan: Path) -> list[Path]:
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "client", "shared", "project.godot",
                                       "server/starting_town_hub_fixture.gd", "addons/com.heroiclabs.nakama",
                                       "docs/third-party/nakama-godot-v3.4.0/LICENSE"]).decode().split("\0")
    names = {name for name in tracked if name and name != "shared/local_llm_client.gd"
             and (Path(name).suffix in {".gd", ".tscn", ".tres", ".json", ".uid", ".godot"}
                  or name == "docs/third-party/nakama-godot-v3.4.0/LICENSE")}
    names.update({PROBE, COORDINATOR, "scripts/macos/offline_probe.gd", "scripts/macos/package.py",
                  "scripts/macos/preflight.py", "scripts/validation_ownership.json"})
    return sorted([root / name for name in names] + [plan])


def diagnose(args: argparse.Namespace, report: dict, evidence: Path) -> None:
    """Own preflight, isolated staging, native execution, custody and cleanup."""
    plan_path = args.plan.resolve()
    sources = _inputs(ROOT, plan_path)
    report["source_hashes"] = package.source_hashes(ROOT, sources)
    manifest_path = ROOT / "scripts/validation_ownership.json"
    manifest = json.loads(manifest_path.read_text())
    plan = json.loads(plan_path.read_text())
    errors = preflight.validate_plan(ROOT, manifest, plan, platform.system(), socket.gethostname())
    if errors:
        raise ValueError("admission plan preflight failed")
    validate_invocation(ROOT, plan, args)
    report["preflight_passed"] = True
    editor = args.godot.resolve()
    if editor.is_symlink() or not editor.is_file() or not editor.is_relative_to((ROOT / "build/tools/godot").resolve()):
        raise ValueError("qualified local Mac editor is required")
    report["editor_sha256"] = package.sha256(editor)
    report["plan_sha256"] = package.sha256(plan_path)
    report["ownership_sha256"] = package.sha256(manifest_path)
    report["source_commit"] = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    report["source_tree_dirty"] = bool(subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain"]))
    admission_step = next(step for step in plan["steps"] if step["suite"] == "macos-admission")
    report["invocation"] = shlex.split(admission_step["command"])
    report["commands"] = []
    with package.owned_state(report) as (owned, user_data, user_data_name):
        portable = owned / "editor/Godot.app"
        shutil.copytree(editor.parents[2], portable, symlinks=True)
        portable_editor = portable / "Contents/MacOS/Godot"
        (portable_editor.parent / "_sc_").touch(exist_ok=False)
        if package.sha256(portable_editor) != report["editor_sha256"]:
            raise ValueError("portable editor differs from qualified tool")
        stage = owned / "client"
        package.stage_project(ROOT, stage, VERSION)
        shutil.copyfile(ROOT / PROBE, stage / PROBE)
        inert_path = "res://scripts/macos/admission_entry.tscn"
        (stage / "scripts/macos/admission_entry.tscn").write_text('[gd_scene format=3]\n[node name="MacAdmissionEntry" type="Node"]\n')
        settings = (package.isolated_settings(user_data_name + "/admission")
                    + 'run/main_scene="' + inert_path + '"\n'
                    + '[debug]\nfile_logging/enable_file_logging=false\n'
                    + 'settings/stdout/print_to_stdout=false\nsettings/stdout/print_to_stderr=false\n')
        (stage / "override.cfg").write_text(settings)
        staged_paths = sorted(path for path in stage.rglob("*") if path.is_file())
        staged_hashes = package.source_hashes(stage, staged_paths)
        report["staged_source_hashes"] = staged_hashes
        report["terminal_stage"] = "cold_import"
        import_command = [str(portable_editor), "--headless", "--path", str(stage), "--import"]
        imported = run_suppressed(import_command, stage, 90)
        report["commands"].append({"phase": "cold_import", "argv": import_command, **imported})
        if imported["timeout"] or imported["exit_code"] != 0 or not imported["process_group_removed"]:
            raise RuntimeError("native import failed")
        report["terminal_stage"] = "admission_probe"
        probe_path = evidence / "admission-probe.json"
        command = [str(portable_editor), "--headless", "--path", str(stage), "--script", "res://" + PROBE,
                   "--", "--evidence=" + str(probe_path), "--expected-user-data=" + str(user_data / "admission")]
        executed = run_suppressed(command, stage, 55)
        report["commands"].append({"phase": "admission_probe", "argv": command, **executed})
        if not probe_path.is_file() or probe_path.is_symlink() or probe_path.stat().st_size > 32768:
            raise RuntimeError("native admission evidence is missing or invalid")
        probe = json.loads(probe_path.read_text())
        validate_evidence(probe)
        report["native_evidence"] = probe
        report["native_evidence_sha256"] = package.sha256(probe_path)
        report["terminal_stage"] = probe["terminal_stage"]
        report["source_custody_preserved"] = package.source_hashes(ROOT, sources) == report["source_hashes"]
        report["staged_custody_preserved"] = package.source_hashes(stage, staged_paths) == staged_hashes
        report["editor_custody_preserved"] = package.sha256(editor) == report["editor_sha256"] and package.sha256(portable_editor) == report["editor_sha256"]
        if not all(report[key] for key in ("source_custody_preserved", "staged_custody_preserved", "editor_custody_preserved")):
            raise RuntimeError("admission source custody changed")
        report["passed"] = (probe["passed"] and not executed["timeout"] and executed["exit_code"] == 0
                            and executed["process_group_removed"])
    report["passed"] = bool(report["passed"] and report["temporary_state_removed"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        print(json.dumps({"passed": False, "terminal_stage": "invalid_invocation"}))
        return 1
    report_path = args.report.resolve()
    if not report_path.is_relative_to((ROOT / "build/validation/macos").resolve()) or report_path.exists():
        print(json.dumps({"passed": False, "terminal_stage": "invalid_evidence_path"}))
        return 1
    evidence = report_path.with_suffix("")
    report = {"schema_version": 1, "issue": 1353, "check": "macos-client-server-admission", "passed": False,
              "target": {"host": HOST, "port": PORT}, "client_version": VERSION,
              "platform": "macos", "host": socket.gethostname(), "terminal_stage": "setup",
              "observed_at_utc": datetime.now(timezone.utc).isoformat(), "temporary_state_removed": True,
              "evidence_kind": "real-source-client-admission-only", "packaged_runtime_acceptance": False,
              "authenticated_world_entry_acceptance": False, "paired_gameplay_acceptance": False,
              "raw_engine_output_captured": False, "server_commands_executed": False}
    try:
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
            with report_path.open("x") as handle:
                json.dump(report, handle, indent=2)
                handle.write("\n")
        except OSError:
            report["passed"] = False
        print(json.dumps({"passed": report["passed"], "terminal_stage": report["terminal_stage"],
                          "temporary_state_removed": report["temporary_state_removed"]}))
    return int(not report["passed"])


if __name__ == "__main__":
    sys.exit(main())
