#!/usr/bin/env python3
import html
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

REPO = Path(os.environ.get("PROJECT_ROOT", "/repo"))
PORT = int(os.environ.get("PORT", "8080"))
GITHUB_REPO = os.environ.get("GITHUB_REPO", "vnvalentin/project0")
GITHUB_ISSUE_CACHE_SECONDS = int(os.environ.get("GITHUB_ISSUE_CACHE_SECONDS", "300"))
SELF_PATH = Path(__file__).resolve()
try:
    _SELF_MTIME = SELF_PATH.stat().st_mtime
except OSError:
    _SELF_MTIME = None
_ISSUE_CACHE = {"at": 0.0, "data": {"available": False, "issues": [], "error": "not loaded"}}


def restart_if_source_changed() -> None:
    # app.py is bind-mounted read-only; re-exec so edits apply without a container rebuild.
    try:
        if SELF_PATH.stat().st_mtime != _SELF_MTIME:
            os.execv(sys.executable, [sys.executable, str(SELF_PATH)])
    except OSError:
        pass


def read_repo_file(name: str) -> str:
    path = (REPO / name).resolve()
    if REPO.resolve() not in path.parents:
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


RECORD_FILES = (
    "docs/FEATURE-LIST.md",
    "docs/PROJECT-TRACKER.md",
    "docs/TECHNICAL-DEBT-TRACKER.md",
    "docs/slices/SLICE-REGISTRY.md",
)


def _git(args: list[str]) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            ["git", "-C", str(REPO), "-c", "safe.directory=*", *args],
            capture_output=True, text=True, timeout=5,
            env={**os.environ, "GIT_OPTIONAL_LOCKS": "0", "HOME": "/tmp"},
        )
        return proc.returncode, proc.stdout
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def github_issues() -> dict:
    now = time.time()
    if now - float(_ISSUE_CACHE["at"]) < GITHUB_ISSUE_CACHE_SECONDS:
        return _ISSUE_CACHE["data"]
    try:
        issues = []
        for page in range(1, 6):
            url = f"https://api.github.com/repos/{GITHUB_REPO}/issues?state=all&per_page=100&page={page}"
            req = Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "project0-flow-dashboard"})
            with urlopen(req, timeout=5) as response:
                raw = response.read().decode("utf-8")
            parsed = json.loads(raw)
            for item in parsed:
                if "pull_request" in item:
                    continue
                issues.append({
                    "number": int(item.get("number", 0)),
                    "title": str(item.get("title", "")),
                    "url": str(item.get("html_url", "")),
                    "state": str(item.get("state", "open")),
                    "labels": [str(label.get("name", "")) for label in item.get("labels", []) if label.get("name")],
                    "body": str(item.get("body", "")),
                })
            if len(parsed) < 100:
                break
        issues.sort(key=lambda issue: issue["number"])
        data = {"available": True, "repo": GITHUB_REPO, "issues": issues, "error": ""}
    except Exception as exc:
        data = {"available": False, "repo": GITHUB_REPO, "issues": [], "error": str(exc)}
    _ISSUE_CACHE.update({"at": now, "data": data})
    return data


def read_committed_file(name: str) -> str:
    # Render last-committed truth, not the live half-merged working tree.
    path = (REPO / name).resolve()
    if REPO.resolve() not in path.parents:
        return ""
    rc, out = _git(["show", f"HEAD:{name}"])
    return out if rc == 0 else read_repo_file(name)


def calibration() -> dict:
    rc, out = _git(["log", "-1", "--format=%h\t%s"])
    sha, subject = "", ""
    if rc == 0 and "\t" in out:
        sha, subject = out.strip().split("\t", 1)
    _, diff = _git(["diff", "--name-only", "HEAD", "--", *RECORD_FILES])
    dirty = [line.strip() for line in diff.splitlines() if line.strip()]
    _, others = _git(["ls-files", "--others", "--exclude-standard"])
    _, tracked = _git(["diff", "--name-only", "HEAD"])
    in_flight = sum(1 for line in others.splitlines() if line.strip())
    in_flight += sum(1 for line in tracked.splitlines() if line.strip())
    return {"sha": sha, "subject": subject, "dirty_records": dirty,
            "in_flight": in_flight, "available": bool(sha)}


def list_repo_dir(rel: str) -> list[str]:
    base = (REPO / rel).resolve()
    root = REPO.resolve()
    if base != root and root not in base.parents:
        return []
    try:
        return sorted(child.name for child in base.iterdir())
    except OSError:
        return []


def map_title(text: str, fallback: str) -> str:
    match = re.search(r"^#\s+(.+)$", text, re.M)
    if match:
        return re.sub(r"^Map:\s*", "", match.group(1).strip())
    return fallback.replace("-", " ").replace("_", " ").title()


def map_destination(text: str) -> str:
    match = re.search(r"^##\s+Destination\s*\n+([\s\S]*?)(?=\n##\s|\Z)", text, re.M)
    if not match:
        return ""
    paragraph = match.group(1).strip().split("\n\n", 1)[0]
    return " ".join(paragraph.split())


def issue_titles_from_map(text: str) -> dict[str, str]:
    lookup = {}
    for match in re.finditer(r"\[([^\]]+)\]\([^)]*issues/([^)/]+?)\.md\)", text):
        title = re.sub(r"^\d+\s*[—-]\s*", "", match.group(1).strip())
        lookup[match.group(2)] = title
    return lookup


def slug_title(stem: str) -> str:
    text = re.sub(r"^\d+[-_]", "", stem).replace("-", " ").replace("_", " ").strip()
    return text[:1].upper() + text[1:] if text else stem


def issue_field(text: str, field: str) -> str:
    match = re.search(rf"^{field}:\s*(.+)$", text, re.M)
    return match.group(1).strip() if match else ""


def issue_state(status: str) -> str:
    normalized = status.lower().strip()
    if normalized.startswith("unclaimed"):
        return "todo"
    if normalized.startswith(("resolved", "done", "closed", "accepted")):
        return "decided"
    if normalized.startswith(("claimed", "in progress", "in-progress", "working")):
        return "active"
    return "todo"


def github_issue_by_source(issue_feed: dict) -> dict[str, dict]:
    lookup = {}
    for issue in issue_feed.get("issues", []):
        match = re.search(r"^Source:\s*(.+)$", issue.get("body", ""), re.M)
        if match:
            lookup[match.group(1).strip()] = issue
    return lookup


def goal_maps(issue_feed: dict | None = None) -> list[dict]:
    issue_lookup = github_issue_by_source(issue_feed or github_issues())
    goals = []
    for name in list_repo_dir(".scratch"):
        map_text = read_repo_file(f".scratch/{name}/map.md")
        map_missing = not bool(map_text)
        title_lookup = issue_titles_from_map(map_text)
        issues = []
        for issue_name in list_repo_dir(f".scratch/{name}/issues"):
            if not issue_name.endswith(".md"):
                continue
            text = read_repo_file(f".scratch/{name}/issues/{issue_name}")
            stem = issue_name[:-3]
            status = issue_field(text, "Status") or "unclaimed"
            number = re.match(r"^(\d+)", stem)
            source = f".scratch/{name}/issues/{issue_name}"
            github_issue = issue_lookup.get(source, {})
            issues.append({
                "id": number.group(1) if number else "",
                "title": title_lookup.get(stem) or slug_title(stem),
                "status": status,
                "type": issue_field(text, "Type"),
                "state": issue_state(status),
                "source": source,
                "github_number": github_issue.get("number"),
                "github_url": github_issue.get("url", ""),
            })
        decided = sum(1 for issue in issues if issue["state"] == "decided")
        total = len(issues)
        goal_source = f".scratch/{name}/map.md" if not map_missing else f".scratch/{name}/ (missing map.md)"
        github_goal = issue_lookup.get(goal_source, {})
        goals.append({
            "name": name,
            "title": map_title(map_text, name),
            "destination": map_destination(map_text) if not map_missing else "New goal that has not been researched yet; map.md is not present.",
            "issues": issues,
            "decided": decided,
            "total": total,
            "percent": round(decided / total * 100) if total else 0,
            "map_missing": map_missing,
            "source": goal_source,
            "github_number": github_goal.get("number"),
            "github_url": github_goal.get("url", ""),
        })
    return goals


def slice_issue_stats() -> dict:
    total, missing = 0, []
    for name in list_repo_dir("docs/slices"):
        if not re.match(r"^\d{3}-.+\.md$", name):
            continue
        total += 1
        text = read_repo_file(f"docs/slices/{name}")
        if not re.search(r"^GitHub issue:\s*(#[0-9]+|https://github\.com/[^/]+/[^/]+/issues/[0-9]+)", text, re.M | re.I):
            missing.append(name)
    return {"total": total, "missing": missing, "linked": total - len(missing)}


def traceability_model(goals: list[dict], issue_feed: dict) -> dict:
    child_total = sum(g["total"] for g in goals)
    child_linked = sum(1 for g in goals for i in g["issues"] if i.get("github_number"))
    goal_linked = sum(1 for g in goals if g.get("github_number"))
    goal_labels = sum(1 for issue in issue_feed.get("issues", []) if issue["title"].startswith("Goal:") and "Goal" in issue.get("labels", []))
    return {
        "goals": len(goals),
        "goal_linked": goal_linked,
        "goal_labels": goal_labels,
        "child_total": child_total,
        "child_linked": child_linked,
        "missing_maps": [g for g in goals if g.get("map_missing")],
        "slices": slice_issue_stats(),
    }


def issue_is_complete(issue: dict) -> bool:
    if issue.get("state") == "closed":
        return True
    return bool(re.search(r"^Status:\s*(resolved|done|closed|accepted)\b", issue.get("body", ""), re.M | re.I))


def issue_covers_goal_target(issue: dict) -> bool:
    return bool(re.search(r"^Status:\s*(resolved|done|closed|accepted)\b", issue.get("body", ""), re.M | re.I))

