#!/usr/bin/env python3
import html
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

REPO = Path(os.environ.get("PROJECT_ROOT", "/repo"))
PORT = int(os.environ.get("PORT", "8080"))
SELF_PATH = Path(__file__).resolve()
try:
    _SELF_MTIME = SELF_PATH.stat().st_mtime
except OSError:
    _SELF_MTIME = None


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


def goal_maps() -> list[dict]:
    goals = []
    for name in list_repo_dir(".scratch"):
        map_text = read_repo_file(f".scratch/{name}/map.md")
        if not map_text:
            continue
        title_lookup = issue_titles_from_map(map_text)
        issues = []
        for issue_name in list_repo_dir(f".scratch/{name}/issues"):
            if not issue_name.endswith(".md"):
                continue
            text = read_repo_file(f".scratch/{name}/issues/{issue_name}")
            stem = issue_name[:-3]
            status = issue_field(text, "Status") or "unclaimed"
            number = re.match(r"^(\d+)", stem)
            issues.append({
                "id": number.group(1) if number else "",
                "title": title_lookup.get(stem) or slug_title(stem),
                "status": status,
                "type": issue_field(text, "Type"),
                "state": issue_state(status),
            })
        decided = sum(1 for issue in issues if issue["state"] == "decided")
        total = len(issues)
        goals.append({
            "name": name,
            "title": map_title(map_text, name),
            "destination": map_destination(map_text),
            "issues": issues,
            "decided": decided,
            "total": total,
            "percent": round(decided / total * 100) if total else 0,
        })
    return goals


def feature_stage(status: str) -> str:
    normalized = status.lower().strip()
    if normalized.startswith(("implemented", "done")):
        return "Done"
    if normalized.startswith(("in progress", "active")):
        return "Active"
    if normalized.startswith("ready"):
        return "Ready"
    return "Planned"


def feature_cards() -> list[dict]:
    text = read_repo_file("docs/FEATURE-LIST.md")
    cards = []
    for match in re.finditer(r"^### ((?:IP|P|F)-\d+):\s*(.+?)[ \t]*$\n([\s\S]*?)(?=^### |\Z)", text, re.M):
        fid, title, body = match.group(1), match.group(2).strip(), match.group(3)
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


def snapshot() -> dict:
    tracker = read_repo_file("docs/PROJECT-TRACKER.md")
    debt = read_repo_file("docs/TECHNICAL-DEBT-TRACKER.md")
    phases = phase_rows(tracker)
    slices = slice_cards(tracker) + queue_items(tracker)
    debts = debt_cards(debt)
    return {"phases": phases, "slices": slices, "debts": debts, "goals": goal_maps(), "features": feature_cards(), "actions": action_items(phases, debts, slices)}


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def card(title: str, body: str, css: str = "") -> str:
    return f'<article class="card {css}"><h3>{esc(title)}</h3><p>{esc(body)}</p></article>'


