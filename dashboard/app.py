#!/usr/bin/env python3
import html
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

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


def feature_cards(reader=read_committed_file) -> list[dict]:
    text = reader("docs/FEATURE-LIST.md")
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


def phase_progress_map(tracker: str) -> dict:
    out = {}
    for m in re.finditer(r"\*\*Phase (\d+)\s*[—-]\s*([^*]+?)\*\*\s+Progress:\s*\*\*(\d+)%\*\*", tracker):
        out[int(m.group(1))] = {"title": m.group(2).strip(), "progress": int(m.group(3))}
    return out


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
                             "feature": "", "done": "100% complete" in status}
            elif status and not row["status_text"]:
                row["status_text"], row["done"] = status, "100% complete" in status
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
    return {"phases": phases, "slices": slices, "debts": debts, "goals": goal_maps(), "features": feature_cards(reader), "actions": action_items(phases, debts, slices), "calibration": calibration(), "slice_lane": build_slice_lane(tracker), "view": view}


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
            "n": "5", "title": "Two big consumers (parallel)",
            "note": "Both tracks well advanced. Accounts: auth/session/CRUD/world-entry landed (Slices 040-044); Linux authoritative validation is green, with Windows GUI confirmation still pending for Slice 044. Canon/JIT: IP-008 JIT boundary + P-011/P-012 durable canon (Slices 045-047); P-009 local-inference config/telemetry (Slice 051) and F-026 LLM-on-boot + town-derived monster exclusion (Slices 052-053) Implemented \u2014 F-026 done, Phase 8 is 11/11. Remaining: P-013 GUIDs/RPC/replay and Slice 044 GUI evidence.",
            "tracks": [
                {"name": "Player accounts & characters", "feat": "F-032 \u00b7 F-033", "steps": [
                    "Auth + session (Slice 040) \u2014 done",
                    "Character CRUD/select/create \u2192 world entry (Slices 042-043) \u2014 done; Slice 044 Windows GUI evidence pending"]},
                {"name": "Canon persistence + JIT completion", "feat": "Phase 9 \u00b7 Phase 8", "steps": [
                    "IP-008 JIT boundary + P-011/P-012 durable canon (Slices 045/046) \u2014 done",
                    "P-009 inference (Slice 051) + F-026 LLM-on-boot & monster exclusion (Slices 052-053) \u2014 done; P-013 mutation (Slice 050) done, GUIDs/RPC/replay remaining"]},
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
        f'<a class="vt{"" if working_view else " on"}" href="/">Committed</a>'
        f'<a class="vt{" on" if working_view else ""}" href="/?view=working">Working tree</a>'
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
<header><div><h1>Project0 Flow</h1><p>Kanban + Andon visual management</p></div><div class="hdr-right">{toggle_html}<div class="stamp">Read-only · refreshes every 15s</div></div></header>
<main>{calib_html}{hero_html}<div class="banner"><strong>Open signals</strong><ul>{actions_html}</ul></div>
<section class="flow">{flow_html}</section>
<section class="dr"><h2 class="sech">Delivery roadmap \u2014 {done_count}/{wave_total} waves complete</h2><div class="waves">{waves_html}</div><div class="drband"><div class="drcol"><h4>Runs in parallel throughout</h4><div class="pcards">{par_html}</div></div><div class="drcol"><h4>Must sequence \u2014 hard deps &amp; shared files</h4><ul class="seqrules">{seq_html}</ul></div></div></section>
<section class="sl"><h2 class="sech">Slices \u2014 what's part of what, in priority order</h2>{slices_html}</section>
<section class="rmwrap"><h2>Vetting \u00b7 goal roadmap <span>{decided_issues}/{total_issues} issues decided \u00b7 {overall_pct}%</span></h2><div class="roadmap">{goal_html}</div></section>
<h2 class="sech">Implementation pipeline \u2014 features correlated to their issues</h2>
<section class="board">{column_html}</section>
<div class="grid"><section class="panel"><h2>Andon / Stop Signals</h2>{andon_html}</section><section class="panel"><h2>Phase Status</h2>{phase_html or '<p>No phase data found</p>'}</section></div>
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
            body = render(view).encode("utf-8")
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
