import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


REQUIRED_JOBS = ["ownership", "godot", "records", "python", "launcher"]
SHA = re.compile(r"[0-9a-f]{40}")


def windows_tooling(path):
    return (path.startswith("scripts/") and len(PurePosixPath(path).parts) == 2
            and path.endswith(".ps1")) or path == "docs/validation-ownership.md"


def digest(tree):
    return hashlib.sha256(json.dumps(tree, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def route(metadata):
    for field in ("candidate", "baseline"):
        if not isinstance(metadata.get(field), str) or not SHA.fullmatch(metadata[field]):
            raise ValueError(f"missing or invalid {field} identity")
    if metadata.get("approved_baseline") != metadata["baseline"]:
        raise ValueError("exact approved baseline identity is required")
    labels = metadata.get("labels")
    if not isinstance(labels, list) or any(not isinstance(label, str) for label in labels):
        raise ValueError("missing ownership labels")
    trees = [metadata.get("candidate_tree"), metadata.get("baseline_tree")]
    for tree in trees:
        if not isinstance(tree, dict) or not tree:
            raise ValueError("missing complete source tree")
        for path, blob in tree.items():
            if (not isinstance(path, str) or path.startswith("/") or "\\" in path
                    or ".." in PurePosixPath(path).parts or not SHA.fullmatch(blob)):
                raise ValueError("invalid source tree entry")
    candidate_tree, baseline_tree = trees
    changed = sorted(path for path in candidate_tree.keys() | baseline_tree.keys()
                     if candidate_tree.get(path) != baseline_tree.get(path))
    windows = "platform:windows-required" in labels
    linux_roots = {"server", "shared", "tests", "scripts", "infra", "deploy", "dashboard",
                   "operator_console", "docs", ".github", ".agents", "addons"}
    linux_files = {"AGENTS.md", "CLAUDE.md", "CONTEXT.md", "HOSHIN.MD", "project.godot",
                   ".gutconfig.json", ".gitignore", ".gitattributes", "skills-lock.json"}
    for path in changed:
        if path.startswith(("client/", "native/")) or path == "export_presets.cfg":
            raise ValueError("native/client changes require an explicit artifact contract")
        if not windows_tooling(path) and path.split("/")[0] not in linux_roots and path not in linux_files:
            raise ValueError(f"unknown ownership: {path}")
        if windows_tooling(path) and not windows:
            raise ValueError("Windows tooling requires platform:windows-required")
    linux_inputs = {path: blob for path, blob in candidate_tree.items() if not windows_tooling(path)}
    if windows:
        baseline_inputs = {path: blob for path, blob in baseline_tree.items() if not windows_tooling(path)}
        if linux_inputs != baseline_inputs:
            raise ValueError("mixed Windows/Linux inputs: source hash mismatch")
    return {"schema_version": 1, "candidate": metadata["candidate"],
            "baseline": metadata["baseline"], "linux_ref": metadata["baseline"] if windows else metadata["candidate"],
            "windows_ref": metadata["candidate"], "windows_required": windows,
            "input_digest": digest(linux_inputs), "changed_paths": changed,
            "required_jobs": REQUIRED_JOBS.copy(), "linux_host": "192.168.1.254",
            "runtime_acceptance": "supporting-only; not Windows or paired acceptance"}


def reconcile(plan, results):
    errors = []
    expected = plan.get("expected_tests", {})
    if plan.get("required_jobs") != REQUIRED_JOBS:
        errors.append("required gates changed or missing")
    for job in REQUIRED_JOBS:
        result = results.get(job, {})
        source = plan["windows_ref"] if job == "launcher" else plan["linux_ref"]
        for field, value in {"schema_version": 1, "candidate": plan["candidate"],
                             "source_ref": source, "input_digest": plan["input_digest"],
                             "status": "success", "skipped": 0}.items():
            if result.get(field) != value:
                errors.append(f"{job}: invalid {field}")
        if not expected.get(job) or sorted(result.get("tests", [])) != sorted(expected[job]):
            errors.append(f"{job}: missing or unexpected test coverage")
        artifacts = result.get("artifacts")
        if not isinstance(artifacts, dict) or not artifacts or any(
                not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value)
                for value in artifacts.values()):
            errors.append(f"{job}: missing artifact hashes")
    return errors


def command(*args):
    return subprocess.check_output(args, text=True, encoding="utf-8", timeout=60).strip()


def git_tree(ref):
    entries = command("git", "ls-tree", "-rz", "--full-tree", ref).split("\0")
    tree = {}
    for entry in filter(None, entries):
        header, path = entry.split("\t", 1)
        mode, kind, blob = header.split()
        if kind != "blob" or mode not in ("100644", "100755"):
            raise ValueError(f"unsupported source entry: {path}")
        tree[path] = blob
    return tree


def metadata_from_event():
    if sys.platform != "win32":
        raise ValueError("candidate acquisition/classification requires Windows metadata host")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    repository = os.environ["GITHUB_REPOSITORY"]
    candidate = event.get("pull_request", {}).get("head", {}).get("sha", os.environ["GITHUB_SHA"])
    if command("git", "rev-parse", "HEAD") != candidate:
        raise ValueError("checkout does not match event candidate")
    approved = command("git", "rev-parse", "refs/remotes/origin/main")
    if os.environ["GITHUB_EVENT_NAME"] == "pull_request":
        number = event["number"]
    elif os.environ["GITHUB_EVENT_NAME"] == "push" and os.environ["GITHUB_REF"] != "refs/heads/main":
        pulls = json.loads(command("gh", "api", f"repos/{repository}/commits/{candidate}/pulls"))
        matches = [pull for pull in pulls if pull["state"] == "open" and pull["head"]["sha"] == candidate
                   and pull["base"]["ref"] == "main"]
        if len(matches) != 1:
            raise ValueError("push requires one current open PR for ownership classification")
        number = matches[0]["number"]
    elif os.environ["GITHUB_EVENT_NAME"] == "push" and os.environ["GITHUB_REF"] == "refs/heads/main":
        pulls = json.loads(command("gh", "api", f"repos/{repository}/commits/{candidate}/pulls"))
        matches = [pull for pull in pulls if pull.get("merged_at") and pull.get("merge_commit_sha") == candidate
                   and pull["base"]["ref"] == "main"]
        if len(matches) != 1 or candidate != approved:
            raise ValueError("main push requires one identified merged PR")
        baseline = event.get("before")
        if not isinstance(baseline, str) or not SHA.fullmatch(baseline):
            raise ValueError("missing pre-merge main identity")
        if command("git", "rev-parse", f"{candidate}^1") != baseline:
            raise ValueError("main push must contain one merge commit")
        return {"candidate": candidate, "baseline": baseline, "approved_baseline": baseline,
                "labels": [label["name"] for label in matches[0]["labels"]],
                "candidate_tree": git_tree(candidate), "baseline_tree": git_tree(baseline)}
    else:
        raise ValueError("unsupported event")
    pull = json.loads(command("gh", "pr", "view", str(number), "--repo", repository,
                             "--json", "headRefOid,baseRefOid,baseRefName,labels,isCrossRepository,state"))
    if (pull["headRefOid"] != candidate or pull["baseRefOid"] != approved or pull["baseRefName"] != "main"
            or pull["isCrossRepository"] or pull["state"] != "OPEN"):
        raise ValueError("stale, foreign, or unapproved PR source identity")
    command("git", "merge-base", "--is-ancestor", approved, candidate)
    return {"candidate": candidate, "baseline": approved, "approved_baseline": approved,
            "labels": [label["name"] for label in pull["labels"]],
            "candidate_tree": git_tree(candidate), "baseline_tree": git_tree(approved)}


def expected_tests(tree):
    return {
        "ownership": ["scripts/test_validation_ownership.py", "scripts/test_ci_validation_routing.py",
                      "scripts/check_validation_ownership.py"],
        "godot": sorted(path for path in tree if re.fullmatch(r"tests/(unit|integration)/test_[^/]+\.gd", path)),
        "records": ["scripts/check_record_sync.sh", "scripts/test_deploy_containers.sh"],
        "python": sorted(path for path in tree if re.fullmatch(r"infra/(enrollment|operator)/tests/test_[^/]+\.py", path)),
        "launcher": sorted(path for path in tree if path.startswith("native/windows_launcher/") and path.endswith("_test.go"))
                    + ["scripts/generate_1100_fixture_test.go", "scripts/test_prepare_windows_experiment_1100.ps1"],
    }


def seal(plan, job, directory):
    if job == "launcher":
        raise ValueError("Windows native executed coverage must be supplied by #1244")
    if command("git", "rev-parse", "HEAD") != plan["linux_ref"]:
        raise ValueError("result source identity mismatch")
    tests = []
    if job in ("godot", "python"):
        report = directory / ("gut.xml" if job == "godot" else "python.xml")
        root = ET.parse(report).getroot()
        cases = root.findall(".//testcase")
        if not cases or any(case.find(tag) is not None for case in cases for tag in ("failure", "error", "skipped")):
            raise ValueError("empty, failed, or skipped test result")
        tests = sorted({suite.attrib["name"] for suite in root.iter("testsuite") if suite.findall("testcase")}) if job == "godot" else sorted({case.attrib["file"] for case in cases})
    elif job == "ownership":
        for name in ("ownership-tests.json", "routing-tests.json", "ownership.json"):
            report = json.loads((directory / name).read_text(encoding="utf-8"))
            if report.get("passed") is not True or report.get("skipped", 0) not in (0, []):
                raise ValueError(f"failed ownership evidence: {name}")
        tests = ["scripts/test_validation_ownership.py", "scripts/test_ci_validation_routing.py",
                 "scripts/check_validation_ownership.py"]
    elif job == "records":
        if "record-sync: 0 error(s), 0 warning(s)" not in (directory / "records.log").read_text():
            raise ValueError("record-sync evidence missing")
        if "deploy containers: durable artifact, targeted service, and recovery verified" not in (directory / "deploy.log").read_text():
            raise ValueError("deployment contract evidence missing")
        tests = ["scripts/check_record_sync.sh", "scripts/test_deploy_containers.sh"]
    if sorted(tests) != sorted(plan["expected_tests"][job]):
        raise ValueError(f"{job}: missing or unexpected executed tests")
    artifacts = {path.relative_to(directory).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in directory.rglob("*") if path.is_file() and path.name != "result.json"}
    if not artifacts:
        raise ValueError("no execution artifacts")
    return {"schema_version": 1, "candidate": plan["candidate"], "source_ref": plan["linux_ref"],
            "input_digest": plan["input_digest"], "status": "success", "skipped": 0,
            "tests": tests, "artifacts": artifacts}


def main():
    parser = argparse.ArgumentParser(description="Fail-closed CI source routing and evidence reconciliation.")
    parser.add_argument("action", choices=["plan", "verify-source", "seal", "aggregate"])
    parser.add_argument("--plan", type=Path, default=Path("routing/plan.json"))
    parser.add_argument("--output", type=Path, default=Path("routing/report.json"))
    parser.add_argument("--results", type=Path)
    parser.add_argument("--job", choices=REQUIRED_JOBS)
    args = parser.parse_args()
    report = {"schema_version": 1, "passed": False, "errors": []}
    try:
        if args.action == "plan":
            metadata = metadata_from_event()
            plan = route(metadata)
            plan["expected_tests"] = expected_tests(metadata["candidate_tree"])
            args.plan.parent.mkdir(parents=True, exist_ok=True)
            args.plan.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
            if os.environ.get("GITHUB_OUTPUT"):
                with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                    output.write(f"linux_ref={plan['linux_ref']}\nwindows_ref={plan['windows_ref']}\n")
        else:
            plan = json.loads(args.plan.read_text(encoding="utf-8"))
            if args.action == "verify-source":
                actual = command("git", "rev-parse", "HEAD")
                if actual != plan["linux_ref"]:
                    raise ValueError("Linux checkout identity mismatch")
                inputs = {path: blob for path, blob in git_tree(actual).items() if not windows_tooling(path)}
                if digest(inputs) != plan["input_digest"]:
                    raise ValueError("Linux source hash mismatch")
            elif args.action == "seal":
                if not args.job:
                    raise ValueError("job required")
                directory = Path("build/validation")
                result = seal(plan, args.job, directory)
                (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
            else:
                if not args.results:
                    raise ValueError("results directory required")
                results = {}
                for job in REQUIRED_JOBS:
                    matches = list(args.results.glob(f"result-{job}-*/result.json"))
                    if len(matches) > 1:
                        raise ValueError(f"{job}: ambiguous result artifacts")
                    result_path = matches[0] if matches else args.results / job / "result.json"
                    if result_path.is_file():
                        result = json.loads(result_path.read_text(encoding="utf-8-sig"))
                        for name, expected_hash in result.get("artifacts", {}).items():
                            artifact = (result_path.parent / name).resolve()
                            if not artifact.is_relative_to(result_path.parent.resolve()) or not artifact.is_file():
                                raise ValueError(f"{job}: missing artifact {name}")
                            if hashlib.sha256(artifact.read_bytes()).hexdigest() != expected_hash:
                                raise ValueError(f"{job}: artifact hash mismatch {name}")
                        results[job] = result
                report["errors"] = reconcile(plan, results)
        report["passed"] = not report["errors"]
    except (OSError, ValueError, TypeError, KeyError, ET.ParseError, subprocess.SubprocessError) as error:
        report["errors"] = [str(error)]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())