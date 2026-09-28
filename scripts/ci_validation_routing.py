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
WINDOWS_ASSETS = {"docs/validation-ownership.md", "scripts/client_package_inventory.gd",
                  "scripts/windows_paired_client.gd", "tests/fixtures/windows_client_packages.gd"}


def windows_tooling(path):
    return (path.startswith("scripts/") and len(PurePosixPath(path).parts) == 2
            and path.endswith(".ps1")) or path in WINDOWS_ASSETS


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
                   "operator_console", "docs", ".github", ".agents", ".scratch", "addons"}
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
    elif (os.environ["GITHUB_EVENT_NAME"] == "workflow_dispatch"
          or (os.environ["GITHUB_EVENT_NAME"] == "push"
              and os.environ["GITHUB_REF"].startswith("refs/tags/"))):
        command("git", "merge-base", "--is-ancestor", candidate, approved)
        return {"candidate": candidate, "baseline": candidate, "approved_baseline": candidate,
                "labels": [], "candidate_tree": git_tree(candidate), "baseline_tree": git_tree(candidate)}
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


def expected_tests(tree, windows_required=False):
    return {
        "ownership": ["scripts/test_validation_ownership.py", "scripts/test_ci_validation_routing.py",
                      "scripts/test_ci_runner_admission.py",
                  "scripts/test_hosted_gut_container.sh",
                      "scripts/check_validation_ownership.py"],
        "godot": sorted(path for path in tree if re.fullmatch(r"tests/(unit|integration)/test_[^/]+\.gd", path)),
        "records": ["scripts/check_record_sync.sh", "scripts/test_deploy_containers.sh"],
        "python": sorted(path for path in tree if re.fullmatch(r"infra/(enrollment|operator)/tests/test_[^/]+\.py", path)),
        "launcher": sorted(path for path in tree if path.startswith("native/windows_launcher/") and path.endswith("_test.go"))
                    + ["scripts/generate_1100_fixture_test.go", "scripts/test_prepare_windows_experiment_1100.ps1"]
                    + (["scripts/test_build_current_deployment.ps1", "scripts/test_windows_client_validation.ps1"] if windows_required else []),
    }


def launcher_tests(directory):
    summary = json.loads((directory / "validation-summary.json").read_text(encoding="utf-8-sig"))
    if (summary.get("status") != "passed" or type(summary.get("exit_code")) is not int
            or summary["exit_code"] != 0 or summary.get("includes_fixture_preparation") is not True
            or "windows" not in str(summary.get("os", "")).lower()):
        raise ValueError("failed or missing native Windows summary")
    log = (directory / "execution.log").read_text(encoding="utf-8-sig")
    marker = "Fixture lifecycle PASS: publication, version/hash/missing/signing rejection, prior evidence preserved, staging removed."
    if marker not in log:
        raise ValueError("fixture preparation execution evidence missing")
    events = [json.loads(line) for line in log.splitlines() if line.lstrip().startswith("{")]
    events = [event for event in events if isinstance(event, dict) and "Action" in event and "Package" in event]
    if not events or any(event["Action"] in ("fail", "skip") for event in events):
        raise ValueError("empty, failed, or skipped native Go execution")
    tests = []
    packages = set()
    for filename, prefix in (("native-package.json", "native/windows_launcher"),
                             ("fixture-package.json", "scripts")):
        metadata = json.loads((directory / filename).read_text(encoding="utf-8-sig"))
        package = metadata["ImportPath"]
        collected = metadata.get("CollectedTests")
        selected_tests = metadata.get("SelectedTests", collected)
        opt_in = metadata.get("OptInTests", [])
        sources = (metadata.get("TestGoFiles") or []) + (metadata.get("XTestGoFiles") or [])
        if (package in packages or not isinstance(collected, list) or not collected or not sources
                or any(not isinstance(name, str) or not re.fullmatch(r"[^/\\:]+_test\.go", name) for name in sources)):
            raise ValueError("invalid native test inventory")
        allowed_opt_in = {"TestExperiment1100RealEngine"} if package == "project0/windows-launcher" else set()
        expected_opt_in = set(collected) & allowed_opt_in
        if (not isinstance(selected_tests, list) or not selected_tests or not isinstance(opt_in, list)
                or set(opt_in) != expected_opt_in or set(selected_tests) != set(collected) - expected_opt_in):
            raise ValueError("unapproved native test selection")
        packages.add(package)
        selected = [event for event in events if event["Package"] == package]
        started = {event["Test"] for event in selected if event["Action"] == "run" and "/" not in event.get("Test", "/")}
        passed = {event["Test"] for event in selected if event["Action"] == "pass" and "/" not in event.get("Test", "/")}
        if set(selected_tests) != started or started != passed:
            raise ValueError("missing native test execution")
        tests.extend(prefix + "/" + name for name in sources)
    completed = {event["Package"] for event in events if event["Action"] == "pass" and "Test" not in event}
    if completed != packages:
        raise ValueError("incomplete or unexpected native packages")
    return sorted(tests + ["scripts/test_prepare_windows_experiment_1100.ps1"])


def client_tests(directory):
    control = json.loads((directory / "client/package-controls/result.json").read_text(encoding="utf-8-sig"))
    build = json.loads((directory / "client/build.json").read_text(encoding="utf-8-sig"))
    if not isinstance(control, dict) or not isinstance(build, dict):
        raise ValueError("invalid Windows client reports")
    cases = control.get("cases")
    if (control.get("check") != "windows-client-package-boundary-controls" or control.get("passed") is not True
            or control.get("cleanup") is not True or not isinstance(cases, list) or not cases
            or any(not isinstance(case, dict) or case.get("passed") is not True for case in cases)):
        raise ValueError("missing or failed Windows package execution")
    if (build.get("status") != "passed" or build.get("cleanup") is not True
            or type(build.get("failure_cases")) is not int or build["failure_cases"] <= 0):
        raise ValueError("missing or failed Windows builder execution")
    return ["scripts/test_build_current_deployment.ps1", "scripts/test_windows_client_validation.ps1"]


