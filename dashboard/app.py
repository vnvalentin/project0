#!/usr/bin/env python3
import html
import json
import os
import re
import sqlite3
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
# Optional: authenticated requests get 5000/hr instead of the 60/hr GitHub
# gives anonymous REST calls from a single IP, which the dashboard alone can
# exhaust after a few container restarts clear its in-memory cache.
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "") or os.environ.get("GH_TOKEN", "")
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


def github_issues() -> dict:
    now = time.time()
    if now - float(_ISSUE_CACHE["at"]) < GITHUB_ISSUE_CACHE_SECONDS:
        return _ISSUE_CACHE["data"]
    try:
        issues = []
        for page in range(1, 6):
            url = f"https://api.github.com/repos/{GITHUB_REPO}/issues?state=all&per_page=100&page={page}"
            headers = {"Accept": "application/vnd.github+json", "User-Agent": "project0-flow-dashboard"}
            if GITHUB_TOKEN:
                headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"
            req = Request(url, headers=headers)
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
                    "assignees": [str(a.get("login", "")) for a in item.get("assignees", []) if a.get("login")],
                    "body": str(item.get("body", "")),
                    "updated_at": str(item.get("updated_at", "")),
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


def goal_wgl_items(body: str) -> list[str]:
    """The Goal's capability breakdown items in order, 1-based position == the 'item
    <n>' a Feature's 'Advances:' line refers to."""
    match = re.search(r"^##\s+What Good Looks Like\s*\n+([\s\S]*?)(?=\n##\s|\Z)", body, re.M | re.I)
    if not match:
        return []
    items = []
    for line in match.group(1).splitlines():
        checked = re.match(r"^\s*-\s*\[([ xX])\]\s+(.+)$", line)
        bullet = re.match(r"^\s*-\s+(.+)$", line) if not checked else None
        if checked:
            items.append(checked.group(2).strip())
        elif bullet:
            items.append(bullet.group(1).strip())
    return items


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
    return {"total": total, "resolved": len(resolved_items), "claimed": len(claimed_items), "percent": percent,
            "resolved_items": resolved_items, "claimed_items": claimed_items}


def goal_target_coverage(criteria: dict) -> int:
    total = criteria.get("total", 0)
    if total <= 0:
        return 0
    return round(criteria.get("done", 0) / total * 100)


def _parent_link(issue: dict, prefix: str) -> int | None:
    match = re.search(rf"^{prefix}:\s*#(\d+)\b", issue.get("body", ""), re.M | re.I)
    return int(match.group(1)) if match else None