def goal_target_coverage(goal: dict, covered_children: int, total_children: int) -> int:
    labels = goal.get("labels", [])
    body = goal.get("body", "")
    if "new" in labels or "(missing map.md)" in body:
        return 0
    if goal.get("state") == "closed":
        return 100
    if total_children == 0:
        return 0
    # Open parent goals still have fog to clear. Child issue completion shows
    # known planning progress, but it does not by itself close the goal target.
    return min(90, round(covered_children / total_children * 100))


def goal_issue_cards(issue_feed: dict) -> list[dict]:
    issues = issue_feed.get("issues", [])
    children_by_parent: dict[int, list[dict]] = {}
    for issue in issues:
        match = re.search(r"^Parent goal:\s*#(\d+)\b", issue.get("body", ""), re.M)
        if not match:
            continue
        parent = int(match.group(1))
        children_by_parent.setdefault(parent, []).append(issue)

    cards = []
    for issue in issues:
        labels = issue.get("labels", [])
        if "Goal" not in labels and not issue.get("title", "").startswith("Goal:"):
            continue
        children = children_by_parent.get(issue["number"], [])
        total = len(children)
        github_closed = sum(1 for child in children if child.get("state") == "closed")
        covered = sum(1 for child in children if issue_covers_goal_target(child))
        open_count = total - github_closed
        child_percent = round(covered / total * 100) if total else 0
        target_percent = goal_target_coverage(issue, covered, total)
        cards.append({
            **issue,
            "child_total": total,
            "child_closed": github_closed,
            "child_open": open_count,
            "target_covered": covered,
            "target_percent": target_percent,
            "child_percent": child_percent,
            "percent": target_percent,
        })
    cards.sort(key=lambda card: (-card["percent"], card["title"]))
    return cards


def feature_stage(status: str) -> str:
    normalized = status.lower().strip()
    if normalized.startswith(("implemented", "done")):
        return "Done"
    if normalized.startswith(("in progress", "active")):
        return "Active"
    if normalized.startswith("ready"):
        return "Ready"
    return "Planned"


def feature_cards(reader=read_committed_file) -> list[dict]:
    text = reader("docs/FEATURE-LIST.md")
    cards, seen_ids = [], set()
    for match in re.finditer(r"^### ((?:IP|P|F)-\d+):\s*(.+?)[ \t]*$\n([\s\S]*?)(?=^### |\Z)", text, re.M):
        fid, title, body = match.group(1), match.group(2).strip(), match.group(3)
        if fid in seen_ids:  # Count repeated feature headings once.
            continue
        seen_ids.add(fid)
        status_match = re.search(r"^- Status:\s*`?([^`\n]+?)`?\s*$", body, re.M)
        status = status_match.group(1).strip() if status_match else "Planned"
        tags, seen = [], set()
        for ref in re.finditer(r"\.scratch/([^/)]+)/issues/(\d+)", body):
            tag = f'{ref.group(1)} #{ref.group(2)}'
            if tag not in seen:
                seen.add(tag)
                tags.append(tag)
        if not tags:
            for ref in re.finditer(r"\.scratch/([^/)]+)/map\.md", body):
                if ref.group(1) not in seen:
                    seen.add(ref.group(1))
                    tags.append(ref.group(1))
        cards.append({"id": fid, "title": title, "status": status, "issue_tags": tags})
    return cards


def phase_rows(text: str) -> list[dict[str, str]]:
    rows = []
    for match in re.finditer(r"^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$", text, re.M):
        phase, status, gate = (part.strip() for part in match.groups())
        if phase == "Phase" or phase == "---":
            continue
        if re.match(r"^\d+\.", phase):
            rows.append({"phase": phase, "status": status, "gate": gate})
    return rows


def slice_cards(text: str) -> list[dict[str, str]]:
    cards = []
    pattern = r"^- \*\*(?:Current\s+)?[Ss]lice:\*\*\s*(?:\[([^]]+)\]\([^)]*\)|([^—]+))\s*—\s*\*\*([^*]+)\*\*"
    for match in re.finditer(pattern, text, re.M):
        title = (match.group(1) or match.group(2) or "").strip()
        cards.append({"title": title, "status": match.group(3).strip()})
    return cards


def queue_items(text: str) -> list[dict[str, str]]:
    cards = []
    section_match = re.search(r"^## Work queue\n([\s\S]*?)(?=^## |\Z)", text, re.M)
    if not section_match:
        return cards
    lines = section_match.group(1).splitlines()
    item = None
    for line in lines:
        top_match = re.match(r"^- \[( |x)\]\s*(?:(Ready|Queued|In progress)\s*—\s*)?(.+)$", line)
        if top_match:
            if item:
                cards.append(item)
            checked, label, title = top_match.groups()
            item = None if checked == "x" else {"title": title.strip(), "status": label or "Queued"}
            continue
        if item and line.strip():
            item["title"] += " " + line.strip()
    if item:
        cards.append(item)
    for card in cards:
        card["title"] = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", card["title"])
        card["title"] = re.sub(r"`([^`]+)`", r"\1", card["title"])
    return cards


def debt_cards(text: str) -> list[dict[str, str]]:
    cards = []
    outstanding = text.split("## Resolved Items", 1)[0]
    for match in re.finditer(r"^###\s+(DT-\d+):\s*(.+)$([\s\S]*?)(?=^###\s+|\Z)", outstanding, re.M):
        body = match.group(3)
        status = re.search(r"^- Status:\s*`?([^`\n]+)", body, re.M)
        cards.append({"id": match.group(1), "title": match.group(2).strip(), "status": status.group(1).strip() if status else "Unstated"})
    return cards


def action_items(phases: list[dict[str, str]], debts: list[dict[str, str]], slices: list[dict[str, str]]) -> list[str]:
    actions = []
    for debt in debts:
        if debt["status"].lower() not in {"resolved", "closed", "accepted"}:
            actions.append(f"Andon: {debt['id']} {debt['title']}")
    for phase in phases:
        if phase["status"].lower() == "blocked":
            actions.append(f"Blocked Phase: {phase['phase']}")
    for card in slices:
        status = card["status"].lower()
        if "100%" in status and "outstanding" not in status:
            continue
        if "outstanding" in status or "awaiting" in status:
            actions.append(f"Evidence needed: {card['title']}")
        elif "in progress" in status or "working" in status:
            actions.append(f"In progress: {card['title']}")
    return actions


def phase_progress_map(tracker: str) -> dict:
    out = {}
    for m in re.finditer(
        r"\*\*Phase (\d+)\s*[—-]\s*([^*]+?)\*\*\s+Progress:\s*\*\*(\d+)%\*\*"
        r"(?:\s*\((\d+) of (\d+) items done\))?",
        tracker,
    ):
        out[int(m.group(1))] = {
            "title": m.group(2).strip(), "progress": int(m.group(3)),
            "done_items": int(m.group(4)) if m.group(4) else None,
            "total_items": int(m.group(5)) if m.group(5) else None,
        }
    return out


def _slice_done(status: str) -> bool:
    # Accept both completion labels used by the tracker.
    s = status.lower()
    if any(k in s for k in ("in progress", "in-progress", "awaiting", "outstanding", "blocked")):
        return False
    return "100% complete" in s or "delivered" in s


def current_slice_numbers(tracker: str) -> set:
    return {int(n) for n in re.findall(r"\*\*Current slice:\*\* \[(\d+)", tracker)}


def slice_index_rows(tracker: str) -> list[dict]:
    # Walk the whole tracker, tracking phase context from both the work-index
    # (**Phase N — Title**) and slice-index (#### Phase N — Title) headers, and
    # collect every Slice/Current slice entry deduped by number.
    rows: dict[int, dict] = {}
    phase_num, phase_title, last = 0, "", None
    for line in tracker.splitlines():
        h = re.match(r"^#{3,4} Phase (\d+)\s*[—-]\s*(.+)$", line) or re.match(r"^\*\*Phase (\d+)\s*[—-]\s*(.+?)\*\*", line)
        if h:
            phase_num, phase_title, last = int(h.group(1)), h.group(2).strip(), None
            continue
        s = re.match(r"^- \*\*(?:Current s|S)lice:\*\* \[(\d+)\s*[—-]\s*([^\]]+)\]\([^)]*\)(?:\s*[—-]\s*\*\*([^*]+)\*\*)?", line)
        if s:
            num, status = int(s.group(1)), (s.group(3) or "").strip()
            row = rows.get(num)
            if row is None:
                rows[num] = {"num": num, "title": s.group(2).strip(), "status_text": status,
                             "phase_num": phase_num, "phase_title": phase_title,
                             "feature": "", "done": _slice_done(status)}
            elif status and not row["status_text"]:
                row["status_text"], row["done"] = status, _slice_done(status)
            last = num
            continue
        f = re.match(r"^\s*- \*\*Features?:\*\* \[([A-Za-z]+-\d+)\]", line)
        if f and last is not None and not rows[last]["feature"]:
            rows[last]["feature"] = f.group(1)
    return list(rows.values())


def _phase_wave_rank(phase_num: int, features: set) -> int:
    pat = re.compile(rf"Phase {phase_num}\b")

    def hit(blob: str) -> bool:
        return bool(pat.search(blob)) or any(
            re.search(rf"(?<![A-Za-z]){re.escape(fid)}\b", blob) for fid in features)

    waves = DELIVERY_ROADMAP["waves"]
    for i, w in enumerate(waves):
        blob = w["title"] + " " + w["note"] + " " + " ".join(
            t["name"] + " " + t["feat"] + " " + " ".join(t["steps"]) for t in w["tracks"])
        if hit(blob):
            return i
    par = " ".join(p["name"] + " " + p["feat"] + " " + p["note"] for p in DELIVERY_ROADMAP["parallel"])
    if hit(par):
        return len(waves)
    return 100 + phase_num


