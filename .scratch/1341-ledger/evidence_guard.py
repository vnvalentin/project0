#!/usr/bin/env python3
"""Source custody and failure-safe finalization for owned ledger experiments."""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def identity():
    errors = []
    def git(*arguments):
        try:
            return subprocess.check_output(
                ["git", *arguments], stderr=subprocess.DEVNULL, timeout=10
            ).decode("utf-8")
        except (OSError, subprocess.SubprocessError, UnicodeError):
            errors.append("git_identity_not_observed:" + arguments[0])
            return None
    status = git("status", "--porcelain")
    revision = git("rev-parse", "HEAD")
    revision = revision.strip() if revision is not None else "NOT_OBSERVED"
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        revision = "NOT_OBSERVED"
        errors.append("revision_not_observed")
    clean = "NOT_OBSERVED" if status is None else status == ""
    if clean is False:
        errors.append("source_not_clean")
    names = git("ls-files", "-z")
    hashes = {}
    if names is not None:
        for name in names.split("\0"):
            if not name:
                continue
            try:
                hashes[name] = hashlib.sha256(Path(name).read_bytes()).hexdigest()
            except OSError:
                hashes[name] = "NOT_OBSERVED"
                errors.append("source_hash_not_observed:" + name)
        if ".scratch/1341-ledger/evidence_guard.py" not in hashes:
            errors.append("guard_source_not_tracked")
    return {"revision": revision, "clean": clean, "source_sha256": hashes, "errors": errors}


def read_object(path, errors, label):
    try:
        if path.is_symlink():
            raise OSError("evidence symlink refused")
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError("object required")
        return value
    except (OSError, ValueError, UnicodeError):
        errors.append(label + "_not_observed")
        return None


def retain(path, record):
    record["result_retention"] = "OBSERVED"
    try:
        if path.is_symlink():
            raise OSError("result symlink refused")
        path.write_text(json.dumps(record, indent=2) + "\n")
    except OSError:
        record["status"] = "failed"
        record["result_retention"] = "NOT_OBSERVED"
        record.setdefault("evidence_errors", []).append("result_retention_not_observed")
        print(json.dumps(record))
        return 1
    print(json.dumps(record))
    return 0 if record["status"] == "passed" else 1


def main():
    mode, directory = sys.argv[1:3]
    out = Path(directory)
    if mode == "start":
        snapshot = identity()
        try:
            (out / "source-start.json").write_text(json.dumps(snapshot, indent=2) + "\n")
        except OSError:
            return 1
        return 1 if snapshot["errors"] else 0
    if mode != "finalize":
        return 2
    original_exit, cleanup_exit = map(int, sys.argv[3:5])
    errors = []
    path = out / "result.json"
    record = read_object(path, errors, "result_preparation")
    if record is None:
        record = {"status": "failed", "reason": "result_preparation_not_observed"}
    if record.get("status") not in ["passed", "failed"]:
        errors.append("result_status_not_observed")
    start = read_object(out / "source-start.json", errors, "source_start")
    end = identity()
    errors.extend("final_" + error for error in end["errors"])
    valid_start = (
        start is not None and set(start) == {"revision", "clean", "source_sha256", "errors"}
        and start["clean"] is True and isinstance(start["revision"], str)
        and re.fullmatch(r"[0-9a-f]{40}", start["revision"]) is not None
        and isinstance(start["source_sha256"], dict) and bool(start["source_sha256"])
        and all(isinstance(name, str) and isinstance(value, str)
                and re.fullmatch(r"[0-9a-f]{64}", value) is not None
                for name, value in start["source_sha256"].items())
        and start["errors"] == []
    )
    if not valid_start:
        errors.append("source_start_not_qualified")
    elif start["revision"] != end["revision"] or start["source_sha256"] != end["source_sha256"]:
        errors.append("source_changed_during_run")
    try:
        removed = not (out / "user-data").exists()
    except OSError:
        removed = "NOT_OBSERVED"
    if removed is not True or cleanup_exit != 0:
        errors.append("cleanup_unverified")
    if original_exit != 0:
        errors.append("runner_failed")
    record.update({"source_start": start if start is not None else "NOT_OBSERVED",
                   "source_end": end, "owned_xdg_removed": removed,
                   "cleanup_verified": removed is True and cleanup_exit == 0,
                   "runner_exit": original_exit, "cleanup_exit": cleanup_exit,
                   "evidence_errors": errors})
    if errors:
        record["status"] = "failed"
    return retain(path, record)


if __name__ == "__main__":
    raise SystemExit(main())
