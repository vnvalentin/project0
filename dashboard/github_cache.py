import json
import math
import os
import subprocess
import tempfile
import threading
import time
from collections.abc import Callable
from email.parser import Parser
from pathlib import Path


def run_api(endpoint: str, etag: str) -> tuple[int, dict, object]:
    command = ["gh", "api", "--method", "GET", "--include", endpoint,
               "-H", "Accept: application/vnd.github+json"]
    if etag:
        command.extend(["-H", f"If-None-Match: {etag}"])
    result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    head, separator, body = result.stdout.replace("\r\n", "\n").partition("\n\n")
    status_line, _, header_lines = head.partition("\n")
    if not separator or not status_line.startswith("HTTP/"):
        raise RuntimeError("GitHub CLI unavailable or returned an invalid response")
    status = int(status_line.split()[1])
    headers = {name.lower(): value for name, value in Parser().parsestr(header_lines).items()}
    if status == 304:
        return status, headers, None
    if status != 200:
        return status, headers, None
    if result.returncode:
        raise RuntimeError("GitHub CLI request failed")
    return status, headers, json.loads(body)


def _issue(item: dict) -> dict:
    milestone = item.get("milestone") or {}
    return {
        "number": int(item.get("number", 0)),
        "title": str(item.get("title", "")),
        "url": str(item.get("html_url", "")),
        "state": str(item.get("state", "open")),
        "labels": [str(label.get("name", "")) for label in item.get("labels", []) if label.get("name")],
        "assignees": [str(assignee.get("login", "")) for assignee in item.get("assignees", []) if assignee.get("login")],
        "body": str(item.get("body") or ""),
        "updated_at": str(item.get("updated_at", "")),
        "closed_at": str(item.get("closed_at") or ""),
        "milestone_number": milestone.get("number"),
        "milestone_title": str(milestone.get("title", "")),
    }


def _milestone(item: dict) -> dict:
    return {
        "number": int(item.get("number", 0)),
        "title": str(item.get("title", "")),
        "state": str(item.get("state", "open")),
        "description": str(item.get("description") or ""),
        "open_issues": int(item.get("open_issues", 0)),
        "closed_issues": int(item.get("closed_issues", 0)),
        "due_on": str(item.get("due_on") or ""),
    }


def fetch_github_feed(repo: str, previous: dict) -> dict:
    feed: dict = {"issues": [], "milestones": [], "pages": {}}
    for resource, project in (("issues", _issue), ("milestones", _milestone)):
        page = 1
        while True:
            endpoint = f"repos/{repo}/{resource}?state=all&per_page=100&page={page}"
            cached = previous.get("pages", {}).get(endpoint, {})
            status, headers, payload = run_api(endpoint, cached.get("etag", ""))
            if status == 304 and cached:
                response = cached
            elif status == 200 and isinstance(payload, list):
                response = {
                    "etag": headers.get("etag", ""),
                    "items": [project(item) for item in payload if resource != "issues" or "pull_request" not in item],
                    "more": len(payload) == 100,
                }
            else:
                raise RuntimeError(f"GitHub {resource} request failed (HTTP {status})")
            feed["pages"][endpoint] = response
            feed[resource].extend(response["items"])
            if not response["more"]:
                break
            page += 1
    for resource in ("issues", "milestones"):
        feed[resource].sort(key=lambda item: item["number"])
    return feed


class GitHubFeedCache:
    def __init__(
        self,
        path: Path,
        repo: str,
        fetch: Callable[[dict], dict],
        interval: int = 1800,
        clock: Callable[[], float] = time.time,
    ) -> None:
        if interval <= 0:
            raise ValueError("Refresh interval must be positive")
        self.path = path
        self.repo = repo
        self.fetch = fetch
        self.interval = interval
        self.clock = clock
        self._lock = threading.Lock()
        self._done = threading.Event()
        self._done.set()
        self._refreshing = False
        self._error = "not loaded"
        self._snapshot: dict = {}
        self._next_due = 0.0
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._scheduler: threading.Thread | None = None
        try:
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            if snapshot.get("schema_version") != 1 or snapshot.get("repo") != repo:
                raise ValueError("Cache schema or repository mismatch")
            updated_at = snapshot.get("updated_at")
            if type(updated_at) not in (int, float) or not math.isfinite(updated_at) or not 0 < updated_at <= self.clock():
                raise ValueError("Invalid cache timestamp")
            self._validate(snapshot)
            self._snapshot = snapshot
            self._error = ""
            self._next_due = updated_at + interval
        except FileNotFoundError:
            pass
        except (OSError, ValueError, TypeError, AttributeError) as exc:
            self._error = f"Cache unavailable: {exc}"

    @staticmethod
    def _validate(data: dict) -> None:
        for field in ("issues", "milestones"):
            if not isinstance(data.get(field), list):
                raise ValueError(f"Invalid {field} snapshot")
            for item in data[field]:
                if not isinstance(item, dict) or type(item.get("number")) is not int or item["number"] <= 0:
                    raise ValueError(f"Invalid {field} entry")
                if not isinstance(item.get("title"), str) or item.get("state") not in ("open", "closed"):
                    raise ValueError(f"Invalid {field} entry")

    def read(self) -> dict:
        with self._lock:
            updated_at = self._snapshot.get("updated_at", 0.0)
            return {
                **self._snapshot,
                "available": bool(self._snapshot),
                "repo": self.repo,
                "issues": self._snapshot.get("issues", []),
                "milestones": self._snapshot.get("milestones", []),
                "updated_at": updated_at,
                "refreshing": self._refreshing,
                "next_refresh_at": self._next_due,
                "stale": bool(self._error) or self.clock() - updated_at >= self.interval,
                "error": self._error,
            }

    def request_refresh(self, *, only_if_due: bool = False) -> bool:
        with self._lock:
            if self._refreshing or (only_if_due and self.clock() < self._next_due):
                return False
            self._refreshing = True
            self._next_due = self.clock() + self.interval
            self._done.clear()
            threading.Thread(target=self._refresh, daemon=True, name="github-refresh").start()
            return True

    def refresh_if_due(self) -> bool:
        return self.request_refresh(only_if_due=True)

    def start(self) -> None:
        with self._lock:
            if self._scheduler is not None:
                return
            self._scheduler = threading.Thread(target=self._schedule, daemon=True, name="github-schedule")
            self._scheduler.start()

    def close(self) -> None:
        self._stop.set()
        self._wake.set()
        if self._scheduler is not None:
            self._scheduler.join(timeout=2)

    def _schedule(self) -> None:
        while not self._stop.is_set():
            self.refresh_if_due()
            delay = max(0.05, self.read()["next_refresh_at"] - self.clock())
            self._wake.wait(delay)
            self._wake.clear()

    def wait_for_refresh(self, timeout: float) -> bool:
        return self._done.wait(timeout)

    def _refresh(self) -> None:
        temporary_path = None
        try:
            data = self.fetch(self._snapshot)
            self._validate(data)
            snapshot = {**data, "schema_version": 1, "repo": self.repo, "updated_at": self.clock()}
            self.path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_path = tempfile.mkstemp(prefix=".github-", dir=self.path.parent)
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                json.dump(snapshot, output)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary_path, self.path)
            with self._lock:
                self._snapshot = snapshot
                self._error = ""
        except Exception as exc:
            with self._lock:
                self._error = f"Refresh failed: {exc}"
        finally:
            if temporary_path and os.path.exists(temporary_path):
                os.unlink(temporary_path)
            with self._lock:
                self._refreshing = False
                self._next_due = self.clock() + self.interval
                self._done.set()
                self._wake.set()