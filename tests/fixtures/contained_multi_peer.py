import json
import os
import signal
import sys
import threading
import time
from pathlib import Path


MARKER = "PROJECT0_TEST_PROCESS_GROUP_NONCE"


def process_info(pid: int) -> dict:
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rpartition(") ")[2].split()
        return {"pid": pid, "state": fields[0], "group": int(fields[2]),
                "session": int(fields[3]), "started": int(fields[19])}
    except (OSError, ValueError, IndexError):
        return {}


def group_members(pid: int, started: int, nonce: str) -> list[dict]:
    members = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal():
            continue
        process = process_info(int(entry.name))
        if not process or process["group"] != pid or process["state"] == "Z":
            continue
        marker = f"{MARKER}={nonce}".encode()
        try:
            environment = (entry / "environ").read_bytes().split(b"\0")
        except FileNotFoundError:
            continue
        if process["session"] != pid or process["started"] < started or marker not in environment:
            raise ValueError("Process group ownership mismatch")
        members.append(process)
    return members


def owned_groups(started: int, nonce: str) -> dict[int, int]:
    groups = {}
    marker = f"{MARKER}={nonce}".encode()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal():
            continue
        process = process_info(int(entry.name))
        if not process or process["state"] == "Z":
            continue
        try:
            environment = (entry / "environ").read_bytes().split(b"\0")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if marker not in environment:
            continue
        if process["group"] <= 0 or process["session"] != process["group"] or process["started"] < started:
            raise ValueError("Owned session custody mismatch")
        groups[process["group"]] = started
    return groups


def stop(report_path: Path, nonce: str, pid: int) -> dict:
    lease_path = Path(str(report_path) + ".group.json")
    lease = json.loads(lease_path.read_text())
    if pid <= 0 or lease["pid"] != pid or lease["nonce"] != nonce:
        raise ValueError("Invalid process group lease")
    leader = process_info(pid)
    if leader and (leader["started"] != lease["started"] or leader["group"] != pid or leader["session"] != pid):
        raise ValueError("Process group leader identity changed")
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    if report and report.get("process_id") != pid:
        raise ValueError("Fixture report identity mismatch")
    deadline = time.monotonic() + 5
    terminated = set()
    groups = owned_groups(lease["started"], nonce)
    while groups and time.monotonic() < deadline:
        members = {group: group_members(group, started, nonce) for group, started in groups.items()}
        for group, processes in members.items():
            terminated.update(process["pid"] for process in processes)
            try:
                os.killpg(group, signal.SIGKILL)
            except ProcessLookupError:
                pass
        threading.Event().wait(0.01)
        groups = owned_groups(lease["started"], nonce)
    if owned_groups(lease["started"], nonce):
        raise RuntimeError("Owned process group did not stop")
    removed = 0
    if report_path.exists():
        paths = [Path(value) for value in report.get("paths", [])]
        database = report.get("database", "")
        if database:
            path = Path(database)
            if not path.name.startswith(f"test_gameplay_{pid}_"):
                raise ValueError("Database custody mismatch")
            paths.extend(Path(database + suffix) for suffix in ("", "-wal", "-shm", "-journal"))
        for path in paths:
            if f"_{pid}_" not in path.name or path.is_symlink():
                raise ValueError("State path custody mismatch")
            for candidate in (path, Path(str(path) + ".pending")):
                if candidate.is_symlink():
                    raise ValueError("State path custody mismatch")
                if candidate.exists():
                    candidate.unlink()
                    removed += 1
    lease_path.unlink()
    return {"passed": True, "processes_terminated": len(terminated), "remaining": 0, "state_removed": removed}


def main() -> int:
    mode, report, nonce = sys.argv[1:4]
    report_path = Path(report)
    if mode == "run":
        if os.getsid(0) != os.getpid() or os.getpgrp() != os.getpid():
            os.setsid()
        os.environ[MARKER] = nonce
        info = process_info(os.getpid())
        lease = {"pid": os.getpid(), "started": info["started"], "nonce": nonce}
        descriptor = os.open(str(report_path) + ".group.json", os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump(lease, output)
        os.execv(sys.argv[4], sys.argv[4:])
    if mode != "stop":
        raise ValueError("Unknown containment mode")
    result = stop(report_path, nonce, int(sys.argv[4]))
    print("CONTAINED_CLEANUP " + json.dumps(result))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("CONTAINED_CLEANUP " + json.dumps({"passed": False, "error": type(exc).__name__}))
        sys.exit(1)