def render() -> str:
    data = snapshot()

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
    for name in stage_order:
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
            f'<span class="chip {i["state"]}" title="{esc(i["status"])}">{esc((i["id"] + " ") if i["id"] else "")}{esc(i["title"])}</span>'
            for i in g["issues"]
        ) or '<span class="chip todo">no issues</span>'
        dest = g["destination"]
        if len(dest) > 170:
            dest = dest[:167].rstrip() + "\u2026"
        goal_html += (
            f'<section class="goal"><div class="goal-head"><h3>{esc(g["title"])}</h3>'
            f'<span class="pct">{g["decided"]}/{g["total"]} \u00b7 {g["percent"]}%</span></div>'
            f'<div class="bar"><div class="fill" style="width:{g["percent"]}%"></div></div>'
            f'<p class="dest">{esc(dest)}</p><div class="chips">{chips}</div></section>'
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
    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="15"><title>Project0 Flow Dashboard</title>
<style>
:root {{ color-scheme: dark; --bg:#11161d; --panel:#1a222d; --line:#304052; --text:#e8eef5; --muted:#9dafbf; --cyan:#58d4e8; --green:#54d18a; --amber:#f3bd55; --red:#ff7070; }}
* {{ box-sizing:border-box }} body {{ margin:0; font:14px/1.4 system-ui,sans-serif; background:var(--bg); color:var(--text) }} header {{ padding:24px 32px; border-bottom:1px solid var(--line); display:flex; justify-content:space-between; align-items:end }} h1 {{ margin:0; color:var(--cyan); letter-spacing:.03em }} h2 {{ margin:0 0 12px; font-size:16px }} h3 {{ margin:0 0 6px; font-size:14px }} p {{ margin:0; color:var(--muted) }} main {{ padding:24px 32px; max-width:1500px; margin:auto }} .banner {{ background:#332619; border:1px solid var(--amber); color:#ffe0a0; padding:14px 16px; margin-bottom:22px; border-radius:8px }} .board {{ display:grid; grid-template-columns:repeat(4,minmax(190px,1fr)); gap:14px; align-items:start }} .column,.panel {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px }} .column h2 span {{ float:right; color:var(--muted); font-weight:normal }} .card {{ background:#222d39; border:1px solid #3a4b5d; border-left:4px solid var(--cyan); border-radius:6px; padding:10px; margin:8px 0 }} .card.andon {{ border-left-color:var(--red) }} .card.in-progress {{ border-left-color:var(--amber) }} .card.done {{ border-left-color:var(--green) }} .empty,.clear {{ color:var(--muted); padding:12px 0 }} .grid {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-top:22px }} ul {{ margin:0; padding-left:20px }} li {{ margin:8px 0 }} .action {{ color:#ffe0a0 }} .stamp {{ color:var(--muted); font-size:12px }} @media(max-width:900px) {{ .board,.grid {{ grid-template-columns:1fr 1fr }} }} @media(max-width:600px) {{ header,main {{ padding:16px }} .board,.grid {{ grid-template-columns:1fr }} }}
.rmwrap {{ margin-bottom:22px }} .rmwrap h2 {{ display:flex; justify-content:space-between; align-items:baseline }} .rmwrap h2 span {{ color:var(--muted); font-weight:normal; font-size:13px }} .roadmap {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(330px,1fr)); gap:14px }} .goal {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px }} .goal-head {{ display:flex; justify-content:space-between; align-items:baseline; gap:8px }} .goal-head h3 {{ margin:0; color:var(--cyan) }} .pct {{ color:var(--muted); font-size:12px; white-space:nowrap }} .bar {{ height:8px; background:#0e141b; border:1px solid var(--line); border-radius:6px; overflow:hidden; margin:10px 0 }} .fill {{ height:100%; background:linear-gradient(90deg,var(--green),var(--cyan)) }} .dest {{ font-size:12px; margin-bottom:10px }} .chips {{ display:flex; flex-wrap:wrap; gap:6px }} .chip {{ font-size:11px; padding:3px 8px; border-radius:12px; border:1px solid var(--line); background:#222d39; color:var(--muted) }} .chip.decided {{ border-color:var(--green); color:var(--green) }} .chip.active {{ border-color:var(--amber); color:var(--amber) }} .chip.todo {{ opacity:.7 }}
.flow {{ display:flex; align-items:stretch; gap:6px; margin-bottom:22px; flex-wrap:wrap }} .flow .stage {{ flex:1 1 0; min-width:118px; background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:12px 14px; display:flex; flex-direction:column; gap:2px }} .flow .stage .n {{ font-size:22px; font-weight:600 }} .flow .stage .lbl {{ font-size:12px; color:var(--muted) }} .flow .stage.vet {{ border-left:4px solid var(--muted) }} .flow .stage.ready {{ border-left:4px solid var(--cyan) }} .flow .stage.active {{ border-left:4px solid var(--amber) }} .flow .stage.await {{ border-left:4px solid var(--amber) }} .flow .stage.done {{ border-left:4px solid var(--green) }} .flow .arw {{ align-self:center; color:var(--muted); font-size:18px }} .sech {{ margin:0 0 10px; font-size:13px; text-transform:uppercase; letter-spacing:.08em; color:var(--muted) }}
.itags {{ display:flex; flex-wrap:wrap; gap:4px; margin-top:8px }} .itag {{ font-size:10px; padding:2px 7px; border-radius:10px; background:#1a2430; border:1px solid var(--line); color:var(--muted) }} .itag.none {{ opacity:.6; font-style:italic }} .card.planned {{ border-left-color:var(--muted) }} .flow .stage.planned {{ border-left:4px solid var(--muted) }}
</style></head><body>
<header><div><h1>Project0 Flow</h1><p>Kanban + Andon visual management</p></div><div class="stamp">Read-only · refreshes every 15s</div></header>
<main><div class="banner"><strong>Action required</strong><ul>{actions_html}</ul></div>
<section class="flow">{flow_html}</section>
<section class="rmwrap"><h2>Vetting \u00b7 goal roadmap <span>{decided_issues}/{total_issues} issues decided \u00b7 {overall_pct}%</span></h2><div class="roadmap">{goal_html}</div></section>
<h2 class="sech">Implementation pipeline \u2014 features correlated to their issues</h2>
<section class="board">{column_html}</section>
<div class="grid"><section class="panel"><h2>Andon / Stop Signals</h2>{andon_html}</section><section class="panel"><h2>Phase Status</h2>{phase_html or '<p>No phase data found</p>'}</section></div>
</main></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        restart_if_source_changed()
        path = urlparse(self.path).path
        if path == "/health":
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        elif path in ("/", "/index.html"):
            body = render().encode("utf-8")
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
