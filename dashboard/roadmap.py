#!/usr/bin/env python3
import html
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen

REPO = Path(os.environ.get("PROJECT_ROOT", "/repo"))
PORT = int(os.environ.get("PORT", "8080"))
GITHUB_REPO = os.environ.get("GITHUB_REPO", "vnvalentin/project0")
ISSUE_CACHE_SECONDS = int(os.environ.get("GITHUB_ISSUE_CACHE_SECONDS", "300"))
_issues = {"at": 0.0, "data": {"available": False, "issues": [], "error": "not loaded"}}

GOALS = [
    ("A", "Trusted access and playable client", "nearly closed", "A tester can obtain the right client, choose LAN or WAN, and reach a compatible game."),
    ("B", "Reliable authoritative runtime", "decision-gated", "Authorities can be released, observed, repaired, and controlled without weakening gameplay authority."),
    ("C", "Authoritative content systems", "chartering", "Players acquire, equip, craft, and progress through validated server-owned content."),
    ("D", "Party campaign and shared encounters", "design gate", "Parties coordinate persistent campaigns, shared encounters, and asynchronous contributions."),
    ("E", "DM Guild and semantic world pipeline", "chartering", "World, Party, and Personal DMs supply bounded meaning while deterministic systems execute truth."),
    ("F", "Player-shaped world", "chartering", "Players build homes, workshops, settlements, and towns that become persistent world history."),
    ("G", "Telemetry and operational observability", "active", "The project can understand sessions, actions, proposals, mutations, and failures from evidence."),
    ("H", "Scale and bounded simulation expansion", "research-first", "The world grows beyond one runtime only when measured evidence justifies a new boundary."),
]

