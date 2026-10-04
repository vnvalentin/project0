#!/usr/bin/env python3
"""Run one validation command while independently qualifying Linux process cleanup."""
import argparse
import ctypes
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import signal
import subprocess
import sys
import time


SHA = re.compile(r"[0-9a-f]{40}")
PR_SET_CHILD_SUBREAPER = 36
ERROR_MARKERS = ("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script")


class MonitorError(RuntimeError):
    pass


@dataclass(frozen=True)
class Process:
    pid: int
    parent_pid: int
    process_group: int
    session_id: int
    start_ticks: int
    state: str
    command: str
    cgroup: str

    @property
    def identity(self):
        return f"{self.pid}:{self.start_ticks}"

    @property
    def is_godot(self):
        return self.command.lower().startswith("godot")


def read_process(entry):
    try:
        stat_text = (entry / "stat").read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    try:
        closing = stat_text.rindex(")")
        command = stat_text[stat_text.index("(") + 1:closing]
        fields = stat_text[closing + 1:].split()
        cgroup = (entry / "cgroup").read_text(encoding="utf-8")
        return Process(
            pid=int(entry.name), parent_pid=int(fields[1]), process_group=int(fields[2]),
            session_id=int(fields[3]), start_ticks=int(fields[19]), state=fields[0],
            command=command, cgroup=cgroup,
        )
    except (OSError, ValueError, IndexError) as error:
        if not entry.exists():
            return None
        raise MonitorError("process_identity_unavailable") from error


def process_snapshot(proc_root=Path("/proc")):
    processes = {}
    for entry in proc_root.iterdir():
        if not entry.name.isdecimal():
            continue
        process = read_process(entry)
        if process is not None:
            processes[process.pid] = process
    return processes


def enable_child_subreaper():
    if not sys.platform.startswith("linux"):
        raise MonitorError("linux_required")
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
        raise MonitorError("child_subreaper_unavailable")
    if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
        raise MonitorError("pidfd_support_required")


def git_state(root):
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", "HEAD"], cwd=root, text=True, timeout=10
    ).strip()
    dirty = subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        cwd=root, text=True, timeout=10,
    )
    return revision, dirty


def gut_summary(path):
    if path.is_symlink() or not path.is_file():
        return False, "gut_summary_unavailable", None
    try:
        summary = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False, "gut_summary_invalid", None
    valid = (
        isinstance(summary, dict)
        and summary.get("runner") == "GUT"
        and summary.get("status") == "passed"
        and type(summary.get("exit_code")) is int and summary["exit_code"] == 0
        and type(summary.get("scripts_expected")) is int and summary["scripts_expected"] > 0
        and type(summary.get("scripts_ran")) is int
        and summary["scripts_ran"] == summary["scripts_expected"]
        and summary.get("timed_out") is False
        and summary.get("gut_script_error_observed") is False
        and summary.get("gut_log_scan_failed") is False
    )
    return valid, "" if valid else "gut_inventory_or_summary_failed", summary


def open_pidfd(process):
    try:
        descriptor = os.pidfd_open(process.pid, 0)
        current = read_process(Path("/proc") / str(process.pid))
        if current is None or current.start_ticks != process.start_ticks:
            os.close(descriptor)
            raise MonitorError("process_identity_changed")
        return descriptor
    except OSError as error:
        raise MonitorError("process_handle_unavailable") from error


def is_alive(descriptor):
    import select

    poller = select.poll()
    poller.register(descriptor, select.POLLIN | select.POLLHUP | select.POLLERR)
    return not poller.poll(0)


def owned_processes(snapshot, monitor_pid, root_process, known):
    candidates = dict(snapshot)
    changed = []
    while True:
        found = False
        known_pids = {pid for pid, entry in known.items() if is_alive(entry["pidfd"])}
        for pid, process in candidates.items():
            existing = known.get(pid)
            if existing is not None:
                if existing["process"].start_ticks != process.start_ticks:
                    changed.append(pid)
                continue
            is_root = pid == root_process.pid and process.parent_pid == monitor_pid
            is_descendant = process.parent_pid in known_pids
            is_adopted = process.parent_pid == monitor_pid and pid != root_process.pid
            if not (is_root or is_descendant or is_adopted):
                continue
            known[pid] = {"process": process, "pidfd": open_pidfd(process)}
            found = True
        if not found:
            break
    return known, changed


