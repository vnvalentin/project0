"""Static admission for the separately approved macOS component scope.

This command reads an explicit plan and ownership metadata. It never launches
Godot, a test, a server, a transport, or an installer. Existing Linux and Windows
validation retain their own preflight and execution rules.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from fnmatch import fnmatchcase
import hashlib
import json
from pathlib import Path, PurePosixPath
import platform
import re
import shlex
import socket
import sys


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "scripts/validation_ownership.json"
MAC_HOST = "Philips-MacBook-Pro-2"
MAC_SUITES = {"macos-tooling", "macos-client", "macos-admission"}
SERVER_DEPENDENCIES = {"sqlite", "canon", "ollama"}


def string_list(value: object) -> bool:
    return (
        isinstance(value, list)
        and bool(value)
        and all(isinstance(item, str) and item.strip() for item in value)
    )


def local_host(value: str) -> str:
    """Accept the standard mDNS suffix without admitting an arbitrary hostname."""
    return value[:-6] if value.endswith(".local") else value


def repository_path(root: Path, value: str) -> bool:
    path = PurePosixPath(value)
    return (
        bool(value)
        and not path.is_absolute()
        and ".." not in path.parts
        and "\\" not in value
        and value == path.as_posix()
        and (root / value).resolve().is_relative_to(root.resolve())
    )


def owners(manifest: dict, name: str) -> list[str]:
    result: list[str] = []
    parts = name.split("/")
    for suite_id, suite in manifest["suites"].items():
        if any(
            len(parts) == len(pattern.split("/"))
            and all(
                fnmatchcase(part, expected)
                for part, expected in zip(parts, pattern.split("/"))
            )
            for pattern in suite["tests"]
        ):
            result.append(suite_id)
    return result


def validate_plan(
    root: Path,
    manifest: dict,
    plan: object,
    actual_platform: str,
    actual_host: str,
) -> list[str]:
    """Validate only Mac component selections; the caller supplies observed host facts."""
    errors: list[str] = []
    if actual_platform != "Darwin" or local_host(actual_host) != MAC_HOST:
        errors.append("execution requires the assigned Darwin host Philips-MacBook-Pro-2")
    if manifest.get("schema_version") != 1:
        errors.append("ownership schema_version must be 1")
    allowed_hosts = manifest.get("hosts", {}).get("macos", [])
    if MAC_HOST not in allowed_hosts:
        errors.append("assigned Mac host is missing from ownership metadata")
    if not isinstance(plan, dict):
        return errors + ["plan must be an object"]
    if plan.get("schema_version") != 1:
        errors.append("plan schema_version must be 1")
    if plan.get("kind") != "component":
        errors.append("Mac preflight admits component plans only; paired proof is out of scope")
    steps = plan.get("steps")
    if not isinstance(steps, list) or not steps:
        return errors + ["plan requires nonempty steps"]
    selected_tests: set[str] = set()
    selected_artifacts: set[str] = set()
    forbidden_dependencies = SERVER_DEPENDENCIES | {
        item.strip().lower() for item in manifest.get("server_dependencies", [])
    }
    for index, step in enumerate(steps):
        prefix = f"step {index + 1}"
        if not isinstance(step, dict):
            errors.append(f"{prefix}: step must be an object")
            continue
        suite_id = step.get("suite")
        if not isinstance(suite_id, str) or suite_id not in MAC_SUITES:
            errors.append(f"{prefix}: only approved Mac suites may execute here")
            continue
        suite = manifest.get("suites", {}).get(suite_id)
        if not isinstance(suite, dict) or suite.get("platform") != "macos":
            errors.append(f"{prefix}: approved Mac suite metadata is missing or invalid")
            continue
        if step.get("platform") != "macos":
            errors.append(f"{prefix}: platform must be macos")
        if step.get("host") != MAC_HOST or step.get("host") not in allowed_hosts:
            errors.append(f"{prefix}: host must be the assigned Mac host")
        dependencies = step.get("dependencies")
        if not string_list(dependencies):
            errors.append(f"{prefix}: explicit nonempty dependencies are required")
        else:
            declared = {item.strip().lower() for item in dependencies}
            if {item.strip().lower() for item in suite["dependencies"]} - declared:
                errors.append(f"{prefix}: required suite dependencies are not declared")
            if declared & forbidden_dependencies:
                errors.append(f"{prefix}: server dependencies are forbidden in the Mac client scope")
        tests = step.get("tests")
        if not string_list(tests):
            errors.append(f"{prefix}: explicit nonempty test selections are required")
            tests = []
        for test in tests:
            if not repository_path(root, test) or not test.startswith("scripts/macos/"):
                errors.append(f"{prefix}: selected tests must remain beneath scripts/macos")
                continue
            if owners(manifest, test) != [suite_id]:
                errors.append(f"{prefix}: selected test must have exactly one matching owner")
            if not (root / test).is_file():
                errors.append(f"{prefix}: selected test does not exist")
            if test in selected_tests:
                errors.append(f"{prefix}: test selection is duplicated")
            selected_tests.add(test)
        artifacts = step.get("artifacts")
        if not string_list(artifacts):
            errors.append(f"{prefix}: explicit evidence artifact paths are required")
        else:
            for artifact in artifacts:
                if (
                    not repository_path(root, artifact)
                    or not artifact.startswith("build/validation/macos/")
                    or any(character in artifact for character in "*?[]")
                ):
                    errors.append(f"{prefix}: evidence requires a concrete Mac validation path")
                if artifact in selected_artifacts:
                    errors.append(f"{prefix}: evidence path is duplicated")
                selected_artifacts.add(artifact)
        command = step.get("command")
        if not isinstance(command, str) or not command.strip():
            errors.append(f"{prefix}: explicit validation command is required")
            continue
        if any(character in command for character in ";&|<>$`\n\r"):
            errors.append(f"{prefix}: shell operators and substitutions are forbidden")
            continue
        try:
            arguments = shlex.split(command)
        except ValueError:
            errors.append(f"{prefix}: validation command is malformed")
            continue
        if len(arguments) < 2 or arguments[0] != "python3":
            errors.append(f"{prefix}: command must use the approved Python Mac entry point")
        elif suite_id == "macos-tooling":
            if (
                arguments[1] not in tests
                or len(arguments) != 4
                or arguments[2] != "--report"
                or arguments[3] not in artifacts
            ):
                errors.append(f"{prefix}: tooling command requires a selected test and planned --report only")
        elif suite_id == "macos-admission":
            expected_tests = {"scripts/macos/admission.py", "scripts/macos/admission_probe.gd"}
            remaining = arguments[2:]
            if arguments[1] != "scripts/macos/admission.py" or set(tests) != expected_tests:
                errors.append(f"{prefix}: admission requires its exact client coordinator and probe")
            flags = {"--godot", "--version", "--plan", "--report"}
            if len(remaining) != 8 or any(
                flag not in flags or not value or value.startswith("--")
                for flag, value in zip(remaining[::2], remaining[1::2])
            ):
                errors.append(f"{prefix}: admission requires only its four planned value flags")
                continue
            values = dict(zip(remaining[::2], remaining[1::2]))
            if set(values) != flags:
                errors.append(f"{prefix}: admission flags must be complete and unique")
                continue
            if (not repository_path(root, values["--godot"])
                or not values["--godot"].startswith("build/tools/godot/")):
                errors.append(f"{prefix}: admission engine must be repository-local")
            if values["--version"] != "0.12.0":
                errors.append(f"{prefix}: admission must match the observed Mac package version")
            if (not repository_path(root, values["--plan"])
                or not values["--plan"].startswith(".scratch/macos-client/")):
                errors.append(f"{prefix}: admission requires an owned Mac plan")
            if artifacts != [values["--report"]]:
                errors.append(f"{prefix}: admission requires its single exact planned report")
        elif arguments[1] != "scripts/macos/package.py" or "--verify" not in arguments:
            errors.append(f"{prefix}: client command must use the Mac package verifier")
        else:
            value_flags = {"--godot", "--template", "--version", "--output", "--report"}
            values: dict[str, str] = {}
            remaining = arguments[2:]
            if remaining.count("--verify") != 1:
                errors.append(f"{prefix}: client command requires one --verify flag")
            remaining = [item for item in remaining if item != "--verify"]
            if len(remaining) != 10 or any(
                flag not in value_flags or not value or value.startswith("--")
                for flag, value in zip(remaining[::2], remaining[1::2])
            ):
                errors.append(f"{prefix}: client command requires only its five planned value flags")
                continue
            for flag, value in zip(remaining[::2], remaining[1::2]):
                if flag in values:
                    errors.append(f"{prefix}: client command flags must not be duplicated")
                values[flag] = value
            if set(values) != value_flags:
                errors.append(f"{prefix}: client command is missing a required value flag")
                continue
            for flag in ("--godot", "--template"):
                if not repository_path(root, values[flag]) or not values[flag].startswith("build/tools/godot/"):
                    errors.append(f"{prefix}: client tools must use explicit repository-local Godot paths")
            if not repository_path(root, values["--output"]) or not values["--output"].startswith("dist/macos/"):
                errors.append(f"{prefix}: package output must remain beneath dist/macos")
            if values["--report"] not in artifacts:
                errors.append(f"{prefix}: client --report must match a planned evidence path")
            if not re.fullmatch(r"\d+\.\d+\.\d+", values["--version"]):
                errors.append(f"{prefix}: client version must be a numeric three-part version")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    actual_platform = platform.system()
    actual_host = socket.gethostname()
    fingerprints: dict[str, str] = {}
    try:
        manifest_bytes = MANIFEST.read_bytes()
        plan_bytes = args.plan.read_bytes()
        fingerprints = {
            "ownership_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
            "plan_sha256": hashlib.sha256(plan_bytes).hexdigest(),
            "preflight_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        }
        errors = validate_plan(
            ROOT,
            json.loads(manifest_bytes),
            json.loads(plan_bytes),
            actual_platform,
            actual_host,
        )
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        errors = [f"invalid preflight input ({type(error).__name__})"]
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / "build/validation/macos").resolve()):
        errors.append("report must remain beneath build/validation/macos")
    report = {
        "schema_version": 1,
        "check": "macos-component-plan-preflight",
        "issue": 1353,
        "passed": not errors,
        "errors": errors,
        "platform": actual_platform,
        "host": actual_host,
        "observed_at_utc": datetime.now(timezone.utc).isoformat(),
        **fingerprints,
        "runtime_executed": False,
        "runtime_acceptance": "not evaluated",
        "paired_acceptance": False,
        "limitations": [
            "Static selections and declared dependencies only; no runtime or package is executed.",
            "Mac component scope only; Linux, Windows and paired acceptance remain separate gates.",
        ],
    }
    try:
        if output.is_relative_to((ROOT / "build/validation/macos").resolve()):
            output.parent.mkdir(parents=True, exist_ok=True)
            with output.open("x", encoding="utf-8") as handle:
                handle.write(json.dumps(report, indent=2) + "\n")
    except OSError:
        report["passed"] = False
        report["errors"].append("could not create a new evidence report; existing evidence is never overwritten")
    print(json.dumps(report, indent=2))
    return int(not report["passed"])


if __name__ == "__main__":
    sys.exit(main())
