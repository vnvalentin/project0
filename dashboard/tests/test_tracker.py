import json
import sys
import threading
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).parents[1]))
from app import _roadmap_milestones, delivery_projection, render_delivery, render_tracker
from tracker import inline_markdown, load_tracker, validate_tracker
import tracker as tracker_module


def test_cached_feed_reads_survive_restart_without_network(tmp_path: Path) -> None:
    from github_cache import GitHubFeedCache

    calls = []
    payload = {"issues": [{"number": 1433, "title": "Cache", "state": "open"}], "milestones": []}

    def fetch(previous: dict) -> dict:
        calls.append(previous)
        return payload

    path = tmp_path / "feed.json"
    cache = GitHubFeedCache(path, "example/project", fetch, clock=lambda: 100.0)
    assert cache.read()["available"] is False
    assert calls == []
    assert cache.request_refresh() is True
    assert cache.wait_for_refresh(2) is True
    assert cache.read()["issues"][0]["number"] == 1433
    restarted = GitHubFeedCache(path, "example/project", fetch, clock=lambda: 200.0)
    assert restarted.read()["available"] is True
    assert restarted.read()["updated_at"] == 100.0
    assert restarted.read()["stale"] is False
    assert len(calls) == 1


def test_refresh_schedule_and_failure_preserve_last_good_snapshot(tmp_path: Path) -> None:
    from github_cache import GitHubFeedCache

    now = [100.0]
    calls = []

    def fetch(previous: dict) -> dict:
        calls.append(previous)
        if len(calls) > 1:
            raise RuntimeError("GitHub unavailable")
        return {"issues": [{"number": 1433, "title": "Cache", "state": "open"}], "milestones": []}

    path = tmp_path / "feed.json"
    cache = GitHubFeedCache(path, "example/project", fetch, clock=lambda: now[0])
    assert cache.refresh_if_due() is True
    assert cache.wait_for_refresh(2) is True
    for _ in range(10):
        assert cache.read()["available"] is True
        assert cache.refresh_if_due() is False
    now[0] = 1899.0
    assert cache.refresh_if_due() is False
    now[0] = 1900.0
    assert cache.refresh_if_due() is True
    assert cache.wait_for_refresh(2) is True
    assert len(calls) == 2
    assert cache.read()["available"] is True
    assert cache.read()["issues"][0]["number"] == 1433
    assert cache.read()["stale"] is True
    assert "GitHub unavailable" in cache.read()["error"]
    assert cache.refresh_if_due() is False
    assert json.loads(path.read_text())["updated_at"] == 100.0


def test_simultaneous_manual_refreshes_share_one_fetch(tmp_path: Path) -> None:
    from github_cache import GitHubFeedCache

    entered = threading.Event()
    release = threading.Event()
    calls = []

    def fetch(previous: dict) -> dict:
        calls.append(previous)
        entered.set()
        assert release.wait(2)
        return {"issues": [], "milestones": []}

    cache = GitHubFeedCache(tmp_path / "feed.json", "example/project", fetch)
    try:
        assert cache.request_refresh() is True
        assert entered.wait(2)
        assert cache.read()["refreshing"] is True
        assert cache.request_refresh() is False
        assert cache.request_refresh() is False
        assert calls == [{}]
    finally:
        release.set()
        assert cache.wait_for_refresh(2)
    assert cache.read()["refreshing"] is False
    assert cache.request_refresh() is True
    assert cache.wait_for_refresh(2)
    assert len(calls) == 2


def test_tracker_model_extracts_phases_and_queue(tmp_path: Path) -> None:
    tracker = tmp_path / "docs" / "PROJECT-TRACKER.md"
    tracker.parent.mkdir()
    tracker.write_text(
        """# Project0 Tracker\n\n## Phases\n\n| Phase | Status | Exit gate |\n| --- | --- | --- |\n| 1. First playable vertical slice | done | Player moves. |\n| 2. Network proof | in-progress | Client connects. |\n\n## Work queue\n\n- [x] Delivered — first slice\n- [ ] Queued — second slice\n""",
        encoding="utf-8",
    )

    model = load_tracker(tmp_path)

    assert model["available"] is True
    assert model["phases"] == [
        {"number": 1, "name": "First playable vertical slice", "status": "done", "gate": "Player moves."},
        {"number": 2, "name": "Network proof", "status": "in-progress", "gate": "Client connects."},
    ]
    assert model["queue_done"] == 1
    assert model["queue_open"] == 1
    assert model["acceptance"] == []
    assert model["warnings"]