def next_slice_to_create(tracker: str) -> dict:
    m = re.search(r"^## Work queue\n([\s\S]*?)(?=\n## |\Z)", tracker, re.M)
    if not m:
        return {}
    section = m.group(1)
    pick, label = None, "Ready"
    for lbl in ("Ready", "Queued"):
        hit = re.search(rf"^- \[ \]\s*{lbl}\s*[—-]\s*([\s\S]*?)(?=\n- \[|\Z)", section, re.M)
        if hit:
            pick, label = hit, lbl
            break
    if not pick:
        return {}
    text = " ".join(pick.group(1).split())
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    concise = re.split(r"(?<=[.:])\s", text, 1)[0]
    feats = list(dict.fromkeys(re.findall(r"\b((?:F|IP|P)-\d+)\b", text)))
    phase = re.search(r"Phase (\d+)", text)
    return {"label": label, "text": concise[:240], "features": feats[:4],
            "phase": phase.group(1) if phase else ""}


def build_slice_lane(tracker: str) -> dict:
    rows = slice_index_rows(tracker)
    currents = current_slice_numbers(tracker)
    prog = phase_progress_map(tracker)
    by_phase: dict[int, list] = {}
    for r in rows:
        r["current"] = r["num"] in currents
        by_phase.setdefault(r["phase_num"], []).append(r)
    phases = []
    for pn, slices in by_phase.items():
        feats = {s["feature"] for s in slices if s["feature"]}
        slices.sort(key=lambda s: s["num"])
        meta = prog.get(pn, {})
        rank = _phase_wave_rank(pn, feats)
        if rank >= 100 and meta.get("progress") == 100:
            rank += 100  # fully-delivered phases sink below unfinished ones
        phases.append({"num": pn, "title": meta.get("title") or (slices[0]["phase_title"] if slices else ""),
                       "progress": meta.get("progress"), "slices": slices, "rank": rank})
    phases.sort(key=lambda p: (p["rank"], p["num"]))
    return {"phases": phases, "next_slice": next_slice_to_create(tracker)}


def snapshot(view: str = "committed") -> dict:
    reader = read_repo_file if view == "working" else read_committed_file
    tracker = reader("docs/PROJECT-TRACKER.md")
    debt = reader("docs/TECHNICAL-DEBT-TRACKER.md")
    phases = phase_rows(tracker)
    slices = slice_cards(tracker) + queue_items(tracker)
    debts = debt_cards(debt)
    issue_feed = github_issues()
    goals = goal_maps(issue_feed)
    return {"phases": phases, "slices": slices, "debts": debts, "goals": goals, "features": feature_cards(reader), "actions": action_items(phases, debts, slices), "calibration": calibration(), "slice_lane": build_slice_lane(tracker), "view": view, "issue_feed": issue_feed, "traceability": traceability_model(goals, issue_feed)}


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def card(title: str, body: str, css: str = "") -> str:
    return f'<article class="card {css}"><h3>{esc(title)}</h3><p>{esc(body)}</p></article>'


def roadmap_step_li(step: str, force_done: bool = False) -> str:
    had_marker = re.search("\u2014 done\\.?$", step) is not None
    label = re.sub("\\s*\u2014 done\\.?$", "", step)
    done = force_done or had_marker
    icon = "\u2713" if done else "\u25cb"
    cls = "sdone" if done else ""
    return f'<li class="{cls}"><span class="si">{icon}</span>{esc(label)}</li>'


def track_card(track: dict, force_done: bool = False) -> str:
    steps = "".join(roadmap_step_li(step, force_done) for step in track["steps"])
    return (
        f'<div class="rtrack"><div class="rtrack-h"><strong>{esc(track["name"])}</strong>'
        f'<span class="rfeat">{esc(track["feat"])}</span></div><ul class="rsteps">{steps}</ul></div>'
    )


# Extra CSS for the "do this next" hero and done/next/queued roadmap states.
PRIORITY_CSS = (
    ".hero { background:linear-gradient(180deg,#13212b,#16242f); border:1px solid var(--cyan); "
    "border-left:6px solid var(--cyan); border-radius:10px; padding:16px 18px 18px; margin-bottom:22px; "
    "box-shadow:0 0 0 1px rgba(88,212,232,.15),0 6px 22px rgba(0,0,0,.35); }"
    ".hero-tag { display:inline-block; font-size:11px; font-weight:700; letter-spacing:.14em; "
    "text-transform:uppercase; color:#0b1118; background:var(--cyan); padding:3px 10px; border-radius:12px; margin-bottom:12px; }"
    ".hero-head { display:flex; align-items:center; gap:12px; flex-wrap:wrap; }"
    ".hero-head h2 { margin:0; font-size:21px; color:var(--text); }"
    ".hero-wn { display:inline-flex; align-items:center; justify-content:center; width:34px; height:34px; "
    "border-radius:50%; background:var(--cyan); color:#0b1118; font-weight:800; font-size:16px; flex:none; }"
    ".hero-of { margin-left:auto; font-size:11px; color:var(--muted); white-space:nowrap; }"
    ".hero-note { font-size:13px; color:var(--muted); margin:10px 0 12px; }"
    ".hero-par { font-size:11px; color:var(--muted); margin-top:12px; border-top:1px dashed var(--line); padding-top:10px; }"
    ".hero.done { border-color:var(--green); border-left-color:var(--green); }"
    ".hero.done .hero-tag { background:var(--green); }"
    ".wbadge { font-size:11px; font-weight:700; letter-spacing:.04em; padding:2px 9px; border-radius:12px; "
    "text-transform:uppercase; flex:none; }"
    ".wbadge.done { background:rgba(84,209,138,.16); color:var(--green); border:1px solid var(--green); }"
    ".wbadge.next { background:var(--cyan); color:#0b1118; border:1px solid var(--cyan); }"
    ".wbadge.queued { background:transparent; color:var(--muted); border:1px solid var(--line); }"
    ".wave.done { opacity:.72; }"
    ".wave.done .wn { background:var(--green); }"
    ".wave.done .wave-h h3 { color:var(--muted); }"
    ".wave.next { border-color:var(--cyan); border-left:4px solid var(--cyan); box-shadow:0 0 0 1px rgba(88,212,232,.18); }"
    ".wave.next .wn { background:var(--cyan); }"
    ".wave.queued .wn { background:var(--muted); color:#0b1118; }"
    ".wave-h h3 { margin-right:4px; }"
    ".rtrack ul.rsteps { list-style:none; padding-left:2px; margin:6px 0 0; }"
    ".rtrack ul.rsteps li { display:flex; gap:7px; align-items:flex-start; margin:3px 0; font-size:12px; color:var(--muted); }"
    ".rtrack ul.rsteps li .si { font-size:12px; line-height:1.45; flex:none; color:var(--muted); }"
    ".rtrack ul.rsteps li.sdone { color:var(--text); }"
    ".rtrack ul.rsteps li.sdone .si { color:var(--green); font-weight:700; }"
    ".calib { font-size:12px; color:var(--muted); background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:8px 12px; margin-bottom:14px; }"
    ".calib.warn { border-color:var(--amber); background:#332619; color:#ffe0a0; }"
    ".calib code { color:var(--cyan); }"
    ".trace { margin-bottom:22px; }"
    ".tgrid { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:12px; margin-bottom:12px; }"
    ".tbox { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px 16px; border-top:4px solid var(--cyan); }"
    ".tnum { font-size:30px; line-height:1; font-weight:800; color:var(--cyan); }"
    ".tlbl { margin-top:7px; font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:.08em; }"
    ".tracepills { margin-top:8px; }"
    ".sl { margin-bottom:22px; }"
    ".nextslice { background:#122a1e; border:1px solid var(--green); border-left:5px solid var(--green); border-radius:8px; padding:12px 14px; margin-bottom:14px; }"
    ".ns-tag { display:inline-block; font-size:11px; font-weight:700; letter-spacing:.1em; text-transform:uppercase; color:#0b1118; background:var(--green); padding:2px 9px; border-radius:12px; margin-bottom:8px; }"
    ".nextslice p { color:var(--text); font-size:13px; margin:4px 0 8px; }"
    ".planes { display:grid; grid-template-columns:repeat(auto-fill,minmax(360px,1fr)); gap:12px; align-items:start; }"
    ".plane { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:12px 14px; }"
    ".plane-h { display:flex; justify-content:space-between; align-items:baseline; gap:8px; margin-bottom:8px; }"
    ".plane-h h3 { margin:0; font-size:13px; color:var(--cyan); }"
    ".pl-prog { font-size:12px; color:var(--muted); flex:none; }"
    ".slrows { display:flex; flex-direction:column; gap:4px; }"
    ".slrow { display:flex; align-items:baseline; gap:8px; font-size:12px; padding:4px 7px; border-radius:5px; border-left:3px solid var(--line); background:#1a2430; }"
    ".slrow.done { border-left-color:var(--green); }"
    ".slrow.done .sltitle { color:var(--muted); }"
    ".slrow.active { border-left-color:var(--amber); }"
    ".slrow.current { box-shadow:0 0 0 1px var(--cyan); border-left-color:var(--cyan); }"
    ".slnum { font-family:monospace; color:var(--muted); flex:none; }"
    ".sltitle { flex:1; color:var(--text); }"
    ".sl-feat { font-size:10px; color:var(--muted); border:1px solid var(--line); border-radius:8px; padding:1px 6px; flex:none; }"
    ".sl-cur { font-size:10px; color:var(--cyan); border:1px solid var(--cyan); border-radius:8px; padding:1px 6px; margin-left:6px; }"
    ".hdr-right { display:flex; flex-direction:column; align-items:flex-end; gap:8px; }"
    ".viewtoggle { display:inline-flex; border:1px solid var(--line); border-radius:8px; overflow:hidden; }"
    ".viewtoggle .vt { font-size:12px; padding:5px 12px; color:var(--muted); text-decoration:none; background:var(--panel); }"
    ".viewtoggle .vt + .vt { border-left:1px solid var(--line); }"
    ".viewtoggle .vt.on { background:var(--cyan); color:#0b1118; font-weight:700; }"
    ".calib-link { color:var(--cyan); text-decoration:none; white-space:nowrap; }"
)


