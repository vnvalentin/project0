import argparse
from fnmatch import fnmatchcase
import json
from pathlib import Path
import re


MANIFEST = Path(__file__).with_name("validation_ownership.json")
TOKENS = re.compile(r'''\#[^\n]*|(?P<string>"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|(?P<name>[A-Za-z_][A-Za-z_0-9]*)''')
RESOURCE_PROBE = re.compile(r'''\bResourceLoader\s*\.\s*exists\s*\(\s*["']res://[^"']+["']\s*\)''')


def string_list(value: object) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) and item.strip() for item in value)


def repository_path(root: Path, value: str) -> bool:
    path = Path(value)
    return not path.is_absolute() and ".." not in path.parts and "\\" not in value and (root / path).resolve().is_relative_to(root.resolve())


def owners(manifest: dict, name: str) -> list[str]:
    return [suite_id for suite_id, suite in manifest["suites"].items()
            if any(len(name.split("/")) == len(pattern.split("/")) and
                   all(fnmatchcase(part, expected) for part, expected in zip(name.split("/"), pattern.split("/")))
                   for pattern in suite["tests"])]


def check_plan(root: Path, manifest: dict, plan: dict) -> list[str]:
    errors: list[str] = []
    if not isinstance(plan, dict):
        return ["plan must be an object"]
    if plan.get("schema_version") != 1:
        errors.append("plan schema_version must be 1")
    if plan.get("kind") not in ("component", "paired-runtime"):
        errors.append("plan kind must be component or paired-runtime")
    steps = plan.get("steps")
    if not isinstance(steps, list) or not steps:
        return errors + ["plan requires nonempty steps"]
    selected_owners: set[str] = set()
    for index, step in enumerate(steps):
        prefix = f"step {index + 1}"
        if not isinstance(step, dict) or not isinstance(step.get("suite"), str):
            errors.append(f"{prefix}: suite object is required")
            continue
        suite = manifest["suites"].get(step["suite"])
        if suite is None:
            errors.append(f"{prefix}: unknown suite")
            continue
        selected_owners.add(suite["owner"])
        if step.get("platform") != suite["platform"]:
            errors.append(f"{prefix}: {step['suite']} requires {suite['platform']}")
        if not isinstance(step.get("host"), str) or not step["host"].strip():
            errors.append(f"{prefix}: execution host is required")
        if not isinstance(step.get("command"), str) or not step["command"].strip():
            errors.append(f"{prefix}: explicit validation command is required")
        allowed_hosts = manifest["hosts"][suite["platform"]]
        if step.get("host") not in allowed_hosts:
            errors.append(f"{prefix}: {suite['platform']} execution requires an assigned host: {allowed_hosts}")
        dependencies = step.get("dependencies")
        if not string_list(dependencies):
            errors.append(f"{prefix}: explicit nonempty dependencies are required")
        else:
            declared = {item.lower() for item in dependencies}
            missing = set(suite["dependencies"]) - declared
            if missing:
                errors.append(f"{prefix}: missing declared dependencies: {sorted(missing)}")
            if step.get("platform") == "windows" and declared & set(manifest["server_dependencies"]):
                errors.append(f"{prefix}: server dependencies belong on Linux, not Windows; correct test placement before installing dependencies")
        if not string_list(step.get("artifacts")):
            errors.append(f"{prefix}: expected evidence artifact paths are required")
        tests = step.get("tests")
        if not string_list(tests):
            errors.append(f"{prefix}: explicitly selected tests are required")
            continue
        for test in tests:
            if not repository_path(root, test):
                errors.append(f"{prefix}: test must be repository-relative: {test}")
                continue
            if owners(manifest, test) != [step["suite"]]:
                errors.append(f"{prefix}: {test} must have exactly one owner matching {step['suite']}")
            if not (root / test).is_file():
                errors.append(f"{prefix}: test does not exist: {test}")
    if plan.get("kind") == "paired-runtime":
        if not {"linux-server", "windows-client"}.issubset(selected_owners):
            errors.append("paired-runtime requires linux-server and windows-client steps; launcher/headless evidence is not a substitute")
        for field in ("scenario_id", "client_build", "server_build", "correlation_id", "setup", "cleanup"):
            if not isinstance(plan.get(field), str) or not plan[field].strip():
                errors.append(f"paired-runtime requires {field}")
    return errors