def test_delivery_projection_normalizes_issue_native_fields() -> None:
    model = delivery_projection({"available": True, "issues": [{
        "number": 12, "title": "Ship view", "url": "https://example.test/12", "state": "open",
        "labels": ["Slice", "Outcome: playable proof", "Phase: execution", "Blocked: waiting"],
        "assignees": ["valentin"], "body": "Evidence: test output\nParent feature: #7",
        "milestone_title": "M1",
    }], "milestones": [{"number": 1, "title": "M1", "state": "open"}]})

    assert model["total"] == 1
    assert model["rows"][0]["outcome"] == "playable proof"
    assert model["rows"][0]["phase"] == "execution"
    assert model["rows"][0]["evidence"] == "test output"
    assert model["rows"][0]["parent"] == 7
    assert model["milestones"] == [{"number": 1, "title": "M1", "state": "open"}]
    assert len(model["blocked"]) == 1


def test_github_issue_feed_keeps_issues_beyond_five_pages(monkeypatch) -> None:
    import github_cache

    def fake_api(endpoint: str, etag: str):
        if "/milestones?" in endpoint:
            return 200, {}, []
        page = int(endpoint.rsplit("page=", 1)[1])
        if page <= 6:
            payload = [{"number": page * 100 + offset, "state": "open"} for offset in range(100)]
            if page == 6:
                payload[0]["number"] = 551
            return 200, {}, payload
        return 422, {}, {"message": "pagination limit"}

    monkeypatch.setattr(github_cache, "run_api", fake_api)
    feed = github_cache.fetch_github_feed("example/project", {})

    assert any(issue["number"] == 551 for issue in feed["issues"])


def test_unchanged_github_pages_use_etags_and_keep_complete_feed(monkeypatch) -> None:
    import github_cache

    calls = []

    def fake_api(endpoint: str, etag: str):
        calls.append((endpoint, etag))
        if etag:
            assert etag == '"unchanged"'
            return 304, {}, None
        payload = [{"number": 1433, "title": "Cache", "state": "open"}]
        if "/issues?" in endpoint:
            payload.append({"number": 1434, "pull_request": {}, "state": "open"})
        return 200, {"etag": '"unchanged"'}, payload

    monkeypatch.setattr(github_cache, "run_api", fake_api)
    first = github_cache.fetch_github_feed("example/project", {})
    second = github_cache.fetch_github_feed("example/project", first)
    assert first["issues"] == second["issues"]
    assert first["milestones"] == second["milestones"]
    assert len(second["issues"]) == 1
    assert len(second["milestones"]) == 1
    assert len(calls) == 4
    assert all(etag == '"unchanged"' for _, etag in calls[2:])


def test_dashboard_manual_refresh_is_same_origin_and_browsing_never_fetches(tmp_path: Path, monkeypatch) -> None:
    import app
    from github_cache import GitHubFeedCache

    calls = []
    entered = threading.Event()
    release = threading.Event()

    def fetch(previous: dict) -> dict:
        calls.append(previous)
        entered.set()
        assert release.wait(2)
        return {"issues": [], "milestones": []}

    cache = GitHubFeedCache(tmp_path / "feed.json", "example/project", fetch)
    monkeypatch.setattr(app, "_ISSUE_CACHE", cache)
    server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    connection = HTTPConnection("127.0.0.1", server.server_port, timeout=2)
    try:
        connection.request("GET", "/roadmap")
        response = connection.getresponse()
        page = response.read().decode()
        assert response.status == 200
        assert "Refresh now" in page
        assert "Last successful update" in page
        assert calls == []
        connection.request("GET", "/api/github/status")
        response = connection.getresponse()
        assert response.status == 200
        assert json.loads(response.read())["available"] is False
        assert calls == []
        connection.request("POST", "/api/github/refresh", headers={"Origin": "https://untrusted.test", "X-Dashboard-Refresh": "1"})
        response = connection.getresponse()
        response.read()
        assert response.status == 403
        assert calls == []
        connection.request("POST", "/api/github/refresh")
        response = connection.getresponse()
        response.read()
        assert response.status == 403
        connection.request("POST", "/api/github/refresh", headers={"X-Dashboard-Refresh": "1"})
        response = connection.getresponse()
        assert response.status == 202
        assert json.loads(response.read())["refreshing"] is True
        assert entered.wait(2)
        connection.request("POST", "/api/github/refresh", headers={"X-Dashboard-Refresh": "1"})
        response = connection.getresponse()
        response.read()
        assert response.status == 202
        assert len(calls) == 1
        release.set()
        assert cache.wait_for_refresh(2)
        connection.request("GET", "/api/github/status")
        response = connection.getresponse()
        status = json.loads(response.read())
        assert status["available"] is True
        assert status["refreshing"] is False
        assert status["interval_seconds"] == 1800
        assert len(calls) == 1
    finally:
        release.set()
        cache.wait_for_refresh(2)
        connection.close()
        server.shutdown()
        server.server_close()
        worker.join(2)


