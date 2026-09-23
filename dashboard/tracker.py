import html
import json
import re
import sys
from pathlib import Path


SCHEMA_PATH = Path(__file__).with_name("tracker_schema.json")


def _sectionize(markdown: str) -> list[dict]:
    sections = []
    current = {"title": "Project0 Tracker", "level": 1, "body": []}
    for line in markdown.splitlines():
        match = re.match(r"^(#{1,3})\s+(.+?)\s*$", line)
        if match:
            if current["body"] or current["title"] != "Project0 Tracker":
                current["text"] = "\n".join(current.pop("body"))
                sections.append(current)
            current = {"title": match.group(2), "level": len(match.group(1)), "body": []}
        else:
            current["body"].append(line)
    if current["body"] or current["title"] != "Project0 Tracker":
        current["text"] = "\n".join(current.pop("body"))
        sections.append(current)
    return sections


def _phase_rows(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        match = re.match(r"^\|\s*(\d+)\.\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|$", line)
        if match:
            rows.append({
                "number": int(match.group(1)),
                "name": match.group(2).strip(),
                "status": match.group(3).strip(),
                "gate": match.group(4).strip(),
            })
    return rows


def _queue_items(text: str) -> list[dict]:
    items = []
    for line in text.splitlines():
        match = re.match(r"^\s*-\s*\[([ xX])\]\s+(.+?)\s*$", line)
        if match:
            items.append({"done": match.group(1).lower() == "x", "text": match.group(2)})
    return items


def _delivery_fields(text: str) -> dict:
    parallel_tracks = []
    dependencies = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("**Runs in parallel throughout"):
            parallel_tracks.append(stripped.strip("*: "))
        elif stripped.startswith("**Must sequence"):
            continue
        elif stripped.startswith("-") and dependencies:
            dependencies.append(stripped[1:].strip())
        elif stripped.startswith("-") and "dependencies" in text[:text.find(line)].lower():
            dependencies.append(stripped[1:].strip())
    marker = text.lower().find("**must sequence")
    if marker >= 0:
        dependency_text = text[marker:]
        dependencies = [line.strip()[1:].strip() for line in dependency_text.splitlines() if line.strip().startswith("-")]
    return {
        "order": [line.strip() for line in text.splitlines() if re.match(r"^\d+\.\s+", line)],
        "parallel_tracks": parallel_tracks,
        "dependencies": dependencies,
        "text": text,
    }


def _load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def load_tracker(repo: Path) -> dict:
    try:
        schema = _load_schema()
    except (OSError, json.JSONDecodeError) as exc:
        return {"available": False, "error": str(exc), "sections": [], "phases": [], "queue": []}
    archive = schema.get("archive", "")
    path = (repo / archive).resolve()
    try:
        if repo.resolve() not in path.parents:
            raise OSError("tracker path is outside the repository")
        markdown = path.read_text(encoding="utf-8")
    except OSError as exc:
        return {"available": False, "error": str(exc), "sections": [], "phases": [], "queue": []}

    sections = _sectionize(markdown)
    section_map = {section["title"]: section for section in sections}
    warnings = [
        f"missing required section: {title}"
        for title in schema.get("required_sections", [])
        if title not in section_map
    ]
    phase_section = next((section for section in sections if section["title"] == "Phases"), None)
    acceptance_section = section_map.get("Implementation slice acceptance")
    delivery_section = section_map.get("Delivery order and parallelization")
    queue_section = next((section for section in sections if section["title"] == "Work queue"), None)
    acceptance = _queue_items(acceptance_section["text"] if acceptance_section else "")
    queue = _queue_items(queue_section["text"] if queue_section else "")
    phases = _phase_rows(phase_section["text"] if phase_section else "")
    if not phases:
        warnings.append("phase table has no data rows")
    if not acceptance:
        warnings.append("implementation acceptance checklist has no items")
    if not queue:
        warnings.append("work queue has no items")
    return {
        "available": True,
        "error": "",
        "schema": schema,
        "source": archive,
        "sections": sections,
        "phases": phases,
        "acceptance": acceptance,
        "delivery": _delivery_fields(delivery_section["text"] if delivery_section else ""),
        "queue": queue,
        "queue_done": sum(1 for item in queue if item["done"]),
        "queue_open": sum(1 for item in queue if not item["done"]),
        "warnings": warnings,
        "source_health": {"available": True, "warnings": warnings},
    }


def inline_markdown(text: str) -> str:
    escaped = html.escape(text, quote=True)
    return re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda match: f'<a href="{html.escape(match.group(2), quote=True)}">{match.group(1)}</a>',
        escaped,
    )


def validate_tracker(repo: Path) -> list[str]:
    errors = []
    try:
        schema = _load_schema()
    except (OSError, json.JSONDecodeError) as exc:
        return [f"invalid tracker schema: {exc}"]
    if schema.get("schema_version") != 1:
        errors.append("unsupported tracker schema version")
    model = load_tracker(repo)
    if not model["available"]:
        return [f"tracker source unavailable: {model['error']}"]
    errors.extend(model["warnings"])
    for name, required_fields in schema.get("fields", {}).items():
        value = model.get(name)
        records = value if isinstance(value, list) else [value]
        if value is None:
            errors.append(f"schema field group is not projected: {name}")
            continue
        for field in required_fields:
            if any(not isinstance(record, dict) or field not in record for record in records):
                errors.append(f"schema field is not projected: {name}.{field}")
    return errors


if __name__ == "__main__":
    if "--validate" not in sys.argv:
        raise SystemExit("usage: python dashboard/tracker.py --validate [repo]")
    root = Path(sys.argv[sys.argv.index("--validate") + 1]) if len(sys.argv) > sys.argv.index("--validate") + 1 else Path.cwd()
    failures = validate_tracker(root)
    for failure in failures:
        print(f"FAIL  {failure}", file=sys.stderr)
    raise SystemExit(1 if failures else 0)