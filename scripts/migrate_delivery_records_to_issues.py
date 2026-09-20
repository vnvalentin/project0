#!/usr/bin/env python3
"""One-time migration: back Features and Slices with GitHub issues.

Reads docs/FEATURE-LIST.md and docs/slices/*.md (left untouched as the frozen
historical archive) and:
  1. Creates one "Feature" issue per F-<n>, with "Parent goal: #N" when the
     feature's Related work already names one of the existing Goal issues.
  2. Adds the "Slice" label to each slice's existing GitHub issue (every slice
     doc already has a `GitHub issue: #N` line) and appends "Parent feature:
     #N" to that issue's body when the slice names a Feature.

Run with --dry-run (default) first; only --apply performs GitHub mutations.
State is recorded in scripts/.migration-state.json so reruns are idempotent.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FEATURE_LIST = REPO_ROOT / "docs" / "FEATURE-LIST.md"
SLICES_DIR = REPO_ROOT / "docs" / "slices"
STATE_FILE = Path(__file__).resolve().parent / ".migration-state.json"
REPO = "vnvalentin/project0"
ISSUE_URL_RE = re.compile(r"github\.com/vnvalentin/project0/issues/(\d+)")


def gh_json(args: list[str]):
    out = subprocess.run(
        ["gh", *args], cwd=REPO_ROOT, capture_output=True, text=True,
        encoding="utf-8", errors="replace", check=True,
    )
    return json.loads(out.stdout)


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    return {"feature_issue": {}}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def goal_issue_numbers() -> set[str]:
    issues = gh_json(["issue", "list", "--label", "Goal", "--state", "all", "--limit", "100", "--json", "number"])
    return {str(item["number"]) for item in issues}


def parse_features() -> list[dict]:
    text = FEATURE_LIST.read_text(encoding="utf-8")
    sections = re.split(r"(?m)^### (F-\d+): (.+)$", text)
    # sections[0] is preamble; then repeating (id, title, body) triples
    features = []
    for i in range(1, len(sections), 3):
        fid, title, body = sections[i], sections[i + 1], sections[i + 2]
        status_match = re.search(r"- Status: `([^`]+)`", body)
        related_match = re.search(r"(?m)^- Related work:.*(?:\n(?!- ).*)*", body)
        related_text = related_match.group(0) if related_match else ""
        issue_refs = ISSUE_URL_RE.findall(related_text) or ISSUE_URL_RE.findall(body)
        features.append({
            "id": fid,
            "title": title.strip(),
            "status": status_match.group(1) if status_match else "unknown",
            "issue_refs": issue_refs,
            "anchor": fid.lower(),
        })
    return features


def parse_slices() -> list[dict]:
    slices = []
    for path in sorted(SLICES_DIR.glob("*.md")):
        if path.name == "SLICE-REGISTRY.md":
            continue
        text = path.read_text(encoding="utf-8")
        issue_match = re.search(r"(?m)^GitHub issue: #(\d+)", text)
        feature_match = re.search(r"(?m)^Feature: \[(F-\d+)\]", text)
        if not issue_match:
            continue
        slices.append({
            "file": path.name,
            "issue": issue_match.group(1),
            "feature": feature_match.group(1) if feature_match else None,
        })
    return slices


def plan(features: list[dict], slices: list[dict], goal_issues: set[str], state: dict):
    feature_actions = []
    for feature in features:
        if feature["id"] in state["feature_issue"]:
            continue
        parent_goal = next((ref for ref in feature["issue_refs"] if ref in goal_issues), None)
        feature_actions.append({**feature, "parent_goal": parent_goal})

    slice_actions = []
    for s in slices:
        slice_actions.append(s)

    return feature_actions, slice_actions


def feature_issue_body(feature: dict) -> str:
    lines = [
        f"Tracks {feature['id']}: {feature['title']}.",
        "",
        f"Full record: [docs/FEATURE-LIST.md#{feature['anchor']}]"
        f"(https://github.com/{REPO}/blob/main/docs/FEATURE-LIST.md#{feature['anchor']})",
        f"Status (at migration time): {feature['status']}",
    ]
    if feature["parent_goal"]:
        lines += ["", f"Parent goal: #{feature['parent_goal']}"]
    return "\n".join(lines)


def run(args):
    state = load_state()
    goal_issues = goal_issue_numbers()
    features = parse_features()
    slices = parse_slices()
    feature_actions, slice_actions = plan(features, slices, goal_issues, state)

    print(f"Features to create: {len(feature_actions)} (already done: {len(state['feature_issue'])})")
    for f in feature_actions:
        print(f"  CREATE issue  [Feature] {f['id']}: {f['title']}  parent_goal={f['parent_goal']}")

    slice_by_feature = {}
    for s in slices:
        slice_by_feature.setdefault(s["feature"], []).append(s["issue"])
    no_feature = slice_by_feature.get(None, [])
    print(f"\nSlices total: {len(slices)}; with known Feature: {len(slices) - len(no_feature)}; legacy (no Feature link): {len(no_feature)}")

    if not args.apply:
        print("\nDry run only. Re-run with --apply to create/edit issues.")
        return

    for f in feature_actions:
        body = feature_issue_body(f)
        out = subprocess.run(
            ["gh", "issue", "create", "--repo", REPO, "--title", f"Feature: {f['id']} {f['title']}",
             "--body", body, "--label", "Feature"],
            cwd=REPO_ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        if out.returncode != 0:
            print(f"FAILED creating {f['id']}: {out.stderr.strip()}")
            continue
        url = out.stdout.strip()
        number = url.rsplit("/", 1)[-1]
        state["feature_issue"][f["id"]] = number
        save_state(state)
        print(f"Created {f['id']} -> #{number}")

    for s in slice_actions:
        try:
            current = gh_json(["issue", "view", s["issue"], "--repo", REPO, "--json", "body,labels"])
        except subprocess.CalledProcessError as error:
            print(f"Slice issue #{s['issue']} ({s['file']}): FAILED to fetch: {error.stderr.strip() if error.stderr else error}")
            continue
        labels = {l["name"] for l in current["labels"]}
        body = current["body"] or ""
        needs_label = "Slice" not in labels
        feature_issue = state["feature_issue"].get(s["feature"]) if s["feature"] else None
        needs_parent = feature_issue and f"Parent feature: #{feature_issue}" not in body
        if not needs_label and not needs_parent:
            continue
        new_body = body
        if needs_parent:
            new_body = (body.rstrip() + f"\n\nParent feature: #{feature_issue}\n") if body.strip() else f"Parent feature: #{feature_issue}\n"
        cmd = ["gh", "issue", "edit", s["issue"], "--repo", REPO]
        if needs_label:
            cmd += ["--add-label", "Slice"]
        if needs_parent:
            cmd += ["--body", new_body]
        out = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        status = "ok" if out.returncode == 0 else f"FAILED: {out.stderr.strip()}"
        print(f"Slice issue #{s['issue']} ({s['file']}): label={needs_label} parent={needs_parent} -> {status}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Perform GitHub mutations (default is dry-run)")
    run(parser.parse_args())
