#!/usr/bin/env python3
import html
import json
import os
import re
import sqlite3
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
# Slice 165 (telemetry map #282, decision #290): the game server's telemetry.db,
# read-only. Mounted separately from /repo (see deploy/compose.yml's dashboard
# service) since it lives in the game server's user:// data directory, not the
# repository checkout.
TELEMETRY_DB_PATH = os.environ.get("TELEMETRY_DB_PATH", "/gamedata/telemetry.db")
TELEMETRY_ROW_LIMIT = 200
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
                milestone = item.get("milestone") or {}
                issues.append({
                    "number": int(item.get("number", 0)),
                    "title": str(item.get("title", "")),
                    "url": str(item.get("html_url", "")),
                    "state": str(item.get("state", "open")),
                    "labels": [str(label.get("name", "")) for label in item.get("labels", []) if label.get("name")],
                    "body": str(item.get("body", "")),
                    "milestone_number": milestone.get("number"),
                    "milestone_title": str(milestone.get("title", "")),
                })
            if len(parsed) < 100:
                break
        issues.sort(key=lambda issue: issue["number"])
        data = {"available": True, "repo": GITHUB_REPO, "issues": issues, "error": ""}
    except Exception as exc:
        data = {"available": False, "repo": GITHUB_REPO, "issues": [], "error": str(exc)}
    _ISSUE_CACHE.update({"at": now, "data": data})
    return data


_MILESTONE_CACHE = {"at": 0.0, "data": {"available": False, "milestones": [], "error": "not loaded"}}


def github_milestones() -> dict:
    # Phases ("Phase N: <title>") live as GitHub milestones (2026-09-19
    # convention change, see issue #374); Outcomes are labels, not milestones.
    now = time.time()
    if now - float(_MILESTONE_CACHE["at"]) < GITHUB_ISSUE_CACHE_SECONDS:
        return _MILESTONE_CACHE["data"]
    try:
        milestones = []
        url = f"https://api.github.com/repos/{GITHUB_REPO}/milestones?state=all&per_page=100&sort=title&direction=asc"
        req = Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "project0-flow-dashboard"})
        with urlopen(req, timeout=5) as response:
            raw = response.read().decode("utf-8")
        for item in json.loads(raw):
            open_n = int(item.get("open_issues", 0))
            closed_n = int(item.get("closed_issues", 0))
            total = open_n + closed_n
            milestones.append({
                "number": int(item.get("number", 0)),
                "title": str(item.get("title", "")),
                "description": str(item.get("description", "")),
                "url": str(item.get("html_url", "")),
                "state": str(item.get("state", "open")),
                "open_issues": open_n,
                "closed_issues": closed_n,
                "percent": round(closed_n / total * 100) if total else 0,
            })
        milestones.sort(key=lambda ms: ms["title"])
        data = {"available": True, "repo": GITHUB_REPO, "milestones": milestones, "error": ""}
    except Exception as exc:
        data = {"available": False, "repo": GITHUB_REPO, "milestones": [], "error": str(exc)}
    _MILESTONE_CACHE.update({"at": now, "data": data})
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



def issue_covers_goal_target(issue: dict) -> bool:
    return bool(re.search(r"^Status:\s*(resolved|done|closed|accepted)\b", issue.get("body", ""), re.M | re.I))

def goal_good_looks_like(body: str) -> dict:
    match = re.search(r"^##\s+What Good Looks Like\s*\n+([\s\S]*?)(?=\n##\s|\Z)", body, re.M | re.I)
    if not match:
        return {"total": 0, "done": 0, "missing": True}
    total, done = 0, 0
    for line in match.group(1).splitlines():
        checked = re.match(r"^\s*-\s*\[([ xX])\]\s+\S+", line)
        bullet = re.match(r"^\s*-\s+\S+", line)
        if checked:
            total += 1
            if checked.group(1).lower() == "x":
                done += 1
        elif bullet:
            total += 1
    return {"total": total, "done": done, "missing": total == 0}


def _feature_resolved(feature: dict) -> bool:
    if feature.get("state") == "closed":
        return True
    return feature["slice_total"] > 0 and feature["slice_closed"] == feature["slice_total"]


