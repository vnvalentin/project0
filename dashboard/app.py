#!/usr/bin/env python3
import html
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

REPO = Path(os.environ.get("PROJECT_ROOT", "/repo"))
PORT = int(os.environ.get("PORT", "8080"))


def read_repo_file(name: str) -> str:
    path = (REPO / name).resolve()
    if REPO.resolve() not in path.parents:
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


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
    for phase in phases:
        if phase["status"].lower() in {"in-progress", "blocked", "queued"}:
            actions.append(f"Review {phase['phase']} ({phase['status']})")
    for debt in debts:
        if debt["status"].lower() not in {"resolved", "closed", "accepted"}:
            actions.append(f"Andon: {debt['id']} {debt['title']}")
    for card in slices:
        status = card["status"].lower()
        if "100%" in status and "outstanding" not in status:
            continue
        if "outstanding" in status or "in progress" in status or "working" in status or re.search(r"(?<!\d)0%", status):
            actions.append(f"Evidence needed: {card['title']}")
    return actions


def snapshot() -> dict:
    tracker = read_repo_file("docs/PROJECT-TRACKER.md")
    debt = read_repo_file("docs/TECHNICAL-DEBT-TRACKER.md")
    phases = phase_rows(tracker)
    slices = slice_cards(tracker)
    debts = debt_cards(debt)
    return {"phases": phases, "slices": slices, "debts": debts, "actions": action_items(phases, debts, slices)}


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def card(title: str, body: str, css: str = "") -> str:
    return f'<article class="card {css}"><h3>{esc(title)}</h3><p>{esc(body)}</p></article>'


def render() -> str:
    data = snapshot()

    def is_done(s: dict[str, str]) -> bool:
        st = s["status"].lower()
        return "100%" in st and "outstanding" not in st

    def is_active(s: dict[str, str]) -> bool:
        st = s["status"].lower()
        return any(w in st for w in ("in progress", "working", "in-progress")) and not is_done(s)

    def is_awaiting(s: dict[str, str]) -> bool:
        st = s["status"].lower()
        return ("outstanding" in st or "awaiting" in st) and not is_done(s)

    def is_ready(s: dict[str, str]) -> bool:
        st = s["status"].lower()
        return bool(re.search(r"(?<!\d)0%", st) or "queued" in st or "ready" in st) and not is_done(s)

    done = [s for s in data["slices"] if is_done(s)]
    active = [s for s in data["slices"] if is_active(s) and s not in done]
    awaiting = [s for s in data["slices"] if is_awaiting(s) and s not in done and s not in active]
    ready = [s for s in data["slices"] if is_ready(s) and s not in done and s not in active and s not in awaiting]

    columns = {
        "Ready": ready,
        "Active": active,
        "Awaiting evidence": awaiting,
        "Done": done,
    }
    column_html = ""
    for name, items in columns.items():
        css_class = "done" if name == "Done" else ("in-progress" if name in ("Active", "Awaiting evidence") else "")
        body = "".join(card(item["title"], item["status"], css_class) for item in items) or '<p class="empty">Nothing here</p>'
        column_html += f'<section class="column"><h2>{esc(name)} <span>{len(items)}</span></h2>{body}</section>'
    phase_html = "".join(card(p["phase"], p["status"] + " — " + p["gate"], p["status"].lower()) for p in data["phases"])
    blocked = [d for d in data["debts"] if d["status"].lower() not in {"resolved", "closed", "accepted"}]
    andon_html = "".join(card(d["id"], d["title"] + " — " + d["status"], "andon") for d in blocked) or '<p class="clear">No open Andon signals</p>'
    actions_html = "".join(f"<li>{esc(item)}</li>" for item in data["actions"]) or '<li>No immediate action detected</li>'
    return f'''<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="15"><title>Project0 Flow Dashboard</title>
<style>
:root {{ color-scheme: dark; --bg:#11161d; --panel:#1a222d; --line:#304052; --text:#e8eef5; --muted:#9dafbf; --cyan:#58d4e8; --green:#54d18a; --amber:#f3bd55; --red:#ff7070; }}
* {{ box-sizing:border-box }} body {{ margin:0; font:14px/1.4 system-ui,sans-serif; background:var(--bg); color:var(--text) }} header {{ padding:24px 32px; border-bottom:1px solid var(--line); display:flex; justify-content:space-between; align-items:end }} h1 {{ margin:0; color:var(--cyan); letter-spacing:.03em }} h2 {{ margin:0 0 12px; font-size:16px }} h3 {{ margin:0 0 6px; font-size:14px }} p {{ margin:0; color:var(--muted) }} main {{ padding:24px 32px; max-width:1500px; margin:auto }} .banner {{ background:#332619; border:1px solid var(--amber); color:#ffe0a0; padding:14px 16px; margin-bottom:22px; border-radius:8px }} .board {{ display:grid; grid-template-columns:repeat(4,minmax(190px,1fr)); gap:14px; align-items:start }} .column,.panel {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px }} .column h2 span {{ float:right; color:var(--muted); font-weight:normal }} .card {{ background:#222d39; border:1px solid #3a4b5d; border-left:4px solid var(--cyan); border-radius:6px; padding:10px; margin:8px 0 }} .card.andon {{ border-left-color:var(--red) }} .card.in-progress {{ border-left-color:var(--amber) }} .card.done {{ border-left-color:var(--green) }} .empty,.clear {{ color:var(--muted); padding:12px 0 }} .grid {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-top:22px }} ul {{ margin:0; padding-left:20px }} li {{ margin:8px 0 }} .action {{ color:#ffe0a0 }} .stamp {{ color:var(--muted); font-size:12px }} @media(max-width:900px) {{ .board,.grid {{ grid-template-columns:1fr 1fr }} }} @media(max-width:600px) {{ header,main {{ padding:16px }} .board,.grid {{ grid-template-columns:1fr }} }}
</style></head><body>
<header><div><h1>Project0 Flow</h1><p>Kanban + Andon visual management</p></div><div class="stamp">Read-only · refreshes every 15s</div></header>
<main><div class="banner"><strong>Action required</strong><ul>{actions_html}</ul></div>
<section class="board">{column_html}</section>
<div class="grid"><section class="panel"><h2>Andon / Stop Signals</h2>{andon_html}</section><section class="panel"><h2>Phase Status</h2>{phase_html or '<p>No phase data found</p>'}</section></div>
</main></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
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
