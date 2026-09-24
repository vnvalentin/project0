import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from app import delivery_projection, render_delivery, render_tracker
from tracker import inline_markdown, load_tracker, validate_tracker
import tracker as tracker_module


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
    import app

    class FakeResponse:
        def __init__(self, payload: list[dict]) -> None:
            self.payload = payload

        def __enter__(self):
            return self

        def __exit__(self, *_args) -> None:
            return None

        def read(self) -> bytes:
            return json.dumps(self.payload).encode("utf-8")

    def fake_urlopen(request, timeout: int):
        assert timeout == 5
        if "/milestones?" in request.full_url:
            return FakeResponse([])
        page = int(request.full_url.rsplit("page=", 1)[1])
        if page <= 5:
            return FakeResponse([{"number": page * 100 + offset, "state": "open"} for offset in range(100)])
        return FakeResponse([{
            "number": 551,
            "title": "JIT generation + canon re-entry",
            "html_url": "https://example.test/551",
            "state": "open",
            "labels": [],
            "assignees": [],
            "body": "",
            "updated_at": "",
        }])

    monkeypatch.setattr(app, "urlopen", fake_urlopen)
    app._ISSUE_CACHE.update({"at": 0.0, "data": {"available": False}})

    feed = app.github_issues()

    assert feed["available"] is True
    assert any(issue["number"] == 551 for issue in feed["issues"])


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