def goal_wgl_feature_coverage(criteria: dict, features: list[dict]) -> dict:
    """A WGL item only counts as covered when >=1 Feature explicitly claims it
    ('Advances: #<goal issue> item <k>') and that Feature is actually resolved
    (closed, or every one of its Slices is closed) -- a hand-ticked checkbox
    with no Feature behind it is not evidence the gap closed."""
    total = criteria.get("total", 0)
    resolved_items: set[int] = set()
    claimed_items: set[int] = set()
    for feature in features:
        for _goal, item in re.findall(r"^Advances:\s*#(\d+)\s+item\s+(\d+)", feature.get("body", ""), re.M | re.I):
            item_num = int(item)
            claimed_items.add(item_num)
            if _feature_resolved(feature):
                resolved_items.add(item_num)
    percent = round(len(resolved_items) / total * 100) if total else 0
    return {"total": total, "resolved": len(resolved_items), "claimed": len(claimed_items), "percent": percent}


def goal_target_coverage(criteria: dict) -> int:
    total = criteria.get("total", 0)
    if total <= 0:
        return 0
    return round(criteria.get("done", 0) / total * 100)


def _parent_link(issue: dict, prefix: str) -> int | None:
    match = re.search(rf"^{prefix}:\s*#(\d+)\b", issue.get("body", ""), re.M)
    return int(match.group(1)) if match else None


def goal_feature_slices(issues: list[dict], goal_number: int) -> list[dict]:
    features = [
        issue for issue in issues
        if "Feature" in issue.get("labels", []) and _parent_link(issue, "Parent goal") == goal_number
    ]
    slices_by_feature: dict[int, list[dict]] = {}
    for issue in issues:
        if "Slice" not in issue.get("labels", []):
            continue
        parent = _parent_link(issue, "Parent feature")
        if parent is not None:
            slices_by_feature.setdefault(parent, []).append(issue)

    result = []
    for feature in features:
        slices = slices_by_feature.get(feature["number"], [])
        result.append({
            **feature,
            "slices": slices,
            "slice_total": len(slices),
            "slice_closed": sum(1 for s in slices if s.get("state") == "closed"),
        })
    result.sort(key=lambda f: (-f["slice_closed"], f["title"]))
    return result


