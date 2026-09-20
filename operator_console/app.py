#!/usr/bin/env python3
import html
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from dashboard.ops_registry import scan_registry

HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8090"))
MANIFEST = Path(os.environ.get("SERVER_MANIFEST", "/config/servers.json"))
SNAPSHOTS = Path(os.environ.get("SNAPSHOT_ROOT", "/snapshots"))


def page(title: str, body: str) -> bytes:
    return ("<!doctype html><html><head><meta charset=utf-8><title>" + html.escape(title)
            + "</title><style>body{font:16px sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;background:#f4f6f8;color:#17212b}a{color:#075985}table{width:100%;border-collapse:collapse;background:white}td,th{padding:.7rem;border-bottom:1px solid #d9e1e8;text-align:left}.healthy{color:#166534}.stale,.unreadable{color:#9a3412}.absent{color:#64748b}pre{white-space:pre-wrap;background:white;padding:1rem;border:1px solid #d9e1e8}</style></head><body>"
            + body + "</body></html>").encode("utf-8")


def render_fleet() -> str:
    rows = scan_registry(MANIFEST, SNAPSHOTS)
    table = ["<h1>Project0 operator console</h1><p>Read-only current state</p><table><tr><th>Server</th><th>Type</th><th>State</th><th>Unit</th></tr>"]
    for row in rows:
        server_id = html.escape(row["server_id"])
        table.append(f'<tr><td><a href="/server/{server_id}">{server_id}</a></td><td>{html.escape(row["server_type"])}</td><td class="{row["state"]}">{row["state"]}</td><td>{html.escape(row["unit"])}</td></tr>')
    table.append("</table>")
    return "".join(table)


def render_detail(server_id: str) -> str | None:
    rows = {row["server_id"]: row for row in scan_registry(MANIFEST, SNAPSHOTS)}
    row = rows.get(server_id)
    if row is None:
        return None
    return f'<h1>{html.escape(server_id)}</h1><p><a href="/">Fleet</a></p><p class="{row["state"]}">State: {row["state"]}</p><pre>{html.escape(repr(row["snapshot"]))}</pre>'


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        body = render_fleet() if path == "/" else render_detail(path.removeprefix("/server/")) if path.startswith("/server/") else None
        if body is None:
            self.send_error(404)
            return
        payload = page("Project0 operator console", body)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format: str, *_args: object) -> None:
        return


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