# Recommended finish order. Waves run top-to-bottom (sequential); tracks inside a
# wave with >1 entry run in parallel. Kept in the viz tool as the orchestration
# layer's recommendation, not (yet) promoted into PROJECT-TRACKER.
DELIVERY_ROADMAP = {
    "waves": [
        {
            "n": "1", "title": "Finish the combat loop & solid village", "done": True,
            "note": "Monster combat is GUI-confirmed (Slice 033); the monster-RPC blocker was a stale-server method-table artifact, not code (Slice 032 re-run reaches 'player spawned').",
            "tracks": [
                {"name": "Combat loop", "feat": "IP-023 \u00b7 IP-015", "steps": [
                    "Server damage/death (029) + client render (033) \u2014 done",
                    "Monster-RPC blocker resolved \u2014 stale server, not code"]},
                {"name": "Walkable village", "feat": "F-026 \u00b7 F-027", "steps": [
                    "Server collision (F-027) \u2014 done", "Slice 031 bigger village \u2014 done"]},
            ],
        },
        {
            "n": "2", "title": "Lock cross-cutting decisions", "done": True,
            "note": "World-scale contract landed (F-028 / ADR 0003); player-accounts design resolved (all 6 tickets, spec.md, new Phase 14).",
            "tracks": [
                {"name": "World-scale", "feat": "F-028 \u00b7 ADR 0003", "steps": [
                    "1 unit = 1 yard; Sector \u2248 \u00bc mile \u2014 done",
                    "WorldScale contract shipped (Slice 036)"]},
                {"name": "Accounts + persistence design", "feat": "player-accounts \u00b7 Phase 14", "steps": [
                    "All 6 tickets resolved; CONTEXT reconciled \u2014 done",
                    "Handoff spec + shared-SQLite decision \u2014 done"]},
            ],
        },
        {
            "n": "3", "title": "World-scale migration", "done": True,
            "note": "Delivered as ADR 0003's two handoff slices: the versioned WorldScale seam (Slice 036) and the meters\u2192yards relabel of the existing constants (Slice 037, magnitudes unchanged). Full GUT suite green (268/268).",
            "tracks": [
                {"name": "Scale / tuning seam", "feat": "F-028 \u00b7 ADR 0003", "steps": [
                    "Versioned WorldScale seam (Slice 036) \u2014 done",
                    "Reconcile existing constants meters\u2192yards (Slice 037) \u2014 done"]},
            ],
        },
        {
            "n": "4", "title": "Shared SQLite persistence foundation", "done": True,
            "note": "Linchpin, built once (Slice 038, F-029): one server-owned SQLite engine consumed by accounts, Canon, and progression. Engine only \u2014 no domain tables yet.",
            "tracks": [
                {"name": "SQLite engine", "feat": "Phase 9 core \u00b7 accounts core", "steps": [
                    "godot-sqlite GDExtension (headless) \u2014 done",
                    "Atomic tx + user_version fail-closed, server-owned \u2014 done"]},
            ],
        },
        {
            "n": "5", "title": "Two big consumers (parallel)", "done": True,
            "note": "Accounts: auth/session/CRUD/world-entry and the Windows login/Character/gameplay lifecycle are implemented and validated (Linux 315/315 tests; Windows GUI acceptance confirmed). Canon/JIT: IP-008 JIT boundary + P-011/P-012 durable canon (Slices 045-047); P-009 local-inference config/telemetry (Slice 051) and F-026 LLM-on-boot + town-derived monster exclusion (Slices 052-053) implemented \u2014 Phase 8 is 11/11. P-013 GUIDs/RPC/replay (Slices 095-098) also done \u2014 Phase 9 is 4/4.",
            "tracks": [
                {"name": "Player accounts & characters", "feat": "F-031 \u00b7 F-032 \u00b7 F-033 \u00b7 F-034", "steps": [
                    "Auth/session + Character CRUD/world entry (Slices 040, 042-043) \u2014 done",
                    "Character CRUD/select/create \u2192 world entry (Slices 042-044) \u2014 done"]},
                {"name": "Canon persistence + JIT completion", "feat": "Phase 9 \u00b7 Phase 8", "steps": [
                    "IP-008 JIT boundary + P-011/P-012 durable canon (Slices 045/046) \u2014 done",
                    "P-009 inference (Slice 051) + F-026 LLM-on-boot & monster exclusion (Slices 052-053) \u2014 done; P-013 GUIDs/RPC/replay (Slices 095-098) \u2014 done"]},
            ],
        },
        {
            "n": "6", "title": "Harden the runtime",
            "note": "Needs the persistence design; wants a feature-stable server.",
            "tracks": [
                {"name": "Containerized fixed-tick server", "feat": "P-014 \u00b7 Phase 10", "steps": [
                    "Isolated Docker runtime", "20\u201330 Hz tick, health + clean shutdown"]},
            ],
        },
        {
            "n": "7", "title": "Signature progression system",
            "note": "Last on purpose \u2014 largest & most speculative; needs combat + persistence + scale + the accounts vessel seam.",
            "tracks": [
                {"name": "Biological progression & kinetic", "feat": "P-016 \u00b7 Phase 12", "steps": [
                    "Six-node vessel, friction, Meridians", "Burnout, magic equilibrium"]},
            ],
        },
    ],
    "parallel": [
        {"name": "Public access \u2014 WireGuard", "feat": "P-024 \u00b7 Phase 13",
         "note": "Independent files (infra/, ci/, Go GDExtension). Already advancing (Slices 028 \u2192 032)."},
        {"name": "Workflow fillers", "feat": "P-005 \u00b7 P-006 \u00b7 DT-006 (resolved)",
         "note": "Remote-SSH, asset quarantine \u2014 low-risk, anytime. Test migration (DT-006) done via Slice 041."},
    ],
    "sequence_rules": [
        "World-scale ADR \u2192 migration \u2192 any further big generation/bounds work.",
        "SQLite engine \u2192 accounts storage, Canon storage, progression storage.",
        "Combat server (Slice 029) \u2192 client monster rendering.",
        "Persistence design \u2192 containerized runtime (P-014).",
        "Combat + persistence + scale + accounts vessel seam \u2192 biological progression (P-016).",
        "Shared hot-spot files (server_player_state.gd, server_main.gd connect, schema/monster constants): edit one track at a time.",
    ],
}