def unknown_engines(snapshot, known, allowed_cgroups):
    owned = {entry["process"].identity for entry in known.values()}
    return [process for process in snapshot.values()
            if process.state != "Z" and process.is_godot and process.identity not in owned
            and process.cgroup.removesuffix("\n") not in allowed_cgroups]


def process_evidence(process, snapshot):
    parent = snapshot.get(process.parent_pid)
    cgroup = process.cgroup.removesuffix("\n")
    return {
        "identity": process.identity,
        "parent_identity": parent.identity if parent is not None else None,
        "parent_pid": process.parent_pid,
        "parent_command": parent.command if parent is not None else None,
        "process_group": process.process_group,
        "session_id": process.session_id,
        "command": process.command,
        "cgroup_sha256": hashlib.sha256(cgroup.encode()).hexdigest(),
    }


def owned_process_evidence(known):
    return sorted((
        {"identity": entry["process"].identity,
         "parent_pid": entry["process"].parent_pid,
         "process_group": entry["process"].process_group,
         "session_id": entry["process"].session_id,
         "command": entry["process"].command}
        for entry in known.values()
    ), key=lambda item: item["identity"])


def reap_owned(known, leader_pid):
    for pid in known:
        if pid == leader_pid:
            continue
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass


def terminate_owned(known):
    if not known:
        return True
    forced = False
    for sig, grace in ((signal.SIGTERM, 1.0), (signal.SIGKILL, 2.0)):
        active = [entry for entry in known.values() if is_alive(entry["pidfd"])]
        if not active:
            break
        forced = True
        for entry in reversed(active):
            try:
                signal.pidfd_send_signal(entry["pidfd"], sig)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline and any(is_alive(entry["pidfd"]) for entry in active):
            time.sleep(0.02)
    return forced


def safe_report_paths(report_path):
    if not report_path.parent.is_dir():
        raise MonitorError("report_directory_unavailable")
    for path in (report_path.parent, *report_path.parent.parents):
        if path.is_symlink():
            raise MonitorError("report_parent_symlink")
    log_path = report_path.with_suffix(report_path.suffix + ".log")
    if report_path.exists() or report_path.is_symlink() or log_path.exists() or log_path.is_symlink():
        raise MonitorError("evidence_path_exists")
    return log_path