def goal_issue_cards(issue_feed: dict) -> list[dict]:
    issues = issue_feed.get("issues", [])
    children_by_parent: dict[int, list[dict]] = {}
    for issue in issues:
        parent = _parent_link(issue, "Parent goal")
        if parent is None:
            continue
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
        criteria = goal_good_looks_like(issue.get("body", ""))
        features = goal_feature_slices(issues, issue["number"])
        wgl_coverage = goal_wgl_feature_coverage(criteria, features)
        # A Goal is only as done as its WGL items with a resolved Feature behind
        # them, never just because the Goal issue itself was closed or a
        # checkbox was hand-ticked with no Feature closing that gap.
        target_percent = wgl_coverage["percent"]
        cards.append({
            **issue,
            "child_total": total,
            "child_closed": github_closed,
            "child_open": open_count,
            "target_covered": covered,
            "target_percent": target_percent,
            "child_percent": child_percent,
            "criteria_total": criteria["total"],
            "criteria_done": criteria["done"],
            "criteria_missing": criteria["missing"],
            "wgl_resolved": wgl_coverage["resolved"],
            "wgl_claimed": wgl_coverage["claimed"],
            "percent": target_percent,
            "features": features,
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


def normalize_tracker_text(text: str) -> str:
    return text.replace("â€”", "—").replace("â€“", "–").replace("â€¦", "…")


def phase_progress_map(tracker: str) -> dict:
    tracker = normalize_tracker_text(tracker)
    out = {}
    for m in re.finditer(
        r"\*\*Phase (\d+)\s*(?:—|–|□|-)\s*([^*]+?)\*\*\s+Progress:\s*\*\*(\d+)%\*\*"
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
    nums = set()
    for line in tracker.splitlines():
        if re.match(r"^-\s*\*{0,2}(?:Current s|S)lices?:\*{0,2}", line):
            nums.update(int(n) for n in re.findall(r"\[(\d+)\s*[—-]", line))
    return nums


def slice_index_rows(tracker: str) -> list[dict]:
    tracker = normalize_tracker_text(tracker)
    # Walk the whole tracker, tracking phase context from both the work-index
    # (**Phase N — Title**) and slice-index (#### Phase N — Title) headers, and
    # collect every Slice/Current slice entry deduped by number. A single
    # '- Current slices:' line may list many slices (each with its own
    # bracketed title/status), not just one.
    rows: dict[int, dict] = {}
    phase_num, phase_title, last = 0, "", None
    for line in tracker.splitlines():
        h = re.match(r"^#{3,4} Phase (\d+)\s*[—-]\s*(.+)$", line) or re.match(r"^\*\*Phase (\d+)\s*[—-]\s*(.+?)\*\*", line)
        if h:
            phase_num, phase_title, last = int(h.group(1)), h.group(2).strip(), None
            continue
        if re.match(r"^-\s*\*{0,2}(?:Current s|S)lices?:\*{0,2}", line):
            for s in re.finditer(r"\[(\d+)\s*[—-]\s*([^\]]+)\]\([^)]*\)(?:\s*[—-]\s*\*\*([^*]+)\*\*)?", line):
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


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def card(title: str, body: str, css: str = "") -> str:
    return f'<article class="card {css}"><h3>{esc(title)}</h3><p>{esc(body)}</p></article>'


# Phase = GitHub milestone ("Phase N: <title>"), Outcome = GitHub label
# ("Outcome: <name>", renamed from the old Track A-F milestones). A phase's
# completion is the fraction of the Outcomes touching it that are fully
# closed (every Outcome-labeled issue across the repo, not just this phase),
# per the 2026-09-19 convention change recorded on issue #374.
def outcome_completion(issue_feed: dict) -> dict[str, dict]:
    by_label: dict[str, list[dict]] = {}
    for issue in issue_feed.get("issues", []):
        for label in issue["labels"]:
            if label.startswith("Outcome:"):
                by_label.setdefault(label, []).append(issue)
    return {
        label: {
            "total": len(issues),
            "closed": sum(1 for i in issues if i["state"] == "closed"),
            "complete": all(i["state"] == "closed" for i in issues),
        }
        for label, issues in by_label.items()
    }


def phase_milestones(issue_feed: dict) -> list[dict]:
    ms_feed = github_milestones()
    outcomes = outcome_completion(issue_feed)
    by_ms: dict[int, list[dict]] = {}
    for issue in issue_feed.get("issues", []):
        n = issue.get("milestone_number")
        if n:
            by_ms.setdefault(n, []).append(issue)

    phases = []
    for ms in ms_feed.get("milestones", []):
        m = re.match(r"^Phase (\d+):\s*(.+)$", ms["title"])
        if not m:
            continue
        issues = sorted(by_ms.get(ms["number"], []), key=lambda i: i["number"])
        touching = sorted({label for i in issues for label in i["labels"] if label.startswith("Outcome:")})
        complete = sum(1 for label in touching if outcomes[label]["complete"])
        phases.append({
            "num": int(m.group(1)), "title": m.group(2), "url": ms["url"],
            "issues": issues, "outcomes": touching, "outcome_completion": outcomes,
            "outcomes_complete": complete, "outcomes_total": len(touching),
            "pct": round(complete / len(touching) * 100) if touching else ms["percent"],
        })
    phases.sort(key=lambda p: p["num"])
    return phases


def render_vision(view: str = "committed") -> str:
    """Detailed view: the charter/vision narrative plus every Goal's real,
    live Goal->Feature->Slice progress (no more hardcoded Track A-F letters
    or stale Outcome-label matching)."""
    issue_feed = github_issues()
    issues_html, issue_status, goal_cards = goal_cards_section(issue_feed)
    other = "?view=working" if view != "working" else "?view=committed"
    other_lbl = "Working tree" if view != "working" else "Committed"

    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="30"><title>Project0 \u2014 Vision &amp; Roadmap</title>
<style>{EXEC_CSS}{VISION_CSS}</style></head><body>
<header>
  <div><h1>Project0 \u2014 Vision &amp; Roadmap</h1><div class="sub">Build a world worth changing \u00b7 {issue_status}</div></div>
  <div class="nav"><a href="/">Reality</a><a class="on" href="/detail">Detailed</a><a href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a href="/detail{other}">{esc(other_lbl)}</a></div>
</header>
<main>
  <section class="vhero">
    <article class="vstatement"><h2>The world is not only generated for players to visit.</h2>
      <p>It is a foundation they can explore, alter, inhabit, build upon, and eventually help govern.
      Meaning comes from the DM Guild; truth comes from deterministic, authoritative execution.</p>
      <span class="vsource">Technology-neutral charter \u00b7 <a href="https://github.com/{esc(issue_feed["repo"])}/issues/495">Charter #495</a></span>
    </article>
    <aside class="vsignal">
      <div><div class="vlabel">Current planning signal</div><div class="vbig">{len(goal_cards)} goals</div>
      <p>One bounded proof comes first: two players solve a movement-based environmental puzzle,
      receive a meaningful item, and permanently change a shared location.</p></div>
      <span class="vsource">{issue_status}</span>
    </aside>
  </section>
  <section class="sec"><h2>Goals \u2192 Features \u2192 Slices <span style="font-weight:400;text-transform:none;letter-spacing:0">\u00b7 live from GitHub, see docs/DEVELOPMENT-WORKFLOW.md#goal-feature-and-slice-semantics-2026-09-20</span></h2>
    <div class="issues">{issues_html}</div></section>
  <section class="sec vtwo">
    <article class="vpanel"><h3>Next proof</h3><p>The Vision-to-Play vertical slice is the bridge from charter to playable evidence.</p>
      <ul><li>Two Characters form a Party.</li><li>Players use traversal to solve one shared puzzle.</li>
      <li>The authoritative server grants one reward.</li><li>A later revisit exposes the accepted world mutation.</li></ul></article>
    <article class="vpanel"><h3>Delivery order</h3>
      <ul><li>Trusted client and runtime evidence already in flight.</li>
      <li>Telemetry identity and persistence for useful evidence.</li>
      <li>Party, traversal, blueprint, reward, and mutation contracts.</li>
      <li>Content and crafting foundations.</li><li>DM Guild, semantic builders, then player construction.</li>
      <li>Scale only when measured evidence demands it.</li></ul></article>
  </section>
  <div class="footer">Roadmap is a planning surface, not an implementation claim. \u00b7 Refreshes every 30 seconds \u00b7 {esc(issue_feed["repo"])}</div>
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


def executive_model(reader, phase_outcomes: dict[int, dict] | None = None) -> dict:
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
    slice_counts: dict[int, dict[str, int]] = {}
    for row in rows:
        counts = slice_counts.setdefault(row["phase_num"], {"total": 0, "delivered": 0})
        counts["total"] += 1
        counts["delivered"] += 1 if row["done"] else 0
    phases = []
    for n, meta in sorted(prog.items()):
        counts = slice_counts.get(n, {"total": 0, "delivered": 0})
        outcome = (phase_outcomes or {}).get(n)
        pct = outcome["pct"] if outcome else meta["progress"]
        phases.append({"num": n, "title": meta["title"], "pct": pct,
                       "status": status_by_num.get(n, ""),
                       "slice_total": counts["total"],
                       "slice_delivered": counts["delivered"],
                       "outcomes_complete": outcome["outcomes_complete"] if outcome else None,
                       "outcomes_total": outcome["outcomes_total"] if outcome else None})
    # Weight overall completion by tracked phase items.
    done_items = sum(m["done_items"] for m in prog.values() if m.get("done_items") is not None)
    total_items = sum(m["total_items"] for m in prog.values() if m.get("total_items") is not None)
    if total_items:
        overall = round(done_items / total_items * 100)
    else:
        overall = round(sum(p["pct"] for p in phases) / len(phases)) if phases else 0

    # Focus = the current, not-yet-done slice of each still-unfinished phase.
    focus, seen = [], set()
    for r in rows:
        pn = r["phase_num"]
        meta = prog.get(pn) or {}
        pct = meta.get("progress")
        if r["num"] not in currents or pct is None or pct >= 100 or pn in seen or r["done"]:
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
.phase-slices{color:var(--muted);font-size:10px;margin-left:6px}
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
.issue-block{display:flex;flex-direction:column;gap:6px}
.gfeatures{display:flex;flex-direction:column;gap:6px;background:var(--card);border:1px solid var(--line);border-left:5px solid var(--amber);border-radius:10px;padding:10px 14px}
.gfeature{display:flex;flex-direction:column;gap:4px;font-size:12px}
.gfeature>a{color:var(--text);text-decoration:none;font-weight:700}
.gfeature>a:hover{color:var(--cyan)}
.gfstats{color:var(--muted)}
.gslice{display:inline-block;margin-left:12px;color:var(--muted);text-decoration:none;font-size:11px;font-family:monospace}
.gslice:hover{color:var(--green)}
.charter-note{color:var(--muted);font-size:13px;max-width:900px;margin:6px 0 16px}
.charter-note a{color:var(--cyan);text-decoration:none}
.charter-note a:hover{text-decoration:underline}
.sourcewarn{background:#332619;border:1px solid var(--amber);color:#ffe0a0;border-radius:10px;padding:12px 14px}
.legend{display:flex;gap:18px;font-size:11px;color:var(--muted);margin-top:14px;flex-wrap:wrap}
.legend span{display:inline-flex;align-items:center;gap:6px}
.legend i{width:11px;height:11px;border-radius:3px;display:inline-block}
.empty{color:var(--muted)}
.stamp{color:var(--muted);font-size:11px}
@media(max-width:760px){.hero{grid-template-columns:1fr}.tiles{grid-template-columns:1fr}.brow{grid-template-columns:1fr auto}.brow .track{grid-column:1/-1;order:3}}
"""

VISION_CSS = """
.vhero{display:grid;grid-template-columns:1.15fr .85fr;gap:20px;align-items:stretch;margin-bottom:22px}
.vstatement,.vpanel{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:22px}
.vstatement{border-top:3px solid var(--cyan)}
.vstatement h2{margin:0;font-size:24px;font-weight:400}
.vstatement p{margin-top:12px;color:var(--muted)}
.vsignal{display:flex;flex-direction:column;justify-content:space-between;padding:22px;background:var(--card);border:1px solid var(--line);border-radius:10px}
.vlabel{font:700 11px/1.2 system-ui,sans-serif;letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}
.vbig{font:400 42px/1.1 system-ui,sans-serif;color:var(--cyan);margin-top:6px}
.vsignal p{color:var(--muted);margin-top:8px}
.vsource{display:inline-block;margin-top:16px;font-size:11px;color:var(--green)}
.vsource a{color:var(--cyan)}
.vtwo{display:grid;grid-template-columns:1fr 1fr;gap:20px}
.vpanel h3{margin:0 0 8px}
.vpanel ul{margin:0;padding-left:18px;color:var(--muted)}
.vpanel li{margin:6px 0}
.footer{color:var(--muted);font-size:12px;margin-top:26px;text-align:center}
@media(max-width:900px){.vhero,.vtwo{grid-template-columns:1fr}}
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


def phase_activity_label(phase: dict) -> str:
    bits = []
    if phase["slice_total"]:
        bits.append(f'{phase["slice_delivered"]}/{phase["slice_total"]} slices delivered')
    if phase.get("outcomes_total"):
        bits.append(f'{phase["outcomes_complete"]}/{phase["outcomes_total"]} outcomes')
    return f' <span class="phase-slices">{" \u00b7 ".join(bits)}</span>' if bits else ""


def _goal_coverage_label(issue: dict) -> str:
    return f'Feature-backed coverage: {issue["wgl_resolved"]}/{issue["criteria_total"]} "What Good Looks Like" items'


def _feature_slice_html(card: dict) -> str:
    if not card["features"]:
        return ""
    rows = "".join(
        f'<div class="gfeature"><a href="{esc(feature["url"])}">#{feature["number"]} {esc(_exec_short(feature["title"], 40))}</a>'
        f'<span class="gfstats">{feature["slice_closed"]}/{feature["slice_total"]} slices closed</span>'
        + "".join(
            f'<a class="gslice" href="{esc(s["url"])}">#{s["number"]} {"\u2713" if s.get("state") == "closed" else "\u25cb"} {esc(_exec_short(s["title"], 34))}</a>'
            for s in feature["slices"]
        )
        + "</div>"
        for feature in card["features"]
    )
    return f'<div class="gfeatures">{rows}</div>'


def goal_cards_section(issue_feed: dict) -> tuple[str, str, list[dict]]:
    """Renders the Goal->Feature->Slice cards shared by the Reality and Detailed views."""
    goal_cards = goal_issue_cards(issue_feed)
    open_goal_children = sum(goal["child_open"] for goal in goal_cards)
    if not issue_feed["available"]:
        issues_html = f'<div class="sourcewarn">GitHub issues unavailable: {esc(issue_feed["error"])}</div>'
        issue_status = f'GitHub issues unavailable for {esc(issue_feed["repo"])}'
        return issues_html, issue_status, goal_cards

    issues_html = "".join(
        f'<div class="issue-block">'
        f'<a class="issue" href="{esc(issue["url"])}"><div class="inum">#{issue["number"]}</div>'
        f'<div class="ititle">{esc(issue["title"])}</div>'
        f'<div class="gstats"><span>{_goal_coverage_label(issue)}</span>'
        f'<span class="gdone">{issue["target_percent"]}%</span></div>'
        f'<div class="gbar"><i style="width:{issue["target_percent"]}%"></i></div>'
        f'<div class="labels">{("<span class=\"label\">criteria missing</span>" if issue["criteria_missing"] else "")}<span class="label">{issue["wgl_claimed"]}/{issue["criteria_total"]} items claimed by a Feature</span><span class="label">known child coverage {issue["target_covered"]}/{issue["child_total"]}</span><span class="label">{issue["child_closed"]} closed</span><span class="label">{issue["child_open"]} open</span>'
        f'{"".join(f"<span class=\"label\">{esc(label)}</span>" for label in issue["labels"])}'
        f'</div></a>'
        f'{_feature_slice_html(issue)}'
        f'</div>'
        for issue in goal_cards
    ) or '<p class="empty">No Goal issues found.</p>'
    issue_status = f'{len(goal_cards)} goal issue(s), {open_goal_children} open child issue(s) from {esc(issue_feed["repo"])}'
    return issues_html, issue_status, goal_cards


def render_exec(view: str = "committed") -> str:
    reader = read_repo_file if view == "working" else read_committed_file
    issue_feed = github_issues()
    phase_outcomes = {p["num"]: p for p in phase_milestones(issue_feed)}
    m = executive_model(reader, phase_outcomes)
    all_issues = issue_feed["issues"]
    open_issues = [issue for issue in all_issues if issue.get("state") == "open"]
    issues_html, issue_status, goal_cards = goal_cards_section(issue_feed)
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
        f'<div class="brow"><div class="bl"><small>P{p["num"]:02d}</small>{esc(_exec_short(p["title"]))}'
        f'{phase_activity_label(p)}</div>'
        f'<div class="track"><i style="width:{p["pct"]}%;background:{_pcol(p["pct"])}"></i></div>'
        f'<div class="bp" style="color:{_pcol(p["pct"])}">{p["pct"]}%</div></div>'
        for p in m["phases"]
    )

    done_html = "".join(
        f'<span class="pill"><span class="dot">\u2713</span><small>{esc(f["id"])}</small>{esc(_exec_short(f["title"]))}</span>'
        for f in m["done"]
    ) or '<p class="empty">Nothing shipped yet.</p>'

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
  <div class="nav"><a class="on" href="/">Reality</a><a href="/detail">Detailed</a><a href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a href="/{other}">{esc(other_lbl)}</a></div>
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

    <section class="sec charter"><h2>Charter \u2192 Goal \u2192 Feature \u2192 Slice</h2>
    <p class="charter-note">Every Goal below must trace to and advance the master vision charter,
    <a href="https://github.com/{esc(issue_feed["repo"])}/issues/495">governing issue #495</a>.
    A Goal is its ideal, measurable condition; a Feature is the measurable gap between that ideal and
    today; a Slice is one root-cause step that closes part of that gap.</p>
    <div class="issues">{issues_html}</div></section>

  <section class="sec"><h2>\u25b6 Focused on now</h2><div class="focus">{focus_html}</div></section>

  <section class="sec"><h2>In progress \u2014 how far</h2><div class="bars">{active_html}</div></section>

  <section class="sec"><h2>Delivery by phase <span style="font-weight:400;text-transform:none;letter-spacing:0">\u00b7 active phases % from Outcome-label completion, see /detail</span></h2><div class="bars">{phase_html}</div>
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
  <div class="nav"><a href="/">Reality</a><a href="/detail">Detailed</a><a class="on" href="/tests">Tests</a><a href="/telemetry">Telemetry</a></div>
</header>
<main>
  <section class="sec">{body_html}</section>
</main></body></html>'''


TELEMETRY_CSS = """
.tform{display:flex;flex-wrap:wrap;gap:10px;align-items:end;margin-bottom:20px}
.tform label{display:flex;flex-direction:column;gap:4px;font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em}
.tform input,.tform select{background:var(--card);border:1px solid var(--line);color:var(--text);border-radius:6px;padding:7px 10px;font-size:13px}
.tform button{background:var(--cyan);color:#08121a;border:none;border-radius:6px;padding:8px 16px;font-weight:700;font-size:13px;cursor:pointer}
.ttable{width:100%;border-collapse:collapse;font-size:12px}
.ttable th{text-align:left;color:var(--muted);text-transform:uppercase;font-size:10px;letter-spacing:.06em;padding:8px 10px;border-bottom:1px solid var(--line)}
.ttable td{padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
.ttable td.payload{font-family:monospace;font-size:11px;color:var(--muted);max-width:420px;overflow-wrap:anywhere}
.ttable tr:hover{background:var(--card)}
"""


def _open_telemetry_db_readonly():
    """Opens TELEMETRY_DB_PATH strictly read-only (mode=ro): the dashboard has
    no write endpoint anywhere, and this page must not become the exception.
    Returns (connection, error_detail); connection is None on any failure.
    """
    if not Path(TELEMETRY_DB_PATH).exists():
        return None, f"No telemetry database found at {TELEMETRY_DB_PATH}."
    try:
        uri = f"file:{TELEMETRY_DB_PATH}?mode=ro"
        conn = sqlite3.connect(uri, uri=True)
        conn.row_factory = sqlite3.Row
        return conn, None
    except sqlite3.Error as exc:
        return None, f"Failed to open telemetry database: {exc}"


def telemetry_model(filters: dict) -> dict:
    """Slice 165 (telemetry map #282, decision #290): reads telemetry.db
    read-only and returns top-line counters plus a filtered raw-event page.
    `event_type` is discovered from the data (SELECT DISTINCT), never
    hardcoded, so this page needs no change when a new event family is added.
    """
    conn, error = _open_telemetry_db_readonly()
    if conn is None:
        return {"available": False, "error": error}
    try:
        total_rows = conn.execute("SELECT COUNT(*) AS n FROM events").fetchone()["n"]
        event_types = [r["event_type"] for r in conn.execute("SELECT DISTINCT event_type FROM events ORDER BY event_type")]
        counts_by_type = [
            dict(r) for r in conn.execute(
                "SELECT event_type, COUNT(*) AS n FROM events GROUP BY event_type ORDER BY n DESC"
            )
        ]

        clauses = []
        params: list = []
        if filters.get("event_type"):
            clauses.append("event_type = ?")
            params.append(filters["event_type"])
        if filters.get("account_id"):
            clauses.append("account_id = ?")
            params.append(filters["account_id"])
        if filters.get("peer_id"):
            clauses.append("peer_id = ?")
            params.append(filters["peer_id"])
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        rows = [
            dict(r) for r in conn.execute(
                f"SELECT id, event_type, schema_version, emitted_at_unix, server_tick, peer_id, "
                f"account_id, character_id, payload FROM events {where} "
                f"ORDER BY id DESC LIMIT ?",
                (*params, TELEMETRY_ROW_LIMIT),
            )
        ]
        return {
            "available": True,
            "total_rows": total_rows,
            "row_ceiling": 2000000,
            "event_types": event_types,
            "counts_by_type": counts_by_type,
            "rows": rows,
        }
    except sqlite3.Error as exc:
        return {"available": False, "error": f"Query failed: {exc}"}
    finally:
        conn.close()


def render_telemetry(filters: dict) -> str:
    m = telemetry_model(filters)

    if not m["available"]:
        body_html = f'<div class="sourcewarn">Telemetry unavailable: {esc(m["error"])}</div>'
    else:
        pct = round(m["total_rows"] / m["row_ceiling"] * 100, 2) if m["row_ceiling"] else 0
        tiles = (
            f'<div class="tile"><div class="num">{m["total_rows"]}</div><div class="lbl">Total events</div></div>'
            f'<div class="tile"><div class="num">{len(m["event_types"])}</div><div class="lbl">Event types</div></div>'
            f'<div class="tile"><div class="num">{pct}%</div><div class="lbl">Of row ceiling</div></div>'
        )
        counts_html = "".join(
            f'<span class="pill">{esc(c["event_type"])}<small>{c["n"]}</small></span>' for c in m["counts_by_type"]
        ) or '<p class="empty">No events recorded yet</p>'

        type_options = "".join(
            f'<option value="{esc(t)}"{" selected" if filters.get("event_type") == t else ""}>{esc(t)}</option>'
            for t in m["event_types"]
        )
        form_html = (
            '<form class="tform" method="get" action="/telemetry">'
            f'<label>Event type<select name="event_type"><option value="">All</option>{type_options}</select></label>'
            f'<label>Account ID<input name="account_id" value="{esc(filters.get("account_id", ""))}"></label>'
            f'<label>Peer ID<input name="peer_id" value="{esc(filters.get("peer_id", ""))}"></label>'
            '<button type="submit">Filter</button>'
            '</form>'
        )

        rows_html = "".join(
            '<tr>'
            f'<td>{r["id"]}</td>'
            f'<td>{esc(r["event_type"])}</td>'
            f'<td>{r["emitted_at_unix"]}</td>'
            f'<td>{r["server_tick"]}</td>'
            f'<td>{r["peer_id"]}</td>'
            f'<td>{esc(r["character_id"] or "")}</td>'
            f'<td class="payload">{esc(r["payload"])}</td>'
            '</tr>'
            for r in m["rows"]
        ) or '<tr><td colspan="7" class="empty">No matching events</td></tr>'
        table_html = (
            f'<table class="ttable"><thead><tr><th>ID</th><th>Event type</th><th>Emitted (unix)</th>'
            f'<th>Tick</th><th>Peer</th><th>Character</th><th>Payload</th></tr></thead>'
            f'<tbody>{rows_html}</tbody></table>'
        )
        body_html = (
            f'<div class="tiles">{tiles}</div>'
            f'<div class="pills" style="margin:16px 0">{counts_html}</div>'
            f'{form_html}{table_html}'
        )

    return f'''<!doctype html>
<html><head><meta charset="utf-8"><title>Project0 — Telemetry</title>
<style>{EXEC_CSS}{TELEMETRY_CSS}</style></head><body>
<header>
  <div><h1>Project0 — Telemetry</h1><div class="sub">Client interactions, connections, and combat outcomes · telemetry.db · query on demand</div></div>
  <div class="nav"><a href="/">Reality</a><a href="/detail">Detailed</a><a href="/tests">Tests</a><a class="on" href="/telemetry">Telemetry</a></div>
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
            body = render_vision(view).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        elif path == "/tests":
            body = render_tests().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        elif path == "/telemetry":
            query = parse_qs(parsed.query)
            filters = {
                "event_type": query.get("event_type", [""])[0].strip(),
                "account_id": query.get("account_id", [""])[0].strip(),
                "peer_id": query.get("peer_id", [""])[0].strip(),
            }
            body = render_telemetry(filters).encode("utf-8")
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