def _parent_link_any(issue: dict, prefixes: list[str]) -> int | None:
    for prefix in prefixes:
        parent = _parent_link(issue, prefix)
        if parent is not None:
            return parent
    return None


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
        wgl_texts = goal_wgl_items(issue.get("body", ""))
        features = goal_feature_slices(issues, issue["number"])
        wgl_coverage = goal_wgl_feature_coverage(criteria, features)
        # A Goal is only as done as its WGL items with a resolved Feature behind
        # them, never just because the Goal issue itself was closed or a
        # checkbox was hand-ticked with no Feature closing that gap.
        target_percent = wgl_coverage["percent"]
        unclaimed_items = [text for i, text in enumerate(wgl_texts, start=1) if i not in wgl_coverage["claimed_items"]]
        unresolved_claimed_items = [
            text for i, text in enumerate(wgl_texts, start=1)
            if i in wgl_coverage["claimed_items"] and i not in wgl_coverage["resolved_items"]
        ]
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
            "unclaimed_items": unclaimed_items,
            "unresolved_claimed_items": unresolved_claimed_items,
            "percent": target_percent,
            "features": features,
        })
    cards.sort(key=lambda card: (-card["percent"], card["title"]))
    return cards


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def render_vision(view: str = "committed") -> str:
    """Detailed view: the vision narrative plus every Goal's real,
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
    <div class="nav"><a href="/">Overview</a><a class="on" href="/detail">Detailed</a><a href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a href="/tbp">TBP View</a><a href="/roadmap">Roadmap</a><a href="/detail{other}">{esc(other_lbl)}</a></div>
</header>
<main>
  <section class="vhero">
    <article class="vstatement"><h2>The world is not only generated for players to visit.</h2>
      <p>It is a foundation they can explore, alter, inhabit, build upon, and eventually help govern.
      Meaning comes from the DM Guild; truth comes from deterministic, authoritative execution.</p>
      <span class="vsource">Technology-neutral vision · <a href="https://github.com/{esc(issue_feed["repo"])}/issues/495">Vision #495</a></span>
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
    <article class="vpanel"><h3>Next proof</h3><p>The Vision-to-Play vertical slice is the bridge from vision to playable evidence.</p>
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

OVERVIEW_CSS = """
.northstar{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:24px 28px}
.charter-text{font-size:17px;line-height:1.6;color:var(--text);max-width:900px;margin:0}
.charter-link{display:inline-block;margin-top:14px;color:var(--cyan);text-decoration:none;font-size:13px}
.charter-link:hover{text-decoration:underline}
.roadmap-track{display:grid;grid-template-columns:repeat(5,minmax(150px,1fr));gap:0;align-items:stretch}
.roadmap-node{position:relative;background:var(--card);border:1px solid var(--line);border-top:4px solid var(--grey);padding:14px 14px 16px;min-height:190px}
.roadmap-node:not(:last-child){border-right:0}
.roadmap-node:not(:last-child)::after{content:'\25B6';position:absolute;z-index:1;right:-10px;top:18px;color:var(--cyan);font-size:13px;background:var(--panel);padding:2px 3px}
.roadmap-node.active{border-top-color:var(--amber)}
.roadmap-node.follow{border-top-color:var(--cyan)}
.roadmap-node.deck{border-top-color:var(--green)}
.roadmap-node.fog{border-top-color:var(--grey)}
.roadmap-horizon{color:var(--muted);font-size:10px;font-weight:800;letter-spacing:.1em;text-transform:uppercase}
.roadmap-title{font-size:14px;font-weight:800;line-height:1.3;margin:8px 0 10px}
.roadmap-outcome{color:var(--muted);font-size:12px;line-height:1.45;margin:0 0 12px}
.roadmap-issues{display:flex;flex-wrap:wrap;gap:5px}
.roadmap-expected{display:block;color:var(--text);font-size:11px;font-weight:800;margin:2px 0 7px}
.roadmap-issue{color:var(--text);text-decoration:none;background:#18232d;border:1px solid var(--line);border-radius:5px;padding:3px 6px;font-size:11px}
.roadmap-issue:hover{color:var(--cyan);border-color:var(--cyan)}
.roadmap-state{display:block;margin-top:10px;color:var(--muted);font-size:10px}
.roadmap-state-badge{display:inline-block;margin-top:8px;padding:3px 7px;border-radius:10px;font-size:10px;font-weight:800;letter-spacing:.03em;background:#232d38;color:var(--muted)}
.roadmap-state-badge.DONE{background:#123524;color:var(--green)}
.roadmap-state-badge.IN_PROGRESS{background:#123044;color:var(--cyan)}
.roadmap-state-badge.READY_TO_PULL{background:#3a2e13;color:var(--amber)}
.roadmap-state-badge.NEEDS_GRILLING{background:#3a2413;color:#f5b86a}
.roadmap-breakdown{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px}
.roadmap-breakdown section{min-width:0;border-top:1px solid var(--line);padding-top:7px}
.roadmap-breakdown h4{margin:0 0 5px;color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.08em}
.roadmap-breakdown ul{list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:5px}
.roadmap-breakdown li{font-size:10px;line-height:1.3}
.roadmap-breakdown a{color:var(--text);text-decoration:none}
.roadmap-breakdown a:hover{color:var(--cyan)}
.roadmap-breakdown small{display:block;color:var(--muted);font-size:9px;margin-top:2px}
.roadmap-undefined{color:var(--muted);font-style:italic}
.roadmap-evidence{margin-top:18px;padding:12px 14px;background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--cyan);color:var(--muted);font-size:12px;line-height:1.45}
.roadmap-evidence strong{color:var(--text)}
.goalrows{display:flex;flex-direction:column;gap:2px}
.goalrow{display:grid;grid-template-columns:1fr 140px 46px 110px 60px;gap:14px;align-items:center;padding:12px 14px;border-bottom:1px solid var(--line)}
.goalrow:first-child{border-top:1px solid var(--line)}
.gr-name{color:var(--text);text-decoration:none;font-size:14px}
.gr-name:hover{color:var(--cyan)}
.gr-bar{height:10px;background:#0e141b;border:1px solid var(--line);border-radius:6px;overflow:hidden}
.gr-bar>i{display:block;height:100%}
.gr-bar>i.done{background:var(--green)}
.gr-bar>i.progress{background:var(--amber)}
.gr-bar>i.notstarted,.gr-bar>i.notchartered{background:var(--grey)}
.gr-pct{font-size:13px;font-variant-numeric:tabular-nums;text-align:right;color:var(--muted)}
.gr-status{font-size:11px;padding:3px 9px;border-radius:12px;text-align:center;white-space:nowrap}
.gr-status.done{background:#123524;color:var(--green)}
.gr-status.progress{background:#3a2e13;color:var(--amber)}
.gr-status.notstarted,.gr-status.notchartered{background:#232d38;color:var(--muted)}
.gr-gaps{font-size:11px;color:var(--muted);text-align:right;white-space:nowrap}
.worklist{display:flex;flex-direction:column;gap:2px}
.workrow{display:flex;justify-content:space-between;align-items:center;gap:14px;padding:10px 14px;border-bottom:1px solid var(--line);font-size:13px}
.workrow:first-child{border-top:1px solid var(--line)}
.workrow a{color:var(--text);text-decoration:none}
.workrow a:hover{color:var(--cyan)}
.workrow .breadcrumb{color:var(--muted);font-size:12px;white-space:nowrap}
.gaplist{display:flex;flex-direction:column;gap:14px}
.gapblock{background:var(--card);border:1px solid var(--line);border-left:5px solid var(--grey);border-radius:10px;padding:14px 16px}
.gapblock>a{color:var(--text);text-decoration:none;font-weight:700;font-size:13px}
.gapblock>a:hover{color:var(--cyan)}
.gapblock ul{margin:8px 0 0;padding-left:18px;color:var(--muted);font-size:13px}
.gapblock li{margin:4px 0}
@media(max-width:760px){.goalrow{grid-template-columns:1fr;gap:6px}.gr-bar{order:3}.gr-pct,.gr-status,.gr-gaps{text-align:left}}
@media(max-width:1100px){.roadmap-track{grid-template-columns:repeat(3,minmax(180px,1fr));gap:10px}.roadmap-node:not(:last-child){border-right:1px solid var(--line)}.roadmap-node:not(:last-child)::after{display:none}}
@media(max-width:650px){.roadmap-track{grid-template-columns:1fr}.roadmap-node{min-height:0}.roadmap-node:not(:last-child){border-right:1px solid var(--line)}}
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


def goal_status(card: dict) -> tuple[str, str]:
    """(css class, label) for a Goal's status pill."""
    if card["criteria_total"] == 0:
        return "notchartered", "Not yet chartered"
    if card["percent"] == 100:
        return "done", "Done"
    if card["wgl_claimed"] > 0:
        return "progress", "In progress"
    return "notstarted", "Not started"


def active_work(issue_feed: dict, goal_cards: list[dict]) -> list[dict]:
    """Open Slices whose chain (Slice -> Feature -> Goal) is fully live-linked,
    newest-updated first -- this is 'what is being worked on right now'."""
    feature_by_number: dict[int, dict] = {}
    goal_by_feature: dict[int, dict] = {}
    for card in goal_cards:
        for feature in card["features"]:
            feature_by_number[feature["number"]] = feature
            goal_by_feature[feature["number"]] = card

    work = []
    for issue in issue_feed.get("issues", []):
        if "Slice" not in issue.get("labels", []) or issue.get("state") != "open":
            continue
        parent = _parent_link(issue, "Parent feature")
        if parent not in goal_by_feature:
            continue
        work.append({"slice": issue, "feature": feature_by_number[parent], "goal": goal_by_feature[parent]})
    work.sort(key=lambda w: w["slice"].get("updated_at", ""), reverse=True)
    return work


VISION_URL = "https://github.com/vnvalentin/project0/issues/495"
VISION_STATEMENT = (
    "Project0 is a persistent cooperative action-adventure in which players inhabit an "
    "evolving world, make consequential choices, solve problems with their own judgment, "
    "develop physically distinct Characters, form lasting Parties, build places of their "
    "own, and experience personal and shared stories shaped by a hierarchy of Dungeon "
    "Masters. The world is not only generated for players to visit \u2014 it is a foundation "
    "they can explore, alter, inhabit, build upon, and eventually help govern."
)

ROADMAP_PLAN = (
    {"horizon": "Active / Now", "class_name": "active", "title": "M0 · Refine the public seam", "issue_numbers": (571,), "outcome": "Align the supporting fixture to the player-triggered boundary flow."},
    {"horizon": "Fast Follower", "class_name": "follow", "title": "M1 · JIT generation + canon re-entry", "issue_numbers": (551,), "outcome": "A player crosses an unexplored boundary and later restores the same canonical sector."},
    {"horizon": "On-Deck", "class_name": "deck", "title": "M2 · Shared Lore convergence", "issue_numbers": (552,), "outcome": "Two clients and a late joiner converge on one authoritative Lore revision."},
    {"horizon": "On-Deck", "class_name": "deck", "title": "M3 · Procedural house geometry", "issue_numbers": (710,), "outcome": "Accepted house fields produce distinct deterministic runtime geometry."},
    {"horizon": "Future / Fog", "class_name": "fog", "title": "M4+ · Semantic world expansion", "issue_numbers": (964, 965, 966), "outcome": "Context bounds, POI Canon persistence, and proposal fallback become refined slices."},
)


def _roadmap_kind(issue: dict) -> str:
    labels = {str(label).lower() for label in issue.get("labels", [])}
    for kind, label in (("feature", "tbp:feature"), ("epic", "tbp:epic"), ("experiment", "tbp:experiment")):
        if label in labels:
            return kind
    title = issue.get("title", "").lower()
    return next((kind for kind in ("feature", "epic", "experiment") if title.startswith(kind + ":")), "issue")


def _roadmap_children(issue: dict, issues: list[dict]) -> list[dict]:
    kind = _roadmap_kind(issue)
    if kind == "feature":
        parent_prefix = "Parent feature"
        child_kind = "epic"
    elif kind == "epic":
        parent_prefix = "Parent epic"
        child_kind = "experiment"
    else:
        return []
    children = [candidate for candidate in issues
                if _roadmap_kind(candidate) == child_kind
                and _parent_link_any(candidate, [parent_prefix]) == issue.get("number")]
    return sorted(children, key=lambda candidate: candidate.get("number", 0))


def _roadmap_node(issue: dict, issues: list[dict]) -> dict:
    children = [_roadmap_node(child, issues) for child in _roadmap_children(issue, issues)]
    kind = _roadmap_kind(issue)
    classified_issue = {**issue, "type": issue.get("type", kind)}
    return {**classified_issue, "roadmap_kind": kind, "children": children,
            "tbp_state": classify_tbp_state(classified_issue, children)}


def _roadmap_ancestors(issue: dict, issues: list[dict]) -> list[dict]:
    ancestors = []
    current = issue
    parent_prefixes = {"experiment": ["Parent epic"], "epic": ["Parent feature"]}
    while _roadmap_kind(current) in parent_prefixes:
        parent_number = _parent_link_any(current, parent_prefixes[_roadmap_kind(current)])
        parent = next((candidate for candidate in issues if candidate.get("number") == parent_number), None)
        if parent is None:
            break
        ancestors.insert(0, _roadmap_node(parent, issues))
        current = parent
    return ancestors


def _roadmap_flatten(node: dict) -> list[dict]:
    return [node] + [child for child_node in node.get("children", []) for child in _roadmap_flatten(child_node)]


def _roadmap_issue_link(node: dict) -> str:
    state = node.get("tbp_state", "READY_TO_PULL")
    display_state = "READY" if state == "READY_TO_PULL" else state.replace("_", " ")
    return (f'<li><a href="{esc(node.get("url", ""))}">#{node["number"]} '
            f'{esc(node.get("title", ""))}</a><small>GitHub {esc(node.get("state", "open"))} · '
            f'<span class="roadmap-state-badge {state}">{display_state}</span></small></li>')


def _roadmap_breakdown(nodes: list[dict]) -> str:
    by_kind = {kind: [node for node in nodes if node.get("roadmap_kind") == kind]
               for kind in ("feature", "epic", "experiment")}
    sections = []
    for kind, label in (("feature", "Feature"), ("epic", "Epic"), ("experiment", "Experiment")):
        entries = "".join(_roadmap_issue_link(node) for node in by_kind[kind])
        if not entries:
            entries = f'<li class="roadmap-undefined">No linked {label}s defined yet</li>'
        sections.append(f'<section><h4>{label}</h4><ul>{entries}</ul></section>')
    return f'<div class="roadmap-breakdown">{"".join(sections)}</div>'


def roadmap_html(issue_feed: dict) -> str:
    """Render the rolling horizon from live GitHub issue records."""
    issues_by_number = {issue["number"]: issue for issue in issue_feed.get("issues", [])}
    rendered_nodes = []
    for stage in ROADMAP_PLAN:
        links = []
        states = []
        breakdown_nodes = []
        expected_label = "Expected issue" if len(stage["issue_numbers"]) == 1 else "Expected issues"
        for number in stage["issue_numbers"]:
            issue = issues_by_number.get(number)
            if issue is None:
                links.append(f'<span class="roadmap-issue">#{number} unavailable</span>')
                states.append("missing from feed")
                continue
            node = _roadmap_node(issue, list(issues_by_number.values()))
            ancestors = _roadmap_ancestors(issue, list(issues_by_number.values()))
            hierarchy_nodes = ancestors + _roadmap_flatten(node)
            breakdown_nodes.extend(hierarchy_nodes)
            state = node["tbp_state"]
            links.append(f'<a class="roadmap-issue" href="{esc(issue["url"])}">#{number} {esc(issue.get("title", ""))}</a>')
            display_state = "READY" if state == "READY_TO_PULL" else state.replace("_", " ")
            states.append(f"GitHub {issue.get('state', 'open').lower()} · TBP {display_state}")
        rendered_nodes.append(
            f'<article class="roadmap-node {stage["class_name"]}">'
            f'<div class="roadmap-horizon">{esc(stage["horizon"])}</div>'
            f'<div class="roadmap-title">{esc(stage["title"])}</div>'
            f'<p class="roadmap-outcome">{esc(stage["outcome"])}</p>'
            f'<div class="roadmap-expected">{expected_label}</div>'
            f'<div class="roadmap-issues">{"".join(links)}</div>'
            f'<span class="roadmap-state">{esc("; ".join(states))}</span>'
            f'{_roadmap_breakdown(breakdown_nodes)}'
            f'</article>'
        )
    source_note = "Live issue state and links are resolved from GitHub."
    if not issue_feed.get("available"):
        source_note = f'GitHub issue feed unavailable: {issue_feed.get("error", "unknown error")}'
    return (
        f'<div class="roadmap-track">{"".join(rendered_nodes)}</div>'
        f'<div class="roadmap-evidence"><strong>Milestone 1 proof:</strong> '
        f'player boundary crossing → async generation → blueprint validation → '
        f'Canon commit → visible sector → stable re-entry. {esc(source_note)}</div>'
    )


def render_roadmap() -> str:
        """Render the rolling milestone map as its own live GitHub view."""
        issue_feed = github_issues()
        return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="60"><title>Project0 — Roadmap</title>
<style>{EXEC_CSS}{OVERVIEW_CSS}</style></head><body>
<header>
    <div><h1>Project0 — Roadmap</h1><div class="sub">Rolling delivery horizons from live GitHub Issues</div></div>
    <div class="nav"><a href="/">Overview</a><a href="/detail">Traceability</a><a href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a href="/tbp">TBP View</a><a class="on" href="/roadmap">Roadmap</a></div>
</header>
<main>
    <section class="sec">
        <h2>Plan at a glance</h2>
        <div class="roadmap-intro">Read left to right: the active refinement gate, the first playable proof, the next convergence step, and bounded future work.</div>
        {roadmap_html(issue_feed)}
    </section>
</main></body></html>'''


def render_overview(view: str = "committed") -> str:
    """The one page that answers: what's the goal, what's done, what's being
    worked on, and where the gaps are. Everything here is live from GitHub
    issues (Goals/Features/Slices) -- no repo-file parsing, no stale text."""
    issue_feed = github_issues()
    if not issue_feed["available"]:
        goal_cards, work = [], []
    else:
        goal_cards = goal_issue_cards(issue_feed)
        work = active_work(issue_feed, goal_cards)

    chartered = [c for c in goal_cards if c["criteria_total"] > 0]
    done = [c for c in chartered if c["percent"] == 100]
    in_progress = [c for c in chartered if c["percent"] < 100 and c["wgl_claimed"] > 0]
    not_started = [c for c in chartered if c["wgl_claimed"] == 0]
    total_items = sum(c["criteria_total"] for c in chartered)
    resolved_items = sum(c["wgl_resolved"] for c in chartered)
    overall_pct = round(resolved_items / total_items * 100) if total_items else 0

    goal_rows_html = "".join(
        f'<div class="goalrow">'
        f'<a class="gr-name" href="{esc(card["url"])}">{esc(_exec_short(card["title"].split("\u2014", 1)[-1].strip() or card["title"], 42))}</a>'
        f'<div class="gr-bar"><i class="{goal_status(card)[0]}" style="width:{card["percent"]}%"></i></div>'
        f'<span class="gr-pct">{card["percent"]}%</span>'
        f'<span class="gr-status {goal_status(card)[0]}">{goal_status(card)[1]}</span>'
        f'<span class="gr-gaps">{len(card["unclaimed_items"])} gap{"s" if len(card["unclaimed_items"]) != 1 else ""}</span>'
        f'</div>'
        for card in sorted(goal_cards, key=lambda c: (-c["percent"], c["title"]))
    ) or '<p class="empty">No Goals found.</p>'

    work_html = "".join(
        f'<div class="workrow">'
        f'<a href="{esc(w["slice"]["url"])}">#{w["slice"]["number"]} {esc(_exec_short(w["slice"]["title"], 52))}</a>'
        f'<span class="breadcrumb">{esc(_exec_short(w["goal"]["title"].split("\u2014", 1)[-1].strip(), 24))} '
        f'\u203a {esc(_exec_short(w["feature"]["title"], 30))}</span>'
        f'</div>'
        for w in work[:10]
    ) or '<p class="empty">Nothing currently in flight against a tracked Goal.</p>'

    gap_blocks = []
    for card in sorted(goal_cards, key=lambda c: -len(c["unclaimed_items"])):
        if not card["unclaimed_items"]:
            continue
        items_html = "".join(f'<li>{esc(item)}</li>' for item in card["unclaimed_items"])
        gap_blocks.append(
            f'<div class="gapblock"><a href="{esc(card["url"])}">{esc(_exec_short(card["title"].split("\u2014", 1)[-1].strip(), 40))}</a>'
            f'<ul>{items_html}</ul></div>'
        )
    gaps_html = "".join(gap_blocks) or '<p class="empty">Every chartered Goal item has at least one Feature.</p>'

    issue_status = (
        f'{len(chartered)} chartered goals \u00b7 {len(done)} done \u00b7 {len(in_progress)} in progress \u00b7 {len(not_started)} not started'
        if issue_feed["available"] else f'GitHub issues unavailable: {esc(issue_feed["error"])}'
    )

    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="60"><title>Project0</title>
<style>{EXEC_CSS}{OVERVIEW_CSS}</style></head><body>
<header>
  <div><h1>Project0</h1><div class="sub">{esc(issue_status)}</div></div>
    <div class="nav"><a class="on" href="/">Overview</a><a href="/detail">Traceability</a><a href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a href="/tbp">TBP View</a><a href="/roadmap">Roadmap</a></div>
</header>
<main>
  <section class="sec northstar">
    <h2>The Vision</h2>
    <p class="charter-text">{esc(VISION_STATEMENT)}</p>
    <a class="charter-link" href="{VISION_URL}">Read the full Vision (#495) →</a>
  </section>

    <section class="sec">
        <h2>Rolling milestone map</h2>
        <div class="roadmap-intro">Active work moves left to right; only the next cycle is fully committed, while later work stays progressively refined.</div>
        {roadmap_html(issue_feed)}
    </section>

  <section class="sec">
    <h2>Where things stand</h2>
    <div class="tiles">
      <div class="tile done"><div class="num">{overall_pct}%</div><div class="lbl">Overall progress</div></div>
      <div class="tile active"><div class="num">{len(in_progress)}</div><div class="lbl">Goals in progress</div></div>
      <div class="tile todo"><div class="num">{sum(len(c["unclaimed_items"]) for c in chartered)}</div><div class="lbl">Open gaps</div></div>
    </div>
  </section>

  <section class="sec">
    <h2>Goals \u2014 the ideal condition each one describes</h2>
    <div class="goalrows">{goal_rows_html}</div>
  </section>

  <section class="sec">
    <h2>Being worked on right now</h2>
    <div class="worklist">{work_html}</div>
  </section>

  <section class="sec">
    <h2>Where the gaps are \u2014 goal outcomes with no Feature yet</h2>
    <div class="gaplist">{gaps_html}</div>
  </section>

  <div class="footer">Live from GitHub Issues \u00b7 refreshes every 60 seconds \u00b7 <a href="/detail">full Goal/Feature/Slice traceability \u2192</a></div>
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
    <div class="nav"><a href="/">Reality</a><a href="/detail">Detailed</a><a class="on" href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a href="/tbp">TBP View</a><a href="/roadmap">Roadmap</a></div>
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
    <div class="nav"><a href="/">Reality</a><a href="/detail">Detailed</a><a href="/tests">Tests</a><a class="on" href="/telemetry">Telemetry</a><a href="/tbp">TBP View</a><a href="/roadmap">Roadmap</a></div>
</header>
<main>
  <section class="sec">{body_html}</section>
</main></body></html>'''


TBP_CSS = """
.tbp-layout{display:grid;grid-template-columns:1fr 340px;gap:20px;align-items:start}
.tbp-panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px 20px}
.tbp-badge{font-size:10px;font-weight:700;border-radius:12px;padding:3px 9px;white-space:nowrap;text-transform:uppercase;letter-spacing:.04em}
.tbp-badge.NEEDS_GRILLING{background:#3a2e13;color:var(--amber)}
.tbp-badge.READY_TO_PULL{background:#123524;color:var(--green)}
.tbp-badge.IN_PROGRESS{background:#12303a;color:var(--cyan);animation:tbp-pulse 1.6s ease-in-out infinite}
.tbp-badge.DONE{background:#232d38;color:var(--muted)}
@keyframes tbp-pulse{0%,100%{opacity:1}50%{opacity:.55}}
.tbp-legend{display:flex;flex-wrap:wrap;gap:12px;font-size:11px;color:var(--muted);margin-bottom:16px;padding-bottom:14px;border-bottom:1px solid var(--line)}
.tbp-row{display:flex;align-items:center;gap:10px;padding:6px 0}
.tbp-row a{color:var(--text);text-decoration:none;font-size:13px}
.tbp-row a:hover{color:var(--cyan)}
.tbp-goal{border-left:3px solid var(--line);padding-left:14px;margin-bottom:16px}
.tbp-goal>summary{cursor:pointer;list-style:none;display:flex;align-items:center}
.tbp-goal>summary::-webkit-details-marker{display:none}
.tbp-goal>summary::before{content:'\25B6';display:inline-block;flex:none;color:var(--muted);font-size:9px;margin-right:8px;transition:transform .15s}
.tbp-goal[open]>summary::before{transform:rotate(90deg)}
.tbp-children{margin-left:16px;border-left:1px dashed var(--line);padding-left:14px}
.tbp-slice{margin-left:16px}
.tbp-section{margin-bottom:22px}
.tbp-section h3{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:0 0 10px}
.tbp-card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px 12px;margin-bottom:6px;font-size:12px}
.tbp-card a{color:var(--text);text-decoration:none}
.tbp-card a:hover{color:var(--cyan)}
.tbp-hoshin{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--cyan);border-radius:12px;padding:16px 18px;margin-bottom:18px}
.tbp-hoshin>.tbp-row{padding-bottom:10px;border-bottom:1px solid var(--line);margin-bottom:14px}
.tbp-hoshin>.tbp-row a{font-size:15px;font-weight:700}
.tbp-theme-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px}
.tbp-theme-card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.tbp-theme-card>.tbp-goal{border-left:none;padding-left:0;margin-bottom:0}
.tbp-theme-card>.tbp-goal .tbp-row a{font-weight:700}
@media(max-width:900px){.tbp-layout{grid-template-columns:1fr}}
"""


TBP_STATE_ICON = {
    "NEEDS_GRILLING": "\U0001F7E1\U0001F525",  # yellow circle + flame
    "READY_TO_PULL": "\U0001F7E2\u25B6\uFE0F",  # green circle + play
    "IN_PROGRESS": "\U0001F535\U0001F501",  # blue circle + pulse/loop
    "DONE": "\u26AA\u2705",  # gray circle + check
}


def _tbp_outcomes(issue: dict) -> tuple[bool, bool]:
    """Return (has_required_outcomes, all_checked) for the canonical checklist."""
    import re
    body = issue.get("body") or ""
    match = re.search(r"(?ims)^##\s+Outcomes\s*$\n(.*?)(?=^##\s|\Z)", body)
    if not match:
        return False, False
    checks = re.findall(r"(?im)^\s*-\s+\[([ xX])\]\s+.+$", match.group(1))
    return bool(checks), bool(checks) and all(x.lower() == "x" for x in checks)


def _tbp_outcomes_satisfied(issue: dict) -> bool:
    has, complete = _tbp_outcomes(issue)
    if has:
        return complete
    labels = {str(x.get("name", x) if isinstance(x, dict) else x) for x in issue.get("labels", [])}
    body = issue.get("body") or ""
    if "tbp:theme" in labels:
        match = re.search(r"(?ims)^##\s+Measurable Outcome\s*$\n(.*?)(?=^##\s|\Z)", body)
        return bool(match and match.group(1).strip() and _tbp_declares_child_breakdown(issue))
    if "tbp:feature" in labels:
        match = re.search(r"(?ims)^##\s+Measurable (?:Component|Outcome)\s*$\n(.*?)(?=^##\s|\Z)", body)
        return bool(match and match.group(1).strip() and _tbp_declares_child_breakdown(issue))
    if "tbp:epic" in labels:
        match = re.search(r"(?ims)^##\s+Measurable Metric\s*$\n(.*?)(?=^##\s|\Z)", body)
        return bool(match and match.group(1).strip() and _tbp_declares_child_breakdown(issue))
    # Compatibility is deliberately limited to pre-contract closed records.
    return (issue.get("state") or "").lower() == "closed" and (issue.get("createdAt") or "9999") < "2025-01-01"


def _tbp_declares_child_breakdown(issue: dict) -> bool:
    import re
    labels = {str(x.get("name", x) if isinstance(x, dict) else x) for x in issue.get("labels", [])}
    section_pattern = (
        r"Features?" if "tbp:theme" in labels
        else r"Epics \(Gaps\)" if "tbp:feature" in labels
        else r"Experiments" if "tbp:epic" in labels
        else ""
    )
    if not section_pattern:
        return False
    body = issue.get("body") or ""
    match = re.search(rf"(?ims)^##\s+{section_pattern}\s*$\n(.*?)(?=^##\s|\Z)", body)
    return bool(match and re.search(r"(?im)^\s*-\s+(?:\[[ xX]\]\s+)?(?:.*#\d+|.*/issues/\d+)", match.group(1)))


def _tbp_theme_gap_is_covered(issue: dict) -> bool:
    import re
    body = issue.get("body") or ""
    outcome = re.search(r"(?ims)^##\s+Measurable Outcome\s*$\n(.*?)(?=^##\s|\Z)", body)
    return bool(outcome and outcome.group(1).strip() and _tbp_declares_child_breakdown(issue))


def _tbp_feature_measure_is_covered(issue: dict) -> bool:
    import re
    body = issue.get("body") or ""
    measure = re.search(r"(?ims)^##\s+Measurable (?:Component|Outcome)\s*$\n(.*?)(?=^##\s|\Z)", body)
    return bool(measure and measure.group(1).strip() and _tbp_declares_child_breakdown(issue))


def classify_tbp_state(issue: dict, children: list[dict] | None = None) -> str:
    """Classify one TBP node, applying the recursive child/outcome gate."""
    children = children or []
    child_states = [c.get("tbp_state") or classify_tbp_state(c) for c in children]
    labels = {str(x.get("name", x) if isinstance(x, dict) else x) for x in issue.get("labels", [])}
    # Themes require a Feature child, Features require an Epic child, and
    # Epics require an Experiment child.
    # A declared canonical child breakdown is sufficient when children are not
    # available in the current issue feed.
    if "tbp:theme" in labels and not _tbp_theme_gap_is_covered(issue):
        return "NEEDS_GRILLING"
    if "tbp:feature" in labels and not _tbp_feature_measure_is_covered(issue):
        return "NEEDS_GRILLING"
    if not children and labels & {"tbp:feature", "tbp:epic"} and not _tbp_declares_child_breakdown(issue):
        return "NEEDS_GRILLING"
    if any(x == "NEEDS_GRILLING" for x in child_states):
        return "NEEDS_GRILLING"
    if any(x == "IN_PROGRESS" for x in child_states):
        return "IN_PROGRESS"
    state = (issue.get("state") or "open").lower()
    if state == "closed":
        has_pass = any("pass" in line.lower() and "[x]" in line.lower() for line in (issue.get("body") or "").splitlines())
        return "DONE" if _tbp_outcomes_satisfied(issue) and (not issue.get("type") == "experiment" or has_pass) and all(x == "DONE" for x in child_states) else "NEEDS_GRILLING"
    if any(x not in ("DONE",) for x in child_states):
        return "READY_TO_PULL" if "tbp:in-progress" not in labels else "IN_PROGRESS"
    if "tbp:in-progress" in labels or "in progress" in {x.lower() for x in labels}:
        return "IN_PROGRESS"
    if "tbp:needs-grilling" in labels or "needs grilling" in {x.lower() for x in labels}:
        return "NEEDS_GRILLING"
    return "READY_TO_PULL"

def _tbp_row(issue: dict, children: list[dict] | None = None) -> str:
    state = classify_tbp_state(issue, children)
    return (
        f'<div class="tbp-row"><span class="tbp-badge {state}">{TBP_STATE_ICON[state]} {state.replace("_", " ")}</span>'
        f'<a href="{esc(issue["url"])}">#{issue["number"]} {esc(issue["title"])}</a></div>'
    )


def _tbp_render_node(node: dict, buckets: dict[str, list[dict]]) -> str:
    """Recursively render one node of the Hoshin->Theme->Feature->Epic->Experiment
    tree, bucketing every node it visits for the pipeline panel. Nodes with
    children (Themes, Features, and any Epic with linked Experiments) render as
    a collapsible <details> so a Theme's/Feature's subtree can be folded away."""
    children = node.get("children", [])
    state = classify_tbp_state(node, children)
    if state in buckets:
        buckets[state].append(node)
    children_html = "".join(_tbp_render_node(child, buckets) for child in children)
    if children_html:
        return f'<details class="tbp-goal"><summary>{_tbp_row(node, children)}</summary><div class="tbp-children">{children_html}</div></details>'
    return f'<div class="tbp-goal">{_tbp_row(node, children)}</div>'


def _tbp_render_root(root: dict, buckets: dict[str, list[dict]]) -> str:
    """Render a root (Hoshin, or a Goal in the REST fallback) as a master
    container card-grid: the root's own row on top, then each direct child
    (Theme/Feature) as its own card holding that child's full subtree."""
    state = classify_tbp_state(root)
    if state in buckets:
        buckets[state].append(root)
    children = root.get("children", [])
    cards = "".join(f'<div class="tbp-theme-card">{_tbp_render_node(child, buckets)}</div>' for child in children)
    grid = f'<div class="tbp-theme-grid">{cards}</div>' if cards else '<p class="empty">No children linked yet.</p>'
    return f'<div class="tbp-hoshin">{_tbp_row(root)}{grid}</div>'


def _tbp_tree_from_rest(issue_feed: dict) -> list[dict]:
    """Fallback tree when the GraphQL sub-issue tree is unavailable: build the same
    node shape (with 'children') from the REST issue list's Parent goal/Parent
    feature body links instead of GitHub sub-issues."""
    goal_cards = goal_issue_cards(issue_feed)
    nodes = []
    for goal in goal_cards:
        feature_nodes = []
        for feature in goal["features"]:
            feature_nodes.append({**feature, "children": feature["slices"]})
        nodes.append({**goal, "children": feature_nodes})
    return nodes


def _tbp_label_tree(issue_feed: dict) -> tuple[list[dict], list[dict]]:
    """The real TBP tree: Hoshin->Theme->Feature->Epic->Experiment, built from
    the `tbp:*` labels and `Parent Vision/Hoshin/Theme/Feature/Epic: #N` body
    links this repo actually uses (GitHub native sub-issues/trackedIssues are
    unused here -- every tbp:hoshin issue has trackedIssuesCount 0). Matching
    is case-insensitive and accepts multiple accepted prefixes per level since
    the convention drifted (older issues: 'Parent Hoshin'; newer: 'Parent
    vision'). Returns (root nodes, unlinked tbp:*-labeled issues whose parent
    link is missing or unresolved, so a broken link is visible instead of
    silently dropped)."""
    issues = issue_feed.get("issues", [])
    by_label = {
        level: [i for i in issues if f"tbp:{level}" in i.get("labels", [])]
        for level in ("hoshin", "theme", "feature", "epic", "experiment")
    }
    parent_prefixes = {
        "theme": ["Parent Hoshin", "Parent vision"],
        "feature": ["Parent Theme"],
        "epic": ["Parent Feature"],
        "experiment": ["Parent Epic"],
    }
    children_by_parent: dict[str, dict[int, list[dict]]] = {}
    unlinked: list[dict] = []
    for level, prefixes in parent_prefixes.items():
        by_parent: dict[int, list[dict]] = {}
        for issue in by_label[level]:
            parent = _parent_link_any(issue, prefixes)
            if parent is None:
                unlinked.append(issue)
            else:
                by_parent.setdefault(parent, []).append(issue)
        children_by_parent[level] = by_parent

    def _build(issue: dict, child_level: str | None) -> dict:
        children = children_by_parent.get(child_level, {}).get(issue["number"], []) if child_level else []
        next_level = {"theme": "feature", "feature": "epic", "epic": "experiment", "experiment": None}.get(child_level)
        return {**issue, "children": [_build(c, next_level) for c in children]}

    roots = [_build(hoshin, "theme") for hoshin in by_label["hoshin"]]
    return roots, unlinked


def render_tbp() -> str:
    """TBP gatekeeper view: the real Hoshin->Theme->Feature->Epic->Experiment
    tree (tbp:* labels + Parent Hoshin/Theme/Feature/Epic body links) plus a
    pipeline summary of what needs grilling, is ready, or is in
    progress. Falls back to the Goal/Feature/Slice tree only when no tbp:*
    backlog exists yet."""
    buckets: dict[str, list[dict]] = {"NEEDS_GRILLING": [], "READY_TO_PULL": [], "IN_PROGRESS": []}
    issue_feed = github_issues()
    if not issue_feed["available"]:
        tree_html = f'<div class="sourcewarn">GitHub issues unavailable: {esc(issue_feed["error"])}</div>'
        issue_status = f'GitHub issues unavailable for {esc(issue_feed["repo"])}'
    else:
        roots, unlinked = _tbp_label_tree(issue_feed)
        if roots:
            tree_html = "".join(_tbp_render_root(n, buckets) for n in roots)
            if unlinked:
                tree_html += (
                    '<div class="tbp-section"><h3>Unlinked (missing Parent link)</h3>'
                    + "".join(_tbp_row(i) for i in unlinked)
                    + "</div>"
                )
                for i in unlinked:
                    _bucket = classify_tbp_state(i)
                    if _bucket in buckets:
                        buckets[_bucket].append(i)
            issue_status = f'{len(roots)} Hoshin root(s), {len(unlinked)} unlinked tbp: issue(s) from {esc(issue_feed["repo"])}'
        else:
            nodes = _tbp_tree_from_rest(issue_feed)
            tree_html = "".join(_tbp_render_root(n, buckets) for n in nodes) or '<p class="empty">No Goal issues found.</p>'
            issue_status = f'{len(nodes)} goal issue(s) from {esc(issue_feed["repo"])} \u00b7 Parent goal/feature links (no tbp:hoshin issue found)'

    def _section(title: str, key: str) -> str:
        cards = "".join(
            f'<div class="tbp-card"><a href="{esc(i["url"])}">#{i["number"]} {esc(i["title"])}</a></div>'
            for i in buckets[key]
        ) or '<p class="empty">None.</p>'
        return f'<div class="tbp-section"><h3>{TBP_STATE_ICON[key]} {esc(title)} ({len(buckets[key])})</h3>{cards}</div>'

    pipeline_html = (
        _section("Needs grilling", "NEEDS_GRILLING")
        + _section("Ready", "READY_TO_PULL")
        + _section("In progress", "IN_PROGRESS")
    )

    legend_html = (
        '<div class="tbp-legend">'
        f'<span>{TBP_STATE_ICON["NEEDS_GRILLING"]} Needs grilling</span>'
        f'<span>{TBP_STATE_ICON["READY_TO_PULL"]} Ready</span>'
        f'<span>{TBP_STATE_ICON["IN_PROGRESS"]} In progress</span>'
        f'<span>{TBP_STATE_ICON["DONE"]} Done</span>'
        '</div>'
    )

    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="60"><title>Project0 — TBP View</title>
<style>{EXEC_CSS}{TBP_CSS}</style></head><body>
<header>
    <div><h1>Project0 — TBP View</h1><div class="sub">Grilling gate: what still needs definition, what's ready, what's in flight · {issue_status}</div></div>
    <div class="nav"><a href="/">Reality</a><a href="/detail">Detailed</a><a href="/tests">Tests</a><a href="/telemetry">Telemetry</a><a class="on" href="/tbp">TBP View</a><a href="/roadmap">Roadmap</a></div>
</header>
<main>
  <section class="sec">
    <div class="tbp-layout">
      <div class="tbp-panel"><h2>Backlog structure</h2>{tree_html}</div>
      <div class="tbp-panel">{legend_html}{pipeline_html}</div>
    </div>
  </section>
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
            body = render_overview(view).encode("utf-8")
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
        elif path == "/tbp":
            body = render_tbp().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        elif path == "/roadmap":
            body = render_roadmap().encode("utf-8")
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
