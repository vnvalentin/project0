import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat


SHA = re.compile(r"[0-9a-f]{40}")
REQUIRED_CHECKS = {
    "Validation ownership and client boundary", "Godot GUT suite", "Delivery record sync",
    "Python service tests", "Windows launcher tests", "project0-godot", "project0-infra",
    "project0-dashboard",
}
CONTEXT_FIELDS = (
    "GITHUB_REPOSITORY", "GITHUB_EVENT_NAME", "GITHUB_SHA", "GITHUB_REF",
    "GITHUB_WORKFLOW_REF", "GITHUB_WORKFLOW_SHA", "GITHUB_JOB", "RUNNER_NAME",
    "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT",
)


def decide(policy, context, now):
    denied = {"allowed": False, "reason": "no matching independent source approval"}
    if not isinstance(policy, dict) or not isinstance(context, dict) or type(now) is not int:
        return denied
    if (type(policy.get("schema_version")) is not int or policy["schema_version"] != 1
            or policy.get("repository") != "vnvalentin/project0" or policy.get("runner") != "okami"):
        return denied
    if (context.get("GITHUB_REPOSITORY") != policy["repository"]
            or context.get("RUNNER_NAME") != policy["runner"]
            or context.get("CANDIDATE_REPOSITORY") != policy["repository"]):
        return denied
    approvals = policy.get("approvals")
    if not isinstance(approvals, list):
        return denied
    matches = []
    fields = {"event": "GITHUB_EVENT_NAME", "sha": "GITHUB_SHA", "ref": "GITHUB_REF",
              "workflow_ref": "GITHUB_WORKFLOW_REF", "workflow_sha": "GITHUB_WORKFLOW_SHA",
              "candidate_sha": "CANDIDATE_SHA"}
    for approval in approvals:
        if not isinstance(approval, dict):
            return denied
        if any(not isinstance(approval.get(field), str) or not approval[field]
               or approval[field] != context.get(variable) for field, variable in fields.items()):
            continue
        if approval["event"] not in ("pull_request", "push", "workflow_dispatch"):
            continue
        if any(not isinstance(approval.get(field), str) or not SHA.fullmatch(approval[field])
               for field in ("sha", "workflow_sha", "source_ref", "source_tree", "candidate_sha")):
            continue
        if (not approval["workflow_ref"].startswith(policy["repository"] + "/.github/workflows/")
                or not approval["workflow_ref"].endswith("@" + approval["ref"])):
            continue
        jobs = approval.get("jobs")
        if (not isinstance(jobs, list) or not jobs or any(not isinstance(job, str) for job in jobs)
                or len(set(jobs)) != len(jobs) or context.get("GITHUB_JOB") not in jobs):
            continue
        if (type(approval.get("expires_at")) is not int or now >= approval["expires_at"]
                or type(approval.get("approval_issue")) is not int or approval["approval_issue"] <= 0
                or approval.get("platform") != "linux" or type(approval.get("windows_required")) is not bool):
            continue
        if approval["event"] == "pull_request" and (
                type(context.get("WINDOWS_REQUIRED")) is not bool
                or context["WINDOWS_REQUIRED"] != approval["windows_required"]):
            continue
        checks = approval.get("required_checks")
        if (not isinstance(checks, list) or any(not isinstance(check, str) for check in checks)
                or not REQUIRED_CHECKS.issubset(checks) or len(set(checks)) != len(checks)):
            continue
        contract = approval.get("contract")
        if contract == "direct-source":
            if approval["source_ref"] not in (approval["sha"], approval["candidate_sha"]) or approval["windows_required"]:
                continue
        elif contract == "approved-ref":
            source_digest = approval.get("linux_input_digest")
            if (not approval["windows_required"] or approval["source_ref"] in (approval["sha"], approval["candidate_sha"])
                    or approval.get("baseline_ref") != approval["source_ref"]
                    or approval.get("authority_ref") != approval["source_ref"]
                    or not isinstance(source_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", source_digest)
                    or approval.get("candidate_linux_input_digest") != source_digest
                    or approval.get("image_publication") is not False):
                continue
        else:
            continue
        if approval["event"] == "workflow_dispatch" or approval["ref"].startswith("refs/tags/"):
            if approval.get("approved_main_sha") != approval["source_ref"]:
                continue
        matches.append(approval)
    if len(matches) != 1:
        return denied
    return {"allowed": True, "reason": "independent exact-source approval",
            "source_ref": matches[0]["source_ref"], "source_tree": matches[0]["source_tree"],
            "windows_required": matches[0]["windows_required"],
            "approval_issue": matches[0]["approval_issue"]}


def event_context(environment, event):
    context = {name: environment.get(name, "") for name in CONTEXT_FIELDS}
    if event["repository"]["full_name"] != context["GITHUB_REPOSITORY"]:
        raise ValueError("event repository mismatch")
    context["CANDIDATE_REPOSITORY"] = event["repository"]["full_name"]
    context["CANDIDATE_SHA"] = context["GITHUB_SHA"]
    if context["GITHUB_EVENT_NAME"] == "pull_request":
        pull = event["pull_request"]
        context["CANDIDATE_REPOSITORY"] = pull["head"]["repo"]["full_name"]
        context["CANDIDATE_SHA"] = pull["head"]["sha"]
        labels = pull["labels"]
        if not isinstance(labels, list) or any(not isinstance(label, dict) or not isinstance(label.get("name"), str) for label in labels):
            raise ValueError("invalid ownership labels")
        context["WINDOWS_REQUIRED"] = any(label["name"] == "platform:windows-required" for label in labels)
    return context


def trusted_file(path):
    path = Path(path)
    if not path.is_absolute():
        return False
    for entry in (path, *path.parents):
        info = entry.lstat()
        if info.st_uid != 0 or info.st_mode & 0o022 or stat.S_ISLNK(info.st_mode):
            return False
        if entry == path and not stat.S_ISREG(info.st_mode):
            return False
        if entry != path and not stat.S_ISDIR(info.st_mode):
            return False
    return True


def load_policy(path):
    source = Path(__file__).absolute()
    if os.name != "posix" or not trusted_file(source) or not trusted_file(path):
        raise ValueError("admission authority is not independently owned")
    policy = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(policy, dict) or policy.get("gate_sha256") != hashlib.sha256(source.read_bytes()).hexdigest():
        raise ValueError("admission authority fingerprint mismatch")
    return policy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", type=Path, required=True)
    args = parser.parse_args()
    import time
    context = {name: os.environ.get(name, "") for name in CONTEXT_FIELDS}
    try:
        policy = load_policy(args.policy)
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8-sig"))
        context = event_context(os.environ, event)
        result = decide(policy, context, int(time.time()))
        if result["allowed"]:
            with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
                output.write(f"PROJECT0_APPROVED_SOURCE_REF={result['source_ref']}\n")
                output.write(f"PROJECT0_APPROVED_SOURCE_TREE={result['source_tree']}\n")
                output.write(f"PROJECT0_SOURCE_WINDOWS_REQUIRED={str(result['windows_required']).lower()}\n")
    except (OSError, ValueError, TypeError, KeyError):
        result = {"allowed": False, "reason": "invalid or unavailable admission policy"}
    result["request"] = context
    print(json.dumps(result, sort_keys=True))
    return 0 if result["allowed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())