def render(view: str = "committed") -> str:
    data = snapshot(view)
    working_view = data["view"] == "working"

    features = data["features"]
    stage_order = ["Planned", "Ready", "Active", "Done"]
    stage_css = {"Planned": "planned", "Ready": "", "Active": "in-progress", "Done": "done"}
    fcols: dict[str, list] = {name: [] for name in stage_order}
    for feat in features:
        fcols[feature_stage(feat["status"])].append(feat)

    def feature_card(feat: dict) -> str:
        stage = feature_stage(feat["status"])
        tags = "".join(f'<span class="itag">{esc(t)}</span>' for t in feat["issue_tags"]) or '<span class="itag none">no linked issue</span>'
        return (
            f'<article class="card {stage_css[stage]}"><h3>{esc(feat["id"])} \u00b7 {esc(feat["title"])}</h3>'
            f'<div class="itags">{tags}</div></article>'
        )

    column_html = ""
    board_stages = [name for name in stage_order if name != "Done"] if working_view else stage_order
    for name in board_stages:
        items = fcols[name]
        body = "".join(feature_card(feat) for feat in items) or '<p class="empty">Nothing here</p>'
        column_html += f'<section class="column"><h2>{esc(name)} <span>{len(items)}</span></h2>{body}</section>'
    phase_html = "".join(card(p["phase"], p["status"] + " — " + p["gate"], p["status"].lower()) for p in data["phases"])
    blocked = [d for d in data["debts"] if d["status"].lower() not in {"resolved", "closed", "accepted"}]
    andon_html = "".join(card(d["id"], d["title"] + " — " + d["status"], "andon") for d in blocked) or '<p class="clear">No open Andon signals</p>'
    actions_html = "".join(f"<li>{esc(item)}</li>" for item in data["actions"]) or '<li>No immediate action detected</li>'
    goals = sorted(data["goals"], key=lambda g: (-g["percent"], g["name"]))
    total_issues = sum(g["total"] for g in goals)
    decided_issues = sum(g["decided"] for g in goals)
    overall_pct = round(decided_issues / total_issues * 100) if total_issues else 0
    goal_html = ""
    for g in goals:
        chips = "".join(
            f'<span class="chip {i["state"]}" title="{esc(i["status"])}">{esc(("#" + str(i["github_number"]) + " · ") if i.get("github_number") else "")}{esc((i["id"] + " ") if i["id"] else "")}{esc(i["title"])}</span>'
            for i in g["issues"]
        ) or '<span class="chip todo">no issues</span>'
        dest = g["destination"]
        if len(dest) > 170:
            dest = dest[:167].rstrip() + "\u2026"
        issue_count = f'#{g["github_number"]} · {g["decided"]}/{g["total"]} · {g["percent"]}%' if g.get("github_number") else f'no GitHub issue · {g["decided"]}/{g["total"]} · {g["percent"]}%'
        missing = '<span class="itag none">new / unresearched</span>' if g.get("map_missing") else ''
        goal_html += (
            f'<section class="goal"><div class="goal-head"><h3>{esc(g["title"])}</h3>'
            f'<span class="pct">{esc(issue_count)}</span></div>'
            f'<div class="bar"><div class="fill" style="width:{g["percent"]}%"></div></div>'
            f'<p class="dest">{esc(dest)}</p><div class="itags">{missing}<span class="itag">{esc(g["source"])}</span></div><div class="chips">{chips}</div></section>'
        )
    goal_html = goal_html or '<p class="empty">No goal maps found</p>'
    vetting_n = sum(1 for g in goals for i in g["issues"] if i["state"] != "decided")
    stage_defs = [
        ("Vetting", vetting_n, "vet"),
        ("Planned", len(fcols["Planned"]), "planned"),
        ("Ready", len(fcols["Ready"]), "ready"),
        ("Active", len(fcols["Active"]), "active"),
        ("Done", len(fcols["Done"]), "done"),
    ]
    flow_html = '<div class="arw">\u2192</div>'.join(
        f'<div class="stage {cls}"><span class="n">{n}</span><span class="lbl">{esc(name)}</span></div>'
        for name, n, cls in stage_defs
    )
    trace = data["traceability"]
    missing_map_html = "".join(
        f'<span class="pill"><small>#{esc(str(g.get("github_number") or "?"))}</small>{esc(g["name"])} · new / unresearched</span>'
        for g in trace["missing_maps"]
    ) or '<span class="pill"><span class="dot">✓</span>No unresearched goal folders</span>'
    trace_html = (
        '<section class="trace"><h2 class="sech">GitHub traceability baseline</h2>'
        '<div class="tgrid">'
        f'<div class="tbox"><div class="tnum">{trace["slices"]["linked"]}/{trace["slices"]["total"]}</div><div class="tlbl">slice records linked</div></div>'
        f'<div class="tbox"><div class="tnum">{trace["goal_linked"]}/{trace["goals"]}</div><div class="tlbl">parent goal issues</div></div>'
        f'<div class="tbox"><div class="tnum">{trace["child_linked"]}/{trace["child_total"]}</div><div class="tlbl">child planning issues</div></div>'
        f'<div class="tbox"><div class="tnum">{len(trace["slices"]["missing"])}</div><div class="tlbl">missing slice links</div></div>'
        '</div>'
        f'<div class="pills tracepills">{missing_map_html}</div></section>'
    )
    waves = DELIVERY_ROADMAP["waves"]
    next_wave = next((w for w in waves if not w.get("done")), None)
    done_count = sum(1 for w in waves if w.get("done"))
    wave_total = len(waves)

    waves_html = ""
    for w in waves:
        tracks = w["tracks"]
        is_done = bool(w.get("done"))
        if is_done:
            state, sbadge = "done", '<span class="wbadge done">\u2713 Done</span>'
        elif w is next_wave:
            state, sbadge = "next", '<span class="wbadge next">\u25b6 Do next</span>'
        else:
            state, sbadge = "queued", '<span class="wbadge queued">Queued</span>'
        par = (f'<span class="par">{len(tracks)} parallel tracks</span>'
               if len(tracks) > 1 else '<span class="par seq">single track</span>')
        track_cards = "".join(track_card(t, is_done) for t in tracks)
        waves_html += (
            f'<div class="wave {state}"><div class="wave-h"><span class="wn">{esc(w["n"])}</span>'
            f'{sbadge}<h3>{esc(w["title"])}</h3>{par}</div>'
            f'<p class="wnote">{esc(w["note"])}</p>'
            f'<div class="rtracks">{track_cards}</div></div>'
        )
    par_html = "".join(
        f'<div class="pcard"><div class="rtrack-h"><strong>{esc(p["name"])}</strong>'
        f'<span class="rfeat">{esc(p["feat"])}</span></div><p>{esc(p["note"])}</p></div>'
        for p in DELIVERY_ROADMAP["parallel"]
    )
    seq_html = "".join(f'<li>{esc(r)}</li>' for r in DELIVERY_ROADMAP["sequence_rules"])

    if next_wave:
        hero_tracks = "".join(track_card(t) for t in next_wave["tracks"])
        hero_par = " \u00b7 ".join(esc(p["name"]) for p in DELIVERY_ROADMAP["parallel"])
        hero_html = (
            f'<section class="hero"><span class="hero-tag">\u25b6 Do this next</span>'
            f'<div class="hero-head"><span class="hero-wn">{esc(next_wave["n"])}</span>'
            f'<h2>{esc(next_wave["title"])}</h2>'
            f'<span class="hero-of">wave {esc(next_wave["n"])} of {wave_total} \u00b7 {done_count} done</span></div>'
            f'<p class="hero-note">{esc(next_wave["note"])}</p>'
            f'<div class="rtracks">{hero_tracks}</div>'
            f'<p class="hero-par">Safe to run in parallel: {hero_par}</p></section>'
        )
    else:
        hero_html = (
            '<section class="hero done"><span class="hero-tag">\u2713 All waves complete</span>'
            '<p class="hero-note">Every delivery-roadmap wave is done. Pick the next goal from the vetting roadmap below.</p></section>'
        )

    calib = data["calibration"]
    if not calib["available"]:
        calib_html = '<div class="calib">Showing the working tree (git unavailable in this environment).</div>'
    elif working_view:
        files = ", ".join(esc(f.rsplit("/", 1)[-1]) for f in calib["dirty_records"]) or "none"
        calib_html = (
            f'<div class="calib warn"><strong>\u26a0 Live working tree \u2014 unfinished work only</strong> \u2014 includes uncommitted edits and '
            f'may be mid-slice; done items are hidden. Dirty record files: {files}. {calib["in_flight"]} file(s) in flight total.</div>'
        )
    else:
        src = f'board reflects committed <code>{esc(calib["sha"])}</code> \u00b7 {esc(calib["subject"][:70])}'
        if calib["dirty_records"]:
            files = ", ".join(esc(f.rsplit("/", 1)[-1]) for f in calib["dirty_records"])
            calib_html = (
                f'<div class="calib warn"><strong>\u26a0 {len(calib["dirty_records"])} record file(s) uncommitted / in-flight</strong> '
                f'\u2014 not reflected below: {files}. {calib["in_flight"]} file(s) in flight total. The {src}. '
                f'<a class="calib-link" href="/?view=working">View working tree \u2192</a></div>'
            )
        else:
            calib_html = (
                f'<div class="calib"><strong>\u2713 Records clean</strong> \u2014 the {src}. '
                f'{calib["in_flight"]} non-record file(s) in flight.</div>'
            )

    lane = data["slice_lane"]
    ns = lane["next_slice"]
    if ns:
        ns_feats = "".join(f'<span class="itag">{esc(f)}</span>' for f in ns["features"])
        ns_ph = f' \u00b7 Phase {esc(ns["phase"])}' if ns["phase"] else ""
        next_slice_html = (
            f'<div class="nextslice"><span class="ns-tag">Next slice to create</span>'
            f'<p>{esc(ns["text"])}</p>'
            f'<div class="itags">{ns_feats}<span class="itag none">{esc(ns["label"])}{ns_ph}</span></div></div>'
        )
    else:
        next_slice_html = ''
    plane_html = ""
    for p in lane["phases"]:
        plane_slices = [s for s in p["slices"] if not s["done"]] if working_view else p["slices"]
        if working_view and not plane_slices:
            continue
        srows = ""
        for s in plane_slices:
            cls = "done" if s["done"] else "active"
            cur = ' current' if s["current"] else ''
            feat = f'<span class="sl-feat">{esc(s["feature"])}</span>' if s["feature"] else ''
            mark = '\u2713 ' if s["done"] else ''
            curlbl = '<span class="sl-cur">current</span>' if s["current"] else ''
            srows += (
                f'<div class="slrow {cls}{cur}" title="{esc(s["status_text"])}">'
                f'<span class="slnum">{s["num"]:03d}</span>'
                f'<span class="sltitle">{mark}{esc(s["title"])}{curlbl}</span>{feat}</div>'
            )
        prog = f'<span class="pl-prog">{p["progress"]}%</span>' if p["progress"] is not None else ''
        plane_html += (
            f'<div class="plane"><div class="plane-h"><h3>Phase {p["num"]} \u00b7 {esc(p["title"])}</h3>{prog}</div>'
            f'<div class="slrows">{srows}</div></div>'
        )
    slices_html = next_slice_html + f'<div class="planes">{plane_html}</div>'
    toggle_html = (
        '<div class="viewtoggle">'
        f'<a class="vt{"" if working_view else " on"}" href="/detail">Committed</a>'
        f'<a class="vt{" on" if working_view else ""}" href="/detail?view=working">Working tree</a>'
        '</div>'
    )
    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="15"><title>Project0 Flow Dashboard</title>