def write_report(path, report, owner=None):
    temporary = path.with_name(path.name + f".{os.getpid()}.pending")
    with temporary.open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(report, indent=2, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.link(temporary, path)
    temporary.unlink()
    if owner is not None:
        os.chown(path, owner[0], owner[1])


def caller_identity():
    if os.geteuid() != 0:
        raise MonitorError("root_monitor_required")
    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        account = pwd.getpwuid(uid)
    except (KeyError, ValueError) as error:
        raise MonitorError("sudo_caller_identity_unavailable") from error
    return uid, gid, account


def drop_to_caller(identity):
    uid, gid, account = identity
    groups = os.getgrouplist(account.pw_name, gid)
    os.setgroups(groups)
    os.setgid(gid)
    os.setuid(uid)


def command_environment(preserve_names, identity):
    environment = os.environ.copy()
    if identity is not None:
        uid, gid, account = identity
        environment.update({"HOME": account.pw_dir, "USER": account.pw_name, "LOGNAME": account.pw_name})
    for key in list(environment):
        if key.startswith("SUDO_"):
            environment.pop(key)
    environment.update({key: os.environ[key] for key in preserve_names if key in os.environ})
    return environment


def run(args):
    if not sys.platform.startswith("linux"):
        raise MonitorError("linux_required")
    if not args.command:
        raise MonitorError("command_required")
    if not SHA.fullmatch(args.expected_revision):
        raise MonitorError("expected_revision_invalid")
    root = args.root.resolve(strict=True)
    report_path = args.report if args.report.is_absolute() else root / args.report
    report_path = report_path.absolute()
    log_path = safe_report_paths(report_path)
    identity = caller_identity() if args.run_as_sudo_caller else None
    if args.require_root and os.geteuid() != 0:
        raise MonitorError("root_required_for_engine_census")
    enable_child_subreaper()
    source_before, dirty_before = git_state(root)
    if source_before != args.expected_revision or dirty_before:
        raise MonitorError("source_identity_or_cleanliness_failed")
    snapshot = process_snapshot()
    baseline_engines = unknown_engines(snapshot, {}, set(args.allowed_cgroup))
    unknown_observations = {
        process.identity: process_evidence(process, snapshot)
        for process in baseline_engines
    }
    report = {
        "schema_version": 1, "runner": "validation-process-monitor",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "source_revision": source_before, "root": str(root),
        "command_sha256": hashlib.sha256("\0".join(args.command).encode()).hexdigest(),
        "monitor": {"pid": os.getpid(), "uid": os.geteuid(), "child_subreaper": True,
                    "poll_interval_seconds": args.poll_interval},
        "allowed_cgroup_sha256": [hashlib.sha256(value.encode()).hexdigest() for value in args.allowed_cgroup],
        "baseline_unowned_godot": [process.identity for process in baseline_engines],
        "unknown_godot_observations": list(unknown_observations.values()),
        "owned_processes": [], "unknown_godot": [], "errors": [],
        "timed_out": False, "forced_recovery": False,
        "command_exit_code": None, "source_unchanged": False,
        "command_identity_captured": False,
    }
    known = {}
    command_process = None
    command_process_stopped = False
    if args.reject_unowned_godot and baseline_engines:
        report["errors"].append("unowned_godot_present_before_run")
        report["command_started"] = False
        command_process_stopped = True
    else:
        report["command_started"] = True
        environment = command_environment(args.preserve_env, identity)
        child_setup = (lambda: drop_to_caller(identity)) if identity is not None else None
        started = time.monotonic()
        deadline = started + args.timeout_seconds
        process = None
        with log_path.open("x", encoding="utf-8") as output:
            try:
                process = subprocess.Popen(
                    args.command, cwd=root, env=environment, stdin=subprocess.DEVNULL,
                    stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
                    preexec_fn=child_setup,
                )
                command_process = process
                root_identity = read_process(Path("/proc") / str(process.pid))
                if root_identity is None:
                    raise MonitorError("command_identity_unavailable")
                report["command_identity"] = root_identity.identity
                known[process.pid] = {"process": root_identity, "pidfd": open_pidfd(root_identity)}
                report["command_identity_captured"] = True
                while True:
                    snapshot = process_snapshot()
                    known, changed = owned_processes(snapshot, os.getpid(), process, known)
                    if changed:
                        report["errors"].append("owned_pid_identity_changed")
                    engines = unknown_engines(snapshot, known, set(args.allowed_cgroup)) if args.reject_unowned_godot else []
                    report["unknown_godot"] = sorted({entry.identity for entry in engines})
                    for engine in engines:
                        unknown_observations.setdefault(engine.identity, process_evidence(engine, snapshot))
                    if engines:
                        report["errors"].append("unowned_godot_during_run")
                    if time.monotonic() >= deadline:
                        report["timed_out"] = True
                        report["errors"].append("command_timeout")
                    if report["errors"] or process.poll() is not None:
                        break
                    time.sleep(args.poll_interval)
                report["command_exit_code"] = process.wait(timeout=5)
                command_process_stopped = process.poll() is not None
                snapshot = process_snapshot()
                known, changed = owned_processes(snapshot, os.getpid(), process, known)
                if changed:
                    report["errors"].append("owned_pid_identity_changed")
                reap_owned(known, process.pid)
                live = [entry for entry in known.values() if is_alive(entry["pidfd"])]
                if live:
                    report["errors"].append("owned_process_survived_command")
                if report["errors"] or live:
                    report["forced_recovery"] = terminate_owned(known)
                final_snapshot = process_snapshot()
                remaining = [entry for entry in known.values()
                             if is_alive(entry["pidfd"])]
                final_unknown = unknown_engines(final_snapshot, known, set(args.allowed_cgroup)) if args.reject_unowned_godot else []
                report["unknown_godot"] = sorted({entry.identity for entry in final_unknown})
                for engine in final_unknown:
                    unknown_observations.setdefault(engine.identity, process_evidence(engine, final_snapshot))
                if remaining:
                    report["errors"].append("owned_process_cleanup_failed")
                if final_unknown:
                    report["errors"].append("unowned_godot_after_run")
            except (OSError, subprocess.SubprocessError, MonitorError, KeyboardInterrupt) as error:
                report["errors"].append(str(error) if isinstance(error, MonitorError) else type(error).__name__)
                if process is not None:
                    report["forced_recovery"] = terminate_owned(known) or report["forced_recovery"]
                    if process.poll() is None:
                        try:
                            if not report["command_identity_captured"]:
                                report["forced_recovery"] = True
                                process.terminate()
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            report["errors"].append("owned_process_wait_failed")
                            try:
                                process.kill()
                                process.wait(timeout=5)
                            except (OSError, subprocess.SubprocessError):
                                report["errors"].append("owned_process_kill_failed")
                    if process.poll() is not None:
                        command_process_stopped = True
                        reap_owned(known, process.pid)
        report["owned_processes"] = owned_process_evidence(known)
        report["unknown_godot_observations"] = list(unknown_observations.values())
        summary = None
        if args.gut_summary:
            summary_path = args.gut_summary if args.gut_summary.is_absolute() else root / args.gut_summary
            valid, reason, summary = gut_summary(summary_path)
            report["gut_summary"] = summary
            if not valid:
                report["errors"].append(reason)
        source_after, dirty_after = git_state(root)
        report["source_unchanged"] = source_after == source_before and not dirty_after
        if not report["source_unchanged"]:
            report["errors"].append("source_changed_during_validation")
        output = log_path.read_text(encoding="utf-8", errors="replace")
        if any(marker in output for marker in ERROR_MARKERS):
            report["errors"].append("engine_script_error_marker")
    report["cleanup"] = {
        "owned_processes_stopped": (
            command_process_stopped
            and (not report["command_started"] or report["command_identity_captured"])
            and not any(is_alive(entry["pidfd"]) for entry in known.values())
        ),
        "unknown_godot_absent": not report["unknown_godot"],
        "forced_recovery": report["forced_recovery"],
    }
    if args.gut_summary:
        summary_path = args.gut_summary if args.gut_summary.is_absolute() else root / args.gut_summary
        if summary_path.is_file() and not summary_path.is_symlink():
            report["artifacts"] = {str(summary_path): hashlib.sha256(summary_path.read_bytes()).hexdigest()}
        else:
            report["artifacts"] = {}
    else:
        report["artifacts"] = {}
    if log_path.is_file() and not log_path.is_symlink():
        report["artifacts"][str(log_path)] = hashlib.sha256(log_path.read_bytes()).hexdigest()
    report["completed_utc"] = datetime.now(timezone.utc).isoformat()
    report["status"] = "passed" if report["command_started"] and not report["errors"] and not report["forced_recovery"] and report["command_exit_code"] == 0 else "failed"
    if not report["cleanup"]["owned_processes_stopped"] or not report["cleanup"]["unknown_godot_absent"]:
        report["status"] = "failed"
    owner = (identity[0], identity[1]) if identity is not None else None
    try:
        write_report(report_path, report, owner)
        if owner is not None:
            os.chown(log_path, owner[0], owner[1])
    finally:
        for entry in known.values():
            os.close(entry["pidfd"])
    print(json.dumps({"report": str(report_path), "status": report["status"],
                      "command_exit_code": report["command_exit_code"],
                      "forced_recovery": report["forced_recovery"], "errors": report["errors"]}, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expected-revision", required=True)
    parser.add_argument("--timeout-seconds", type=float, required=True)
    parser.add_argument("--poll-interval", type=float, default=0.025)
    parser.add_argument("--allowed-cgroup", action="append", default=[])
    parser.add_argument("--reject-unowned-godot", action="store_true")
    parser.add_argument("--require-root", action="store_true")
    parser.add_argument("--run-as-sudo-caller", action="store_true")
    parser.add_argument("--preserve-env", action="append", default=[])
    parser.add_argument("--gut-summary", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.timeout_seconds <= 0 or args.timeout_seconds > 7200:
        parser.error("timeout-seconds must be in (0, 7200]")
    if args.poll_interval <= 0 or args.poll_interval > 1:
        parser.error("poll-interval must be in (0, 1]")
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    try:
        return run(args)
    except (MonitorError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "failed", "error": str(error)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())