def test_delivery_page_shows_source_failure(monkeypatch) -> None:
    import app

    monkeypatch.setattr(app, "github_issues", lambda: {"available": False, "issues": [], "error": "offline"})

    page = render_delivery()

    assert "Project0 — Delivery" in page
    assert "GitHub issue feed unavailable: offline" in page
    assert "Active delivery table" in page


def test_delivery_page_shows_unassigned_open_milestones(monkeypatch) -> None:
    import app

    monkeypatch.setattr(app, "github_issues", lambda: {
        "available": True,
        "issues": [{
            "number": 12, "title": "Ship view", "url": "https://example.test/12", "state": "open",
            "labels": [], "assignees": [], "body": "", "milestone_title": "",
        }],
        "milestones": [{"number": 2, "title": "Phase 16: Client delivery experience", "state": "open"}],
        "error": "",
    })

    page = render_delivery()

    assert "Phase 16: Client delivery experience" in page


def test_roadmap_keeps_milestones_without_compact_prefix() -> None:
    stages = _roadmap_milestones({
        "milestones": [{"number": 2, "title": "Phase 16: Client delivery experience"}],
    })

    assert [stage["title"] for stage in stages] == ["Phase 16: Client delivery experience"]


def test_tracker_model_reports_missing_source(tmp_path: Path) -> None:
    model = load_tracker(tmp_path)

    assert model["available"] is False
    assert model["sections"] == []


def test_inline_markdown_escapes_text_and_links() -> None:
    rendered = inline_markdown('[Tracker](docs/PROJECT-TRACKER.md) <script>')

    assert rendered == '<a href="docs/PROJECT-TRACKER.md">Tracker</a> &lt;script&gt;'


def test_tracker_page_projects_the_committed_record(monkeypatch) -> None:
    import app

    monkeypatch.setattr(app, "REPO", Path.cwd())
    page = render_tracker()

    assert 'Project0 — Tracker Archive' in page
    assert 'Phase gates' in page
    assert 'Implementation slice acceptance' in page
    assert 'Work queue' in page
    assert 'docs/PROJECT-TRACKER.md' in page
    assert 'Live delivery: GitHub Issues and Project #2' in page


def test_tracker_page_renders_source_warnings(tmp_path: Path, monkeypatch) -> None:
    import app

    tracker = tmp_path / "docs" / "PROJECT-TRACKER.md"
    tracker.parent.mkdir()
    tracker.write_text("# Project0 Tracker\n", encoding="utf-8")
    monkeypatch.setattr(app, "REPO", tmp_path)

    page = render_tracker()

    assert "Source warning: missing required section: Tracking system" in page


def test_committed_tracker_matches_schema() -> None:
    assert validate_tracker(Path.cwd()) == []


def test_committed_tracker_preserves_structured_delivery_and_source_fields() -> None:
    model = load_tracker(Path.cwd())

    assert model["schema"]["schema_version"] == 1
    assert model["source"] == "docs/PROJECT-TRACKER.md"
    assert model["delivery"]["order"]
    assert model["delivery"]["parallel_tracks"]
    assert model["delivery"]["dependencies"]
    assert len(model["acceptance"]) == 6
    assert isinstance(model["warnings"], list)


def test_schema_controls_archive_and_required_sections(tmp_path: Path, monkeypatch) -> None:
    archive = tmp_path / "records" / "tracker.md"
    archive.parent.mkdir()
    archive.write_text("# Tracker\n\n## Required by schema\n", encoding="utf-8")
    schema = tmp_path / "tracker_schema.json"
    schema.write_text(
        '{"schema_version": 1, "archive": "records/tracker.md", '
        '"required_sections": ["Required by schema", "Missing by design"], "fields": {}}',
        encoding="utf-8",
    )
    monkeypatch.setattr(tracker_module, "SCHEMA_PATH", schema)

    model = load_tracker(tmp_path)

    assert model["source"] == "records/tracker.md"
    assert model["warnings"] == [
        "missing required section: Missing by design",
        "phase table has no data rows",
        "implementation acceptance checklist has no items",
        "work queue has no items",
    ]


def test_validation_enforces_schema_field_contract(tmp_path: Path, monkeypatch) -> None:
    archive = tmp_path / "tracker.md"
    archive.write_text("# Tracker\n", encoding="utf-8")
    schema = tmp_path / "tracker_schema.json"
    schema.write_text(
        '{"schema_version": 1, "archive": "tracker.md", "required_sections": [], '
        '"fields": {"source_health": ["available", "missing_field"]}}',
        encoding="utf-8",
    )
    monkeypatch.setattr(tracker_module, "SCHEMA_PATH", schema)

    assert "schema field is not projected: source_health.missing_field" in validate_tracker(tmp_path)