<style>
:root {{ color-scheme: dark; --bg:#11161d; --panel:#1a222d; --line:#304052; --text:#e8eef5; --muted:#9dafbf; --cyan:#58d4e8; --green:#54d18a; --amber:#f3bd55; --red:#ff7070; }}
* {{ box-sizing:border-box }} body {{ margin:0; font:14px/1.4 system-ui,sans-serif; background:var(--bg); color:var(--text) }} header {{ padding:24px 32px; border-bottom:1px solid var(--line); display:flex; justify-content:space-between; align-items:end }} h1 {{ margin:0; color:var(--cyan); letter-spacing:.03em }} h2 {{ margin:0 0 12px; font-size:16px }} h3 {{ margin:0 0 6px; font-size:14px }} p {{ margin:0; color:var(--muted) }} main {{ padding:24px 32px; max-width:1500px; margin:auto }} .banner {{ background:#332619; border:1px solid var(--amber); color:#ffe0a0; padding:14px 16px; margin-bottom:22px; border-radius:8px }} .board {{ display:grid; grid-template-columns:repeat(4,minmax(190px,1fr)); gap:14px; align-items:start }} .column,.panel {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px }} .column h2 span {{ float:right; color:var(--muted); font-weight:normal }} .card {{ background:#222d39; border:1px solid #3a4b5d; border-left:4px solid var(--cyan); border-radius:6px; padding:10px; margin:8px 0 }} .card.andon {{ border-left-color:var(--red) }} .card.in-progress {{ border-left-color:var(--amber) }} .card.done {{ border-left-color:var(--green) }} .empty,.clear {{ color:var(--muted); padding:12px 0 }} .grid {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-top:22px }} ul {{ margin:0; padding-left:20px }} li {{ margin:8px 0 }} .action {{ color:#ffe0a0 }} .stamp {{ color:var(--muted); font-size:12px }} @media(max-width:900px) {{ .board,.grid {{ grid-template-columns:1fr 1fr }} }} @media(max-width:600px) {{ header,main {{ padding:16px }} .board,.grid {{ grid-template-columns:1fr }} }}
.rmwrap {{ margin-bottom:22px }} .rmwrap h2 {{ display:flex; justify-content:space-between; align-items:baseline }} .rmwrap h2 span {{ color:var(--muted); font-weight:normal; font-size:13px }} .roadmap {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(330px,1fr)); gap:14px }} .goal {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px }} .goal-head {{ display:flex; justify-content:space-between; align-items:baseline; gap:8px }} .goal-head h3 {{ margin:0; color:var(--cyan) }} .pct {{ color:var(--muted); font-size:12px; white-space:nowrap }} .bar {{ height:8px; background:#0e141b; border:1px solid var(--line); border-radius:6px; overflow:hidden; margin:10px 0 }} .fill {{ height:100%; background:linear-gradient(90deg,var(--green),var(--cyan)) }} .dest {{ font-size:12px; margin-bottom:10px }} .chips {{ display:flex; flex-wrap:wrap; gap:6px }} .chip {{ font-size:11px; padding:3px 8px; border-radius:12px; border:1px solid var(--line); background:#222d39; color:var(--muted) }} .chip.decided {{ border-color:var(--green); color:var(--green) }} .chip.active {{ border-color:var(--amber); color:var(--amber) }} .chip.todo {{ opacity:.7 }}
.flow {{ display:flex; align-items:stretch; gap:6px; margin-bottom:22px; flex-wrap:wrap }} .flow .stage {{ flex:1 1 0; min-width:118px; background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:12px 14px; display:flex; flex-direction:column; gap:2px }} .flow .stage .n {{ font-size:22px; font-weight:600 }} .flow .stage .lbl {{ font-size:12px; color:var(--muted) }} .flow .stage.vet {{ border-left:4px solid var(--muted) }} .flow .stage.ready {{ border-left:4px solid var(--cyan) }} .flow .stage.active {{ border-left:4px solid var(--amber) }} .flow .stage.await {{ border-left:4px solid var(--amber) }} .flow .stage.done {{ border-left:4px solid var(--green) }} .flow .arw {{ align-self:center; color:var(--muted); font-size:18px }} .sech {{ margin:0 0 10px; font-size:13px; text-transform:uppercase; letter-spacing:.08em; color:var(--muted) }}
.itags {{ display:flex; flex-wrap:wrap; gap:4px; margin-top:8px }} .itag {{ font-size:10px; padding:2px 7px; border-radius:10px; background:#1a2430; border:1px solid var(--line); color:var(--muted) }} .itag.none {{ opacity:.6; font-style:italic }} .card.planned {{ border-left-color:var(--muted) }} .flow .stage.planned {{ border-left:4px solid var(--muted) }}
.dr {{ margin-bottom:22px }} .waves {{ display:flex; flex-direction:column; gap:10px }} .wave {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:12px 14px }} .wave-h {{ display:flex; align-items:center; gap:10px }} .wave-h h3 {{ margin:0; font-size:14px; color:var(--text) }} .wn {{ display:inline-flex; align-items:center; justify-content:center; width:26px; height:26px; border-radius:50%; background:var(--cyan); color:#0b1118; font-weight:700; font-size:13px; flex:none }} .par {{ margin-left:auto; font-size:11px; color:var(--green); border:1px solid var(--green); border-radius:12px; padding:2px 8px }} .par.seq {{ color:var(--muted); border-color:var(--line) }} .wnote {{ font-size:12px; margin:6px 0 10px }} .rtracks {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:10px }} .rtrack {{ background:#222d39; border:1px solid #3a4b5d; border-left:4px solid var(--amber); border-radius:6px; padding:8px 10px }} .rtrack-h {{ display:flex; justify-content:space-between; align-items:baseline; gap:8px }} .rtrack-h strong {{ font-size:13px }} .rfeat {{ font-size:10px; color:var(--muted); white-space:nowrap }} .rtrack ul {{ padding-left:16px; margin:6px 0 0 }} .rtrack li {{ margin:3px 0; font-size:12px; color:var(--muted) }} .drband {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; margin-top:12px }} .drcol {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:12px 14px }} .drcol h4 {{ margin:0 0 8px; font-size:12px; text-transform:uppercase; letter-spacing:.06em; color:var(--muted) }} .pcards {{ display:flex; flex-direction:column; gap:8px }} .pcard {{ background:#222d39; border:1px solid #3a4b5d; border-left:4px solid var(--green); border-radius:6px; padding:8px 10px }} .pcard p {{ font-size:12px; margin:6px 0 0 }} .seqrules {{ padding-left:18px }} .seqrules li {{ margin:5px 0; font-size:12px; color:var(--muted) }} @media(max-width:700px){{ .drband {{ grid-template-columns:1fr }} }}
{PRIORITY_CSS}
</style></head><body>
<header><div><h1>Project0 Traceability</h1><p>Issue hierarchy, slices, and delivery records</p></div><div class="hdr-right"><a class="calib-link" href="/">\u2190 Reality view</a><a class="calib-link" href="/tests">Tests</a>{toggle_html}<div class="stamp">Read-only · refreshes every 15s</div></div></header>
<main>{calib_html}{trace_html}<div class="banner"><strong>Open signals</strong><ul>{actions_html}</ul></div>
<section class="flow">{flow_html}</section>
<section class="sl"><h2 class="sech">Slices \u2014 what's part of what, in priority order</h2>{slices_html}</section>
<section class="rmwrap"><h2>Goals \u00b7 parent issues and child planning issues <span>{decided_issues}/{total_issues} local issues decided \u00b7 {overall_pct}%</span></h2><div class="roadmap">{goal_html}</div></section>
<h2 class="sech">Implementation pipeline \u2014 features correlated to local planning issues</h2>
<section class="board">{column_html}</section>
<div class="grid"><section class="panel"><h2>Andon / Stop Signals</h2>{andon_html}</section><section class="panel"><h2>Phase Status</h2>{phase_html or '<p>No phase data found</p>'}</section></div>
</main></body></html>'''


# --- Executive "Reality" view -------------------------------------------------
# A deliberately small, chart-first read of the same authoritative records:
# how far along overall, what is shipped, what is in progress (and how far),
# and what is being worked on right now. Less prose, more scale.

def _exec_short(text: str, limit: int = 44) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "\u2026"


def _pcol(pct: int) -> str:
    return "var(--green)" if pct >= 100 else ("var(--amber)" if pct > 0 else "var(--grey)")


def _donut(pct: int, size: int = 190, stroke: int = 20) -> str:
    import math
    pct = max(0, min(100, int(pct)))
    r = (size - stroke) / 2
    circ = 2 * math.pi * r
    off = circ * (1 - pct / 100)
    ctr = size / 2
    return (
        f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" role="img" aria-label="{pct}% complete">'
        '<defs><linearGradient id="eg" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#5ad78f"/><stop offset="1" stop-color="#5ad0e6"/></linearGradient></defs>'
        f'<circle cx="{ctr}" cy="{ctr}" r="{r:.1f}" fill="none" stroke="#22303d" stroke-width="{stroke}"/>'
        f'<circle cx="{ctr}" cy="{ctr}" r="{r:.1f}" fill="none" stroke="url(#eg)" stroke-width="{stroke}" '
        f'stroke-linecap="round" stroke-dasharray="{circ:.1f}" stroke-dashoffset="{off:.1f}" '
        f'transform="rotate(-90 {ctr} {ctr})"/>'
        f'<text x="50%" y="50%" text-anchor="middle" dy="-2" font-size="46" font-weight="800" fill="#e9eff6">{pct}%</text>'
        '<text x="50%" y="50%" text-anchor="middle" dy="26" font-size="12" fill="#93a4b5">complete</text></svg>'
    )


def executive_model(reader) -> dict:
    tracker = reader("docs/PROJECT-TRACKER.md")
    features = feature_cards(reader)
    rows = slice_index_rows(tracker)
    prog = phase_progress_map(tracker)
    currents = current_slice_numbers(tracker)

    # Per-feature slice completion (the most concrete "based on what we know now").
    fstats: dict[str, dict] = {}
    fphase: dict[str, int] = {}
    for r in rows:
        fid = r["feature"]
        if not fid:
            continue
        st = fstats.setdefault(fid, {"done": 0, "total": 0})
        st["total"] += 1
        st["done"] += 1 if r["done"] else 0
        if fid not in fphase and r["phase_num"]:
            fphase[fid] = r["phase_num"]

    done_f, active_f, other_f = [], [], []
    for f in features:
        stage = feature_stage(f["status"])
        if stage == "Done":
            done_f.append(f)
        elif stage == "Active":
            st = fstats.get(f["id"])
            if st and st["total"]:
                pct = round(st["done"] / st["total"] * 100)
            else:
                pct = (prog.get(fphase.get(f["id"], -1), {}) or {}).get("progress", 40)
            active_f.append({**f, "pct": max(15, min(90, pct))})  # in progress is never 0 or 100
        else:
            other_f.append(f)
    active_f.sort(key=lambda x: -x["pct"])

    status_by_num: dict[int, str] = {}
    for p in phase_rows(tracker):
        mnum = re.match(r"(\d+)", p["phase"])
        if mnum:
            status_by_num[int(mnum.group(1))] = p["status"].lower()
    phases = [{"num": n, "title": meta["title"], "pct": meta["progress"],
               "status": status_by_num.get(n, "")} for n, meta in sorted(prog.items())]
    # Weight overall completion by tracked phase items.
    done_items = sum(m["done_items"] for m in prog.values() if m.get("done_items") is not None)
    total_items = sum(m["total_items"] for m in prog.values() if m.get("total_items") is not None)
    if total_items:
        overall = round(done_items / total_items * 100)
    else:
        overall = round(sum(p["pct"] for p in phases) / len(phases)) if phases else 0

    # Focus = the current slice of each still-unfinished phase.
    focus, seen = [], set()
    for r in rows:
        pn = r["phase_num"]
        meta = prog.get(pn) or {}
        pct = meta.get("progress")
        if r["num"] not in currents or pct is None or pct >= 100 or pn in seen:
            continue
        seen.add(pn)
        focus.append({"phase_num": pn, "phase_title": meta.get("title") or r["phase_title"],
                      "title": r["title"], "pct": pct})
    focus.sort(key=lambda x: -x["pct"])

    return {"overall": overall, "phases": phases, "done": done_f,
            "active": active_f, "not_started": other_f, "focus": focus}


EXEC_CSS = """
:root{color-scheme:dark;--bg:#0f141a;--panel:#19212b;--card:#202b37;--line:#2c3a49;--text:#e9eff6;--muted:#93a4b5;--cyan:#5ad0e6;--green:#5ad78f;--amber:#f5c15a;--grey:#5b6b7b}
*{box-sizing:border-box}
body{margin:0;font:15px/1.45 system-ui,Segoe UI,sans-serif;background:var(--bg);color:var(--text)}
header{padding:22px 34px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px}
header h1{margin:0;font-size:22px;letter-spacing:.02em}
header .sub{color:var(--muted);font-size:12px;margin-top:3px}
.nav{display:flex;gap:8px;align-items:center}
.nav a{font-size:12px;color:var(--muted);text-decoration:none;border:1px solid var(--line);border-radius:8px;padding:6px 12px;background:var(--panel)}
.nav a.on{background:var(--cyan);color:#08121a;font-weight:700;border-color:var(--cyan)}
main{padding:26px 34px;max-width:1180px;margin:auto}
.sec{margin:0 0 32px}
.sec>h2{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin:0 0 14px;font-weight:700}
.hero{display:grid;grid-template-columns:210px 1fr;gap:28px;align-items:center;background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:24px 28px;margin-bottom:32px}
.tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px 20px;border-top:4px solid var(--line)}
.tile .num{font-size:42px;font-weight:800;line-height:1}
.tile .lbl{font-size:12px;color:var(--muted);margin-top:8px;text-transform:uppercase;letter-spacing:.08em}
.tile.done{border-top-color:var(--green)}.tile.done .num{color:var(--green)}
.tile.active{border-top-color:var(--amber)}.tile.active .num{color:var(--amber)}
.tile.todo{border-top-color:var(--grey)}.tile.todo .num{color:var(--muted)}
.focus{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:14px}
.fcard{background:var(--card);border:1px solid var(--line);border-left:5px solid var(--amber);border-radius:10px;padding:16px 18px}
.fcard .ph{font-size:12px;color:var(--amber);font-weight:700;letter-spacing:.05em;text-transform:uppercase}
.fcard .ti{font-size:15px;margin:8px 0 12px}
.mini{height:8px;background:#0e141b;border-radius:6px;overflow:hidden}
.mini>i{display:block;height:100%;background:var(--amber)}
.fcard .pc{font-size:12px;color:var(--muted);margin-top:8px}
.bars{display:flex;flex-direction:column;gap:12px}
.brow{display:grid;grid-template-columns:250px 1fr 54px;gap:14px;align-items:center}
.brow .bl{font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.brow .bl small{color:var(--muted);font-family:monospace;margin-right:7px}
.track{height:15px;background:#0e141b;border:1px solid var(--line);border-radius:8px;overflow:hidden}
.track>i{display:block;height:100%;border-radius:8px}
.brow .bp{font-size:13px;font-weight:700;text-align:right;font-variant-numeric:tabular-nums}
.pills{display:flex;flex-wrap:wrap;gap:8px}
.pill{display:inline-flex;align-items:center;gap:7px;font-size:12px;background:var(--card);border:1px solid var(--line);border-radius:20px;padding:7px 13px}
.pill .dot{color:var(--green);font-weight:800}
.pill small{color:var(--muted);font-family:monospace}
.issues{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:12px}
.issue{display:block;background:var(--card);border:1px solid var(--line);border-left:5px solid var(--cyan);border-radius:10px;padding:14px 16px;text-decoration:none;color:var(--text)}
.issue:hover{border-left-color:var(--green)}
.issue .inum{font-family:monospace;color:var(--cyan);font-size:12px;margin-bottom:5px}
.issue .ititle{font-size:14px;margin-bottom:9px}
.issue .labels{display:flex;flex-wrap:wrap;gap:5px}
.issue .label{font-size:10px;color:var(--muted);border:1px solid var(--line);border-radius:12px;padding:2px 7px}
.issue .gstats{display:flex;justify-content:space-between;gap:10px;align-items:center;color:var(--muted);font-size:12px;margin:8px 0}
.issue .gbar{height:8px;background:#0e141b;border:1px solid var(--line);border-radius:8px;overflow:hidden;margin:8px 0 10px}
.issue .gbar>i{display:block;height:100%;background:linear-gradient(90deg,var(--green),var(--cyan))}
.issue .gdone{font-weight:800;color:var(--green)}
.sourcewarn{background:#332619;border:1px solid var(--amber);color:#ffe0a0;border-radius:10px;padding:12px 14px}
.legend{display:flex;gap:18px;font-size:11px;color:var(--muted);margin-top:14px;flex-wrap:wrap}
.legend span{display:inline-flex;align-items:center;gap:6px}
.legend i{width:11px;height:11px;border-radius:3px;display:inline-block}
.empty{color:var(--muted)}
.stamp{color:var(--muted);font-size:11px}
@media(max-width:760px){.hero{grid-template-columns:1fr}.tiles{grid-template-columns:1fr}.brow{grid-template-columns:1fr auto}.brow .track{grid-column:1/-1;order:3}}
"""


TESTS_CSS = """
.trunbar{border:1px solid var(--line);border-radius:10px;padding:12px 16px;margin-bottom:22px;font-size:13px;background:var(--panel)}
.trunbar.ok{border-left:5px solid var(--green)}
.trunbar.bad{border-left:5px solid #f57a7a}
.tsummary{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:14px;margin-bottom:24px}
.tstat{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;border-top:4px solid var(--line)}
.tstat .num{font-size:34px;font-weight:800;line-height:1}
.tstat .lbl{font-size:11px;color:var(--muted);margin-top:6px;text-transform:uppercase;letter-spacing:.08em}
.tstat.pass{border-top-color:var(--green)}.tstat.pass .num{color:var(--green)}
.tstat.fail{border-top-color:#f57a7a}.tstat.fail .num{color:#f57a7a}
.tstat.skip{border-top-color:var(--amber)}.tstat.skip .num{color:var(--amber)}
.suites{display:flex;flex-direction:column;gap:8px}
.suite{background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.suite>summary{cursor:pointer;padding:12px 16px;display:flex;align-items:center;gap:12px;list-style:none}
.suite>summary::-webkit-details-marker{display:none}
.sname{flex:1;font-family:monospace;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sbadge{font-size:11px;font-weight:700;border-radius:20px;padding:3px 10px;white-space:nowrap}
.sbadge.ok{background:#16311f;color:var(--green)}
.sbadge.bad{background:#3a1c1c;color:#f79c9c}
.trow{padding:8px 16px 8px 40px;border-top:1px solid var(--line);display:flex;flex-wrap:wrap;align-items:center;gap:10px;font-size:12px}
.trow.fail{background:#241417}
.tdot{font-weight:800;width:14px;text-align:center}
.tdot.pass{color:var(--green)}.tdot.fail{color:#f57a7a}.tdot.skip{color:var(--amber)}
.tname{flex:1;font-family:monospace;word-break:break-word}
.ttime{color:var(--muted);font-variant-numeric:tabular-nums;font-size:11px}
.tmsg{width:100%;margin:2px 0 0 24px;padding:8px 10px;background:#0e141b;border:1px solid var(--line);border-radius:6px;color:#f7b0b0;font-family:monospace;font-size:11px;white-space:pre-wrap;overflow-x:auto}
"""


def render_exec(view: str = "committed") -> str:
    reader = read_repo_file if view == "working" else read_committed_file
    m = executive_model(reader)
    issue_feed = github_issues()
    all_issues = issue_feed["issues"]
    open_issues = [issue for issue in all_issues if issue.get("state") == "open"]
    goal_cards = goal_issue_cards(issue_feed)
    open_goal_children = sum(goal["child_open"] for goal in goal_cards)

    focus_html = "".join(
        f'<div class="fcard"><div class="ph">Phase {c["phase_num"]} \u00b7 {c["pct"]}%</div>'
        f'<div class="ti">{esc(_exec_short(c["phase_title"], 40))}</div>'
        f'<div class="mini"><i style="width:{c["pct"]}%"></i></div>'
        f'<div class="pc">Now: {esc(_exec_short(c["title"], 48))}</div></div>'
        for c in m["focus"]
    ) or '<p class="empty">Nothing marked in progress.</p>'

    active_html = "".join(
        f'<div class="brow"><div class="bl"><small>{esc(f["id"])}</small>{esc(_exec_short(f["title"]))}</div>'
        f'<div class="track"><i style="width:{f["pct"]}%;background:var(--amber)"></i></div>'
        f'<div class="bp" style="color:var(--amber)">{f["pct"]}%</div></div>'
        for f in m["active"]
    ) or '<p class="empty">No features in progress.</p>'

    phase_html = "".join(
        f'<div class="brow"><div class="bl"><small>P{p["num"]:02d}</small>{esc(_exec_short(p["title"]))}</div>'
        f'<div class="track"><i style="width:{p["pct"]}%;background:{_pcol(p["pct"])}"></i></div>'
        f'<div class="bp" style="color:{_pcol(p["pct"])}">{p["pct"]}%</div></div>'
        for p in m["phases"]
    )

    done_html = "".join(
        f'<span class="pill"><span class="dot">\u2713</span><small>{esc(f["id"])}</small>{esc(_exec_short(f["title"]))}</span>'
        for f in m["done"]
    ) or '<p class="empty">Nothing shipped yet.</p>'

    if issue_feed["available"]:
        issues_html = "".join(
            f'<a class="issue" href="{esc(issue["url"])}"><div class="inum">#{issue["number"]}</div>'
            f'<div class="ititle">{esc(issue["title"])}</div>'
            f'<div class="gstats"><span>Target coverage: {issue["target_percent"]}%</span>'
            f'<span class="gdone">{issue["target_percent"]}%</span></div>'
            f'<div class="gbar"><i style="width:{issue["target_percent"]}%"></i></div>'
            f'<div class="labels"><span class="label">known child coverage {issue["target_covered"]}/{issue["child_total"]}</span><span class="label">{issue["child_closed"]} closed</span><span class="label">{issue["child_open"]} open</span>'
            f'{"".join(f"<span class=\"label\">{esc(label)}</span>" for label in issue["labels"])}'
            f'</div></a>'
            for issue in goal_cards
        ) or '<p class="empty">No Goal issues found.</p>'
        issue_status = f'{len(goal_cards)} goal issue(s), {open_goal_children} open child issue(s) from {esc(issue_feed["repo"])}'
    else:
        issues_html = f'<div class="sourcewarn">GitHub issues unavailable: {esc(issue_feed["error"])}</div>'
        issue_status = f'GitHub issues unavailable for {esc(issue_feed["repo"])}'

    other = "?view=working" if view != "working" else "?view=committed"
    other_lbl = "Working tree" if view != "working" else "Committed"
    src = "live working tree" if view == "working" else "last committed state"

    cal = calibration()
    prov = f'@{esc(cal["sha"])}' if cal.get("sha") else "no git"
    if view != "working" and cal.get("in_flight"):
        prov += (f' \u00b7 <b style="color:var(--amber)">{cal["in_flight"]} uncommitted '
                 f'change(s) not shown</b>')

    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="30"><title>Project0 \u2014 Reality</title>
<style>{EXEC_CSS}</style></head><body>
<header>
    <div><h1>Project0 \u2014 Reality</h1><div class="sub">Where the product actually stands \u00b7 {esc(src)} \u00b7 {prov} \u00b7 {issue_status} \u00b7 auto-refreshes</div></div>
  <div class="nav"><a class="on" href="/">Reality</a><a href="/detail">Detailed</a><a href="/tests">Tests</a><a href="/{other}">{esc(other_lbl)}</a></div>
</header>
<main>
  <section class="hero">
    <div>{_donut(m["overall"])}</div>
    <div class="tiles">
      <div class="tile done"><div class="num">{len(m["done"])}</div><div class="lbl">Shipped</div></div>
      <div class="tile active"><div class="num">{len(m["active"])}</div><div class="lbl">In progress</div></div>
        <div class="tile todo"><div class="num">{open_goal_children if issue_feed["available"] else len(m["not_started"])}</div><div class="lbl">Open goal child issues</div></div>
    </div>
  </section>

    <section class="sec"><h2>GitHub source of truth</h2><div class="issues">{issues_html}</div></section>

  <section class="sec"><h2>\u25b6 Focused on now</h2><div class="focus">{focus_html}</div></section>

  <section class="sec"><h2>In progress \u2014 how far</h2><div class="bars">{active_html}</div></section>

  <section class="sec"><h2>Delivery by phase</h2><div class="bars">{phase_html}</div>
    <div class="legend"><span><i style="background:var(--green)"></i>Complete</span>
    <span><i style="background:var(--amber)"></i>In progress</span>
    <span><i style="background:var(--grey)"></i>Not started</span></div>
  </section>

  <section class="sec"><h2>Shipped \u2014 working functionality ({len(m["done"])})</h2><div class="pills">{done_html}</div></section>
</main></body></html>'''


def _to_float(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def tests_model() -> dict:
    summary = {}
    raw_summary = read_repo_file("build/validation/validation-summary.json")
    if raw_summary:
        try:
            summary = json.loads(raw_summary)
        except json.JSONDecodeError:
            summary = {}

    raw_xml = read_repo_file("build/validation/gut.xml")
    suites = []
    total = passed = failed = skipped = 0
    parse_error = ""
    root = None
    if raw_xml:
        try:
            root = ET.fromstring(raw_xml)
        except ET.ParseError as exc:
            parse_error = str(exc)

    if root is not None:
        for suite in root.iter("testsuite"):
            cases = []
            for case in suite.findall("testcase"):
                status = (case.get("status") or "").lower()
                failure = case.find("failure")
                error = case.find("error")
                if failure is not None or error is not None or status in ("fail", "error"):
                    st = "fail"
                elif status in ("skip", "skipped", "pending"):
                    st = "skip"
                else:
                    st = "pass"
                node = failure if failure is not None else error
                message = ""
                if node is not None:
                    message = (node.text or node.get("message") or "").strip()
                cases.append({
                    "name": case.get("name", ""),
                    "status": st,
                    "time": _to_float(case.get("time")),
                    "message": message,
                })
            suite_failed = sum(1 for c in cases if c["status"] == "fail")
            suite_skipped = sum(1 for c in cases if c["status"] == "skip")
            total += len(cases)
            failed += suite_failed
            skipped += suite_skipped
            passed += len(cases) - suite_failed - suite_skipped
            suites.append({
                "name": suite.get("name", ""),
                "tests": len(cases),
                "failures": suite_failed,
                "skipped": suite_skipped,
                "time": _to_float(suite.get("time")),
                "cases": cases,
            })

    # Failing suites first, then alphabetical, so red rises to the top.
    suites.sort(key=lambda s: (s["failures"] == 0, s["name"]))
    return {
        "available": bool(raw_xml) and not parse_error,
        "parse_error": parse_error,
        "suites": suites,
        "total": total,
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "summary": summary,
    }


def _tdot(status: str) -> str:
    if status == "fail":
        return '<span class="tdot fail">\u2717</span>'
    if status == "skip":
        return '<span class="tdot skip">\u25cb</span>'
    return '<span class="tdot pass">\u2713</span>'


def render_tests() -> str:
    m = tests_model()
    summary = m["summary"]
    runner = esc(str(summary.get("runner", "GUT")))
    run_status = str(summary.get("status", "unknown"))
    stamp = esc(str(summary.get("timestamp_utc", "")))
    ran = summary.get("scripts_ran")
    expected = summary.get("scripts_expected")

    if not m["available"]:
        detail = esc(m["parse_error"]) if m["parse_error"] else \
            "No build/validation/gut.xml found. Run scripts/run_gut_validation.sh to generate it."
        body_html = f'<div class="sourcewarn">Test results unavailable: {detail}</div>'
    else:
        status_class = "ok" if run_status == "passed" else "bad"
        status_line = (
            f'<div class="trunbar {status_class}">Runner <b>{runner}</b> \u00b7 '
            f'last result <b>{esc(run_status)}</b>'
        )
        if ran is not None and expected is not None:
            status_line += f' \u00b7 {esc(str(ran))}/{esc(str(expected))} scripts ran'
        if stamp:
            status_line += f' \u00b7 {stamp}'
        status_line += '</div>'

        suites_html = ""
        for s in m["suites"]:
            open_attr = " open" if s["failures"] else ""
            badge_cls = "bad" if s["failures"] else "ok"
            badge_txt = (f'{s["failures"]} failed / {s["tests"]}'
                         if s["failures"] else f'{s["tests"]} passed')
            rows = ""
            for c in s["cases"]:
                msg = f'<div class="tmsg">{esc(c["message"])}</div>' if c["message"] else ""
                rows += (
                    f'<div class="trow {c["status"]}">{_tdot(c["status"])}'
                    f'<span class="tname">{esc(c["name"])}</span>'
                    f'<span class="ttime">{c["time"]:.3f}s</span>{msg}</div>'
                )
            skip_txt = f' \u00b7 {s["skipped"]} skipped' if s["skipped"] else ""
            suites_html += (
                f'<details class="suite"{open_attr}><summary>'
                f'<span class="sbadge {badge_cls}">{esc(badge_txt)}{skip_txt}</span>'
                f'<span class="sname">{esc(s["name"])}</span>'
                f'<span class="ttime">{s["time"]:.2f}s</span></summary>{rows}</details>'
            )

        body_html = (
            status_line
            + '<div class="tsummary">'
            + f'<div class="tstat total"><div class="num">{m["total"]}</div><div class="lbl">Tests</div></div>'
            + f'<div class="tstat pass"><div class="num">{m["passed"]}</div><div class="lbl">Passed</div></div>'
            + f'<div class="tstat fail"><div class="num">{m["failed"]}</div><div class="lbl">Failed</div></div>'
            + f'<div class="tstat skip"><div class="num">{m["skipped"]}</div><div class="lbl">Skipped</div></div>'
            + '</div>'
            + f'<div class="suites">{suites_html}</div>'
        )

    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="30"><title>Project0 \u2014 Tests</title>
<style>{EXEC_CSS}{TESTS_CSS}</style></head><body>
<header>
  <div><h1>Project0 \u2014 Tests</h1><div class="sub">Every automated test and its last recorded result \u00b7 build/validation/gut.xml \u00b7 auto-refreshes</div></div>
  <div class="nav"><a href="/">Reality</a><a href="/detail">Detailed</a><a class="on" href="/tests">Tests</a></div>
</header>
<main>
  <section class="sec">{body_html}</section>
</main></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        restart_if_source_changed()
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/health":
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        elif path in ("/", "/index.html"):
            view = "working" if parse_qs(parsed.query).get("view", [""])[0] == "working" else "committed"
            body = render_exec(view).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        elif path == "/detail":
            view = "working" if parse_qs(parsed.query).get("view", [""])[0] == "working" else "committed"
            body = render(view).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        elif path == "/tests":
            body = render_tests().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        else:
            body = b"not found"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