def native_omissions(directory):
    metadata = json.loads((directory / "native-package.json").read_text(encoding="utf-8-sig"))
    opt_in = metadata.get("OptInTests", [])
    if (not isinstance(opt_in, list) or len(opt_in) != len(set(opt_in))
            or any(name != "TestExperiment1100RealEngine" for name in opt_in)):
        raise ValueError("invalid native opt-in inventory")
    return [{"test": name, "reason": "explicit opt-in via scripts/run_windows_experiment_1100.ps1"}
            for name in opt_in]


def seal(plan, job, directory):
    source_ref = plan["windows_ref"] if job == "launcher" else plan["linux_ref"]
    if command("git", "rev-parse", "HEAD") != source_ref:
        raise ValueError("result source identity mismatch")
    tests = []
    if job == "launcher":
        if sys.platform != "win32":
            raise ValueError("native Windows sealing requires the Windows execution host")
        tests = launcher_tests(directory)
        if plan.get("windows_required"):
            tests += client_tests(directory)
    elif job in ("godot", "python"):
        report = directory / ("gut.xml" if job == "godot" else "python.xml")
        root = ET.parse(report).getroot()
        cases = root.findall(".//testcase")
        if not cases or any(case.find(tag) is not None for case in cases for tag in ("failure", "error", "skipped")):
            raise ValueError("empty, failed, or skipped test result")
        tests = sorted({suite.attrib["name"] for suite in root.iter("testsuite") if suite.findall("testcase")}) if job == "godot" else sorted({case.attrib["file"] for case in cases})
    elif job == "ownership":
        for name in ("ownership-tests.json", "routing-tests.json", "runner-admission-tests.json",
                 "hosted-container-tests.json", "ownership.json"):
            report = json.loads((directory / name).read_text(encoding="utf-8"))
            if report.get("passed") is not True or report.get("skipped", 0) not in (0, []):
                raise ValueError(f"failed ownership evidence: {name}")
            if name != "ownership.json":
                count = report.get("tests_run" if name == "ownership-tests.json" else "tests")
                if (type(count) is not int or count <= 0
                        or report.get("failures") not in (0, [])
                        or report.get("errors") not in (0, [])
                        or report.get("skipped") not in (0, [])):
                    raise ValueError(f"missing or failed ownership execution: {name}")
            if name == "hosted-container-tests.json":
                cases = report.get("cases")
                expected_cases = [
                    {"name": "reject_privileged", "passed": True, "exit_code": 2},
                    {"name": "reject_network_host", "passed": True, "exit_code": 2},
                    {"name": "reject_cap_add", "passed": True, "exit_code": 2},
                    {"name": "induced_failure_cleanup", "passed": True, "exit_code": 23, "surviving_containers": 0},
                    {"name": "host_sealer_success", "passed": True, "exit_code": 0, "surviving_containers": 0},
                ]
                if report.get("tests") != len(expected_cases) or cases != expected_cases:
                    raise ValueError("hosted container control evidence is incomplete")
        tests = ["scripts/test_validation_ownership.py", "scripts/test_ci_validation_routing.py",
                 "scripts/test_ci_runner_admission.py",
                 "scripts/test_hosted_gut_container.sh",
                 "scripts/check_validation_ownership.py"]
    elif job == "records":
        if not re.search(r"^record-sync: 0 error\(s\), \d+ warning\(s\)$",
                         (directory / "records.log").read_text(), re.MULTILINE):
            raise ValueError("record-sync evidence missing")
        if "deploy containers: durable artifact, targeted service, and recovery verified" not in (directory / "deploy.log").read_text():
            raise ValueError("deployment contract evidence missing")
        tests = ["scripts/check_record_sync.sh", "scripts/test_deploy_containers.sh"]
    if sorted(tests) != sorted(plan["expected_tests"][job]):
        raise ValueError(f"{job}: missing or unexpected executed tests")
    artifacts = {path.relative_to(directory).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in directory.rglob("*") if path.is_file() and path != directory / "result.json"}
    if not artifacts:
        raise ValueError("no execution artifacts")
    result = {"schema_version": 1, "candidate": plan["candidate"], "source_ref": source_ref,
              "input_digest": plan["input_digest"], "status": "success", "skipped": 0,
              "tests": tests, "artifacts": artifacts}
    if job == "launcher":
        result["not_evaluated"] = native_omissions(directory)
    return result


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
            plan["expected_tests"] = expected_tests(metadata["candidate_tree"], plan["windows_required"])
            args.plan.parent.mkdir(parents=True, exist_ok=True)
            args.plan.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
            if os.environ.get("GITHUB_OUTPUT"):
                with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                    output.write(f"linux_ref={plan['linux_ref']}\nwindows_ref={plan['windows_ref']}\n")
                    output.write(f"windows_required={str(plan['windows_required']).lower()}\n")
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
                if args.job == "launcher":
                    directory = directory / "windows_launcher"
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
                        if job == "launcher":
                            if ("native-package.json" not in result.get("artifacts", {})
                                    or result.get("not_evaluated") != native_omissions(result_path.parent)):
                                raise ValueError("launcher: missing or inconsistent native opt-in disclosure")
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