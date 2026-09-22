import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1]))
from app import _tbp_render_node, classify_tbp_state, render_roadmap

def issue(state="open", body="## Outcomes\n- [x] validated"):
    return {"state": state, "body": body, "labels": []}
def test_refinement_ready():
    assert classify_tbp_state(issue()) == "READY_TO_PULL"
def test_child_needs_grilling_blocks_parent():
    assert classify_tbp_state(issue(), [dict(issue(), tbp_state="NEEDS_GRILLING")]) == "NEEDS_GRILLING"
def test_child_in_progress_blocks_parent():
    assert classify_tbp_state(issue(), [dict(issue(), tbp_state="IN_PROGRESS")]) == "IN_PROGRESS"
def test_closed_all_outcomes_complete():
    assert classify_tbp_state(issue("closed")) == "DONE"
def test_missing_or_unchecked_outcomes_are_not_complete():
    assert classify_tbp_state(issue("closed", "# Work")) == "NEEDS_GRILLING"
    assert classify_tbp_state(issue("closed", "## Outcomes\n- [ ] pending")) == "NEEDS_GRILLING"
def test_closed_experiment_requires_pass():
    assert classify_tbp_state({"state": "closed", "type": "experiment", "body": "## Outcomes\n- [x] other", "labels": []}) == "NEEDS_GRILLING"
    assert classify_tbp_state({"state": "closed", "type": "experiment", "body": "## Outcomes\n- [x] Pass", "labels": []}) == "DONE"


def test_childless_feature_needs_grilling():
    assert classify_tbp_state({**issue(), "labels": ["tbp:feature"]}) == "NEEDS_GRILLING"


def test_childless_epic_needs_grilling_even_when_closed():
    assert classify_tbp_state({**issue("closed"), "labels": ["tbp:epic"]}) == "NEEDS_GRILLING"


def test_feature_and_epic_with_children_keep_child_derived_state():
    feature = {**issue(), "labels": ["tbp:feature"]}
    epic = {**issue(), "labels": ["tbp:epic"]}
    child = {**issue(), "tbp_state": "READY_TO_PULL"}
    assert classify_tbp_state(feature, [child]) == "READY_TO_PULL"
    assert classify_tbp_state(epic, [{**child, "tbp_state": "IN_PROGRESS"}]) == "IN_PROGRESS"


def test_rendered_epic_uses_its_recognized_child_state():
    epic = {**issue(), "number": 939, "title": "Epic", "url": "https://example.test/939", "labels": ["tbp:epic"]}
    experiment = {**issue(), "number": 942, "title": "Experiment", "url": "https://example.test/942", "tbp_state": "READY_TO_PULL"}
    buckets = {"NEEDS_GRILLING": [], "READY_TO_PULL": [], "IN_PROGRESS": []}

    rendered = _tbp_render_node({**epic, "children": [experiment]}, buckets)

    assert any(item["number"] == 939 for item in buckets["READY_TO_PULL"])
    assert all(item["number"] != 939 for item in buckets["NEEDS_GRILLING"])
    assert 'class="tbp-badge READY_TO_PULL"' in rendered


def test_roadmap_view_is_separate_and_keeps_tbp_navigation(monkeypatch):
    monkeypatch.setattr("app.github_issues", lambda: {"available": True, "issues": [], "error": ""})
    page = render_roadmap()
    assert "Project0 — Roadmap" in page
    assert "Rolling delivery horizons" in page
    assert 'href="/roadmap"' in page
    assert 'href="/tbp">TBP View</a>' in page
