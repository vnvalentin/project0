#!/usr/bin/env python3
"""Bounded GitHub API preflight and Project-command evidence capture."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys


PREFLIGHT_QUERY = "query { rateLimit { limit remaining cost resetAt } viewer { login } }"
QUOTA_QUERY = ".resources | {graphql, core}"


def _parse_json(value):
    try:
        return json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return None


def _quota_snapshot(runner):
    result = runner(
        ["gh", "api", "rate_limit", "--jq", QUOTA_QUERY],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None, result.stderr or result.stdout or "REST rate_limit request failed", "quota_unavailable"

    quota = _parse_json(result.stdout)
    graphql = quota.get("graphql") if isinstance(quota, dict) else None
    core = quota.get("core") if isinstance(quota, dict) else None
    remaining = graphql.get("remaining") if isinstance(graphql, dict) else None
    if not isinstance(remaining, int) or remaining < 0 or not isinstance(core, dict):
        return None, "REST rate_limit response is missing valid graphql/core quota data", "invalid_quota_response"
    return {"graphql": graphql, "core": core}, None, None


def _write_evidence(path, evidence):
    evidence["schema_version"] = 1
    evidence["recorded_at"] = datetime.now(timezone.utc).isoformat()
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(evidence, stream, indent=2, sort_keys=True)
        stream.write("\n")


def _preflight(evidence_path, runner):
    evidence = {"operation": "graphql_preflight"}
    quota, quota_error, quota_reason = _quota_snapshot(runner)
    if quota_error is not None:
        evidence.update(status="blocked", reason=quota_reason, quota_error=quota_error)
        _write_evidence(evidence_path, evidence)
        return 1

    evidence["quota"] = quota
    if quota["graphql"]["remaining"] == 0:
        evidence.update(status="blocked", reason="graphql_budget_exhausted")
        _write_evidence(evidence_path, evidence)
        return 1

    result = runner(
        ["gh", "api", "graphql", "-f", f"query={PREFLIGHT_QUERY}"],
        capture_output=True,
        text=True,
        check=False,
    )
    response = _parse_json(result.stdout)
    data = response.get("data") if isinstance(response, dict) else None
    rate_limit = data.get("rateLimit") if isinstance(data, dict) else None
    viewer = data.get("viewer") if isinstance(data, dict) else None
    errors = response.get("errors") if isinstance(response, dict) else None
    if result.returncode != 0 or errors or not isinstance(rate_limit, dict) or not isinstance(viewer, dict):
        evidence.update(
            status="blocked",
            reason="graphql_preflight_failed",
            graphql={"response": result.stdout, "stderr": result.stderr, "returncode": result.returncode},
        )
        _write_evidence(evidence_path, evidence)
        if result.stderr:
            sys.stderr.write(result.stderr)
        return result.returncode or 1

    evidence.update(
        status="ready",
        graphql={"rateLimit": rate_limit, "viewer": viewer},
    )
    _write_evidence(evidence_path, evidence)
    print(json.dumps(evidence, sort_keys=True))
    return 0


def _guarded_command(evidence_path, command, runner):
    if len(command) < 2 or command[0] != "gh" or command[1] not in {"api", "project"}:
        print("guarded command must be a GitHub CLI `gh api` or `gh project` operation", file=sys.stderr)
        return 2

    if command[1] == "api" and (len(command) < 3 or command[2] != "graphql"):
        print("guarded `gh api` operations must target GraphQL; use REST directly for supported issue endpoints", file=sys.stderr)
        return 2

    result = runner(command, capture_output=True, text=True, check=False)
    guard_exit_code = result.returncode
    graphql_reason = None
    graphql_response = None
    if command[1] == "api":
        graphql_response = _parse_json(result.stdout)
        if result.returncode == 0:
            data = graphql_response.get("data") if isinstance(graphql_response, dict) else None
            errors = graphql_response.get("errors") if isinstance(graphql_response, dict) else None
            if errors:
                graphql_reason = "graphql_response_errors"
            elif not isinstance(data, dict):
                graphql_reason = "invalid_graphql_response"
            if graphql_reason is not None:
                guard_exit_code = 1

    evidence = {
        "operation": "github_cli",
        "command": command[:3],
        "returncode": result.returncode,
        "guard_exit_code": guard_exit_code,
        "status": "success" if guard_exit_code == 0 else "failed",
    }
    if graphql_reason is not None:
        evidence["reason"] = graphql_reason
    if guard_exit_code != 0:
        evidence["command_stderr"] = result.stderr
        if command[1] == "api":
            evidence["command_response"] = result.stdout
        quota, quota_error, _ = _quota_snapshot(runner)
        if quota_error is None:
            evidence["quota"] = quota
        else:
            evidence["quota_error"] = quota_error
    _write_evidence(evidence_path, evidence)

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        target = sys.stdout if guard_exit_code == 0 else sys.stderr
        target.write(result.stderr)
    return guard_exit_code


def _parser():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    preflight = subparsers.add_parser("preflight", help="check REST quota and one minimal GraphQL query")
    preflight.add_argument("--evidence", required=True, help="new JSON evidence file; existing files are never overwritten")
    guarded = subparsers.add_parser("run", help="run one Project or GraphQL command and capture failures")
    guarded.add_argument("--evidence", required=True, help="new JSON evidence file; existing files are never overwritten")
    guarded.add_argument("command", nargs=argparse.REMAINDER, help="GitHub CLI command after --")
    return parser


def main(argv=None, runner=None):
    args = _parser().parse_args(argv)
    command_runner = runner or subprocess.run
    if args.operation == "preflight":
        return _preflight(args.evidence, command_runner)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    return _guarded_command(args.evidence, command, command_runner)


if __name__ == "__main__":
    raise SystemExit(main())