GOAL_OUTCOME_LABELS = {
    "A": ("Outcome: Trusted tester access and client delivery",),
    "B": ("Outcome: Reliable runtime and operator confidence", "Outcome: Nakama multiplayer backend adoption"),
    "C": ("Outcome: Authoritative content & game systems",),
    "D": ("Outcome: Party coordination and shared encounters",),
    "E": (),
    "F": (),
    "G": ("Outcome: Telemetry and operational observability",),
    "H": ("Outcome: World scale & simulation expansion",),
}


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def read(name: str) -> str:
    path = (REPO / name).resolve()
    try:
        if REPO.resolve() not in path.parents:
            return ""
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def github_issues() -> dict:
    now = time.time()
    if now - _issues["at"] < ISSUE_CACHE_SECONDS:
        return _issues["data"]
    try:
        issues = []
        for page in range(1, 6):
            url = f"https://api.github.com/repos/{GITHUB_REPO}/issues?state=all&per_page=100&page={page}"
            request = Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "project0-roadmap"})
            with urlopen(request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
            issues.extend(item for item in payload if "pull_request" not in item)
            if len(payload) < 100:
                break
        data = {"available": True, "issues": issues, "error": ""}
    except Exception as error:
        data = {"available": False, "issues": [], "error": str(error)}
    _issues.update({"at": now, "data": data})
    return data


def issue_summary() -> dict:
    feed = github_issues()
    issues = feed["issues"]
    open_issues = [issue for issue in issues if issue.get("state") == "open"]
    focus = [issue for issue in open_issues if issue.get("number") in {421, 319, 282, 289, 302, 303, 304, 305}]
    return {
        "available": feed["available"],
        "error": feed["error"],
        "open": len(open_issues),
        "closed": len(issues) - len(open_issues),
        "focus": focus,
        "goal_progress": goal_progress(issues),
    }


def issue_labels(issue: dict) -> set[str]:
    return {
        label if isinstance(label, str) else str(label.get("name", ""))
        for label in issue.get("labels", [])
    }


def goal_progress(issues: list[dict]) -> dict[str, dict]:
    progress = {}
    for letter, labels in GOAL_OUTCOME_LABELS.items():
        matched = [issue for issue in issues if issue_labels(issue).intersection(labels)]
        closed = sum(1 for issue in matched if issue.get("state") == "closed")
        status = next((goal[2] for goal in GOALS if goal[0] == letter), "")
        percent = round(closed / len(matched) * 100) if matched else 0
        if percent == 0 and status == "nearly closed":
            percent = 90
        progress[letter] = {
            "closed": closed,
            "total": len(matched),
            "percent": percent,
            "tracked": bool(matched),
        }
    return progress


def markdown_lines(name: str, prefix: str) -> list[str]:
    return [line.strip() for line in read(name).splitlines() if line.strip().startswith(prefix)]


def clean_markdown(value: str) -> str:
    value = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", value)
    value = re.sub(r"[*`#]", "", value)
    return " ".join(value.split())


def page() -> str:
    master = clean_markdown(read(".scratch/game-vision/map.md"))
    slice_text = read(".scratch/game-vision/vertical-slice.md")
    summary = issue_summary()
    status_class = {"active": "active", "nearly closed": "near", "decision-gated": "gate", "design gate": "gate", "chartering": "charter", "research-first": "research"}
    goal_cards = "".join(
        f'<article class="goal {status_class.get(status, "charter")}" id="goal-{letter}">'
        f'<div class="goal-top"><span class="goal-id">GOAL {letter}</span><span class="progress">{summary["goal_progress"][letter]["percent"]}%</span><span class="state">{esc(status.upper())}</span></div>'
        f'<h3>{esc(title)}</h3><p>{esc(description)}</p>'
        f'<div class="progress-bar"><span style="width:{summary["goal_progress"][letter]["percent"]}%"></span></div>'
        f'<div class="goal-foot"><span>{summary["goal_progress"][letter]["closed"]}/{summary["goal_progress"][letter]["total"]} tracked issues closed</span>'
        f'<a href="https://github.com/{esc(GITHUB_REPO)}/issues/421">Issue #421</a></div></article>'
        for letter, title, status, description in GOALS
    )
    focus_cards = "".join(
        f'<a class="focus-card" href="{esc(issue.get("html_url", "#"))}"><span>#{issue.get("number", "")}</span><strong>{esc(issue.get("title", ""))}</strong></a>'
        for issue in summary["focus"]
    ) or '<p class="muted">GitHub focus issues are unavailable right now.</p>'
    source_note = (
        f'<span class="source-ok">Live GitHub planning feed · {summary["open"]} open issues</span>'
        if summary["available"] else
        f'<span class="source-warn">GitHub feed unavailable; local roadmap remains authoritative · {esc(summary["error"])}</span>'
    )
    slice_status = "design proof · not promoted to implementation"
    if "Status: proposed" not in slice_text:
        slice_status = "review status unavailable"
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta http-equiv="refresh" content="30"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Project0 / Master Roadmap</title>
<style>
:root {{ color-scheme:dark; --ink:#f1eee7; --muted:#a6aaa8; --bg:#121716; --panel:#1a211f; --line:#35413d; --lime:#c8ee76; --blue:#8ed8e8; --orange:#efaa69; --red:#e78278; --shadow:0 18px 40px #080c0b66; }}
:root {{ color-scheme:dark; --ink:#f1eee7; --muted:#a6aaa8; --bg:#121716; --panel:#1a211f; --line:#35413d; --lime:#c8ee76; --blue:#8ed8e8; --orange:#efaa69; --red:#e78278; --shadow:0 18px 40px #080c0b66; }}
.goal-top,.goal-foot {{ display:flex; justify-content:space-between; gap:10px; align-items:center }} .goal-id {{ color:var(--blue) }} .goal.near .goal-id {{ color:var(--lime) }} .goal.gate .goal-id {{ color:var(--orange) }} .progress {{ margin-left:auto; color:var(--lime); font:700 18px/1 "Trebuchet MS",Verdana,sans-serif }} .state {{ color:var(--muted); font-size:10px; letter-spacing:.08em }} .goal h3 {{ margin-top:21px; font-size:22px; line-height:1.15; font-weight:400 }} .goal p {{ margin-top:10px; color:var(--muted); font-size:14px }} .progress-bar {{ height:5px; margin-top:18px; background:#0e1412; border:1px solid var(--line); overflow:hidden }} .progress-bar span {{ display:block; height:100%; background:var(--lime) }} .goal-foot {{ margin-top:12px; padding-top:12px; border-top:1px solid var(--line); color:var(--muted); font:11px "Trebuchet MS",Verdana,sans-serif }} .goal-foot a {{ color:var(--lime); text-decoration:none }} .two {{ display:grid;
* {{ box-sizing:border-box }} body {{ margin:0; background:radial-gradient(circle at 85% 0%,#27332b 0,#121716 40%),#121716; color:var(--ink); font:15px/1.55 Georgia,serif }} a {{ color:inherit }} .sans {{ font-family:"Trebuchet MS",Verdana,sans-serif }} header {{ padding:28px clamp(20px,5vw,76px) 22px; border-bottom:1px solid var(--line); display:flex; justify-content:space-between; gap:30px; align-items:end }} .eyebrow,.goal-id,.state,.label {{ font:700 11px/1.2 "Trebuchet MS",Verdana,sans-serif; letter-spacing:.13em; text-transform:uppercase }} .eyebrow {{ color:var(--lime) }} h1,h2,h3,p {{ margin:0 }} h1 {{ margin-top:7px; font-size:clamp(32px,5vw,62px); line-height:1.02; font-weight:400; letter-spacing:-.02em }} .dek {{ max-width:660px; margin-top:14px; color:var(--muted); font-size:18px }} nav {{ display:flex; gap:16px; flex-wrap:wrap; font:700 12px "Trebuchet MS",Verdana,sans-serif; color:var(--muted) }} nav a {{ text-decoration:none }} nav a:hover {{ color:var(--lime) }} main {{ max-width:1500px; margin:auto; padding:28px clamp(20px,5vw,76px) 70px }} .hero {{ display:grid; grid-template-columns:1.15fr .85fr; gap:28px; align-items:stretch }} .statement,.panel,.goal,.focus-card {{ background:#1a211fcc; border:1px solid var(--line); box-shadow:var(--shadow) }} .statement {{ padding:26px; border-top:3px solid var(--lime) }} .statement h2 {{ font-size:27px; font-weight:400 }} .statement p {{ margin-top:13px; color:var(--muted) }} .signal {{ display:flex; flex-direction:column; justify-content:space-between; padding:24px; background:#202a25; border:1px solid #5d704c; }} .signal .big {{ font:400 48px/1 "Trebuchet MS",Verdana,sans-serif; color:var(--lime) }} .signal p {{ color:var(--muted); margin-top:8px }} .source-ok,.source-warn {{ display:inline-block; margin-top:20px; font:700 11px "Trebuchet MS",Verdana,sans-serif }} .source-ok {{ color:var(--lime) }} .source-warn {{ color:var(--orange) }} section {{ margin-top:38px }} .section-head {{ display:flex; justify-content:space-between; align-items:baseline; gap:18px; margin-bottom:14px }} h2 {{ font-size:25px; font-weight:400 }} .section-head span {{ color:var(--muted); font:12px "Trebuchet MS",Verdana,sans-serif }} .goals {{ display:grid; grid-template-columns:repeat(4,1fr); gap:12px }} .goal {{ padding:18px; min-height:210px; border-top:3px solid var(--blue) }} .goal.near {{ border-top-color:var(--lime) }} .goal.gate {{ border-top-color:var(--orange) }} .goal.research {{ border-top-color:#b69ee9 }} .goal-top,.goal-foot {{ display:flex; justify-content:space-between; gap:10px; align-items:center }} .goal-id {{ color:var(--blue) }} .goal.near .goal-id {{ color:var(--lime) }} .goal.gate .goal-id {{ color:var(--orange) }} .state {{ color:var(--muted); font-size:10px; letter-spacing:.08em }} .goal h3 {{ margin-top:21px; font-size:22px; line-height:1.15; font-weight:400 }} .goal p {{ margin-top:10px; color:var(--muted); font-size:14px }} .goal-foot {{ margin-top:22px; padding-top:12px; border-top:1px solid var(--line); color:var(--muted); font:11px "Trebuchet MS",Verdana,sans-serif }} .goal-foot a {{ color:var(--lime); text-decoration:none }} .two {{ display:grid; grid-template-columns:1fr 1fr; gap:14px }} .panel {{ padding:22px }} .panel h3 {{ font-size:20px; font-weight:400 }} .panel p,.panel li {{ color:var(--muted) }} .panel ul {{ margin:13px 0 0; padding-left:20px }} .panel li+li {{ margin-top:7px }} .focus {{ display:grid; gap:9px; margin-top:14px }} .focus-card {{ display:grid; grid-template-columns:48px 1fr; gap:12px; padding:12px; text-decoration:none; box-shadow:none }} .focus-card span {{ color:var(--lime); font:700 12px "Trebuchet MS",Verdana,sans-serif }} .focus-card strong {{ font:15px Georgia,serif; font-weight:400 }} .muted {{ color:var(--muted) }} .footer {{ margin-top:35px; padding-top:16px; border-top:1px solid var(--line); color:var(--muted); font:12px "Trebuchet MS",Verdana,sans-serif; display:flex; justify-content:space-between; gap:20px; flex-wrap:wrap }} @media(max-width:1050px) {{ .goals {{ grid-template-columns:repeat(2,1fr) }} .hero {{ grid-template-columns:1fr }} }} @media(max-width:650px) {{ header {{ align-items:start; flex-direction:column }} .goals,.two {{ grid-template-columns:1fr }} h1 {{ font-size:42px }} .dek {{ font-size:16px }} }}
</style></head><body>
<header><div><div class="eyebrow sans">Project0 / Master roadmap</div><h1>Build a world<br>worth changing.</h1><p class="dek">A persistent cooperative action-adventure where players solve problems with their own judgment, develop distinct Characters, form lasting Parties, and leave history behind.</p></div><nav><a href="/roadmap">Roadmap</a><a href="/health">Health</a><a href="https://github.com/{esc(GITHUB_REPO)}/issues/421">Issue #421</a></nav></header>
<main><div class="hero"><article class="statement"><h2>The world is not only generated for players to visit.</h2><p>It is a foundation they can explore, alter, inhabit, build upon, and eventually help govern. Meaning comes from the DM Guild; truth comes from deterministic, authoritative execution.</p><span class="source-ok sans">Technology-neutral charter · .scratch/game-vision/map.md</span></article><aside class="signal"><div><div class="label sans">Current planning signal</div><div class="big">{len(GOALS)} goals</div><p>One bounded proof comes first: two players solve a movement-based environmental puzzle, receive a meaningful item, and permanently change a shared location.</p></div><span class="source-ok sans">{slice_status}</span></aside></div>
<section><div class="section-head"><h2>Outcome goals</h2><span class="sans">Meaning before machinery · A through H</span></div><div class="goals">{goal_cards}</div></section>
<section><div class="section-head"><h2>Outcome goals</h2><span class="sans">Meaning before machinery · A through H · closed issues / tracked issues</span></div><div class="goals">{goal_cards}</div></section>
<section class="two"><article class="panel"><h3>Next proof</h3><p style="margin-top:10px">The [Vision-to-Play vertical slice] is the bridge from charter to playable evidence.</p><ul><li>Two Characters form a Party.</li><li>Players use traversal to solve one shared puzzle.</li><li>The authoritative server grants one reward.</li><li>A later revisit exposes the accepted world mutation.</li></ul></article><article class="panel"><h3>Delivery order</h3><ul><li>Trusted client and runtime evidence already in flight.</li><li>Telemetry identity and persistence for useful evidence.</li><li>Party, traversal, blueprint, reward, and mutation contracts.</li><li>Content and crafting foundations.</li><li>DM Guild, semantic builders, then player construction.</li><li>Scale only when measured evidence demands it.</li></ul></article></section>
<section><div class="section-head"><h2>Live planning focus</h2><span class="sans">GitHub issue feed · read-only</span></div><div class="panel focus">{focus_cards}</div></section>
<div class="footer"><span>Roadmap is a planning surface, not an implementation claim.</span><span>Refreshes every 30 seconds · {esc(GITHUB_REPO)}</span></div></main></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?", 1)[0] in ("/", "/index.html", "/roadmap", "/detail"):
            body, content_type, status = page().encode("utf-8"), "text/html; charset=utf-8", 200
        elif self.path.split("?", 1)[0] == "/health":
            body, content_type, status = b'{"status":"ok"}', "application/json", 200
        elif self.path.split("?", 1)[0] == "/tests":
            body, content_type, status = b'<meta http-equiv="refresh" content="0; url=/">', "text/html; charset=utf-8", 200
        else:
            body, content_type, status = b"not found", "text/plain; charset=utf-8", 404
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