def check_inventory(root: Path, manifest: dict) -> tuple[list[str], dict[str, int]]:
    errors: list[str] = []
    counts = dict.fromkeys(manifest["suites"], 0)
    for directory in manifest["test_roots"]:
        for path in sorted((root / directory).rglob("*")):
            if not path.is_file() or not (path.name.endswith("_test.go") or (path.name.startswith("test_") and path.suffix in (".py", ".sh", ".ps1", ".gd"))):
                continue
            name = path.relative_to(root).as_posix()
            matches = owners(manifest, name)
            if len(matches) != 1:
                errors.append(f"unowned or conflicting test: {name}: {matches}")
            else:
                counts[matches[0]] += 1
    if not sum(counts.values()):
        errors.append("no owned tests found")
    return errors, counts


def source_tokens(path: Path) -> tuple[list[str], list[str]]:
    source = path.read_text(encoding="utf-8")
    source = RESOURCE_PROBE.sub("", source)
    names: list[str] = []
    resources: list[str] = []
    for token in TOKENS.finditer(source):
        if token.group("name"):
            names.append(token.group("name"))
        elif token.group("string"):
            value = token.group("string").strip("\"'")
            if value.startswith("res://"):
                resources.append(value[6:])
    return names, resources


def check_client_dependencies(root: Path, manifest: dict) -> tuple[list[str], int]:
    errors: list[str] = []
    classes: dict[str, str] = {}
    for directory in ("shared", "server", "client"):
        for path in sorted((root / directory).rglob("*.gd")):
            names, _ = source_tokens(path)
            for index, name in enumerate(names[:-1]):
                if name == "class_name":
                    classes[names[index + 1]] = path.relative_to(root).as_posix()
    pending = [(path.relative_to(root).as_posix(), "client root")
               for path in sorted((root / "client").rglob("*"))
               if path.is_file() and path.suffix in (".gd", ".tscn", ".tres")]
    if not pending:
        return ["no client source roots found"], 0
    visited: set[str] = set()
    while pending:
        name, parent = pending.pop()
        if not repository_path(root, name):
            errors.append(f"{parent}: invalid resource path {name}")
            continue
        name = (root / name).resolve().relative_to(root.resolve()).as_posix()
        if name in visited:
            continue
        visited.add(name)
        if name.startswith("addons/godot-sqlite/") or (name.startswith("server/") and name not in manifest["server_data_exceptions"]):
            errors.append(f"{parent} -> {name}: server dependency reachable from client")
            continue
        path = root / name
        if path.suffix not in (".gd", ".tscn", ".tres"):
            continue
        if not path.is_file():
            errors.append(f"{parent}: missing static dependency {name}")
            continue
        names, resources = source_tokens(path)
        if "SQLite" in names:
            errors.append(f"{name}: SQLite belongs exclusively to the Linux server")
        for symbol in set(names) & classes.keys():
            dependency = classes[symbol]
            if dependency.startswith("server/") and dependency not in manifest["server_data_exceptions"]:
                errors.append(f"{name}: server type {symbol} ({dependency}) reachable from client")
            else:
                pending.append((dependency, name))
        pending.extend((resource, name) for resource in resources)
    return sorted(set(errors)), len(visited)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate test execution ownership; never execute a runner.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    counts: dict[str, int] = {}
    source_count = 0
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if args.plan:
            plan = json.loads(args.plan.read_text(encoding="utf-8"))
            errors = check_plan(args.root, manifest, plan)
        else:
            errors, counts = check_inventory(args.root, manifest)
            source_errors, source_count = check_client_dependencies(args.root, manifest)
            errors.extend(source_errors)
    except (OSError, ValueError, TypeError, KeyError) as error:
        errors = [f"invalid ownership input: {error}"]
    report = {
        "schema_version": 1,
        "passed": not errors,
        "errors": errors,
        "tests_by_suite": counts,
        "client_dependencies_checked": source_count,
        "runtime_executed": False,
        "runtime_acceptance": "not evaluated",
        "limitations": ["Static resource/type references only; dynamic loading and exported package contents require native client validation.",
                        "A valid plan describes intended execution; it is not evidence that any test ran."],
    }
    output = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    print(output, end="")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())