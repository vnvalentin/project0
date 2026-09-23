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


def test_childless_theme_needs_grilling():
    assert classify_tbp_state({**issue(), "labels": ["tbp:theme"]}) == "NEEDS_GRILLING"


def test_childless_epic_needs_grilling_even_when_closed():
    assert classify_tbp_state({**issue("closed"), "labels": ["tbp:epic"]}) == "NEEDS_GRILLING"


def test_fleshed_out_feature_with_declared_epic_is_not_needs_grilling():
    feature = {
        **issue(),
        "labels": ["tbp:feature"],
        "body": "## Ideal Condition\nideal\n\n## Current Condition\ncurrent\n\n## Measurable Component\nmetric\n\n## Epics (Gaps)\n- [ ] [Epic: schema](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(feature) == "READY_TO_PULL"


def test_feature_without_linked_epic_for_its_measurable_measure_needs_grilling():
    feature = {
        **issue(),
        "labels": ["tbp:feature"],
        "body": "## Ideal Condition\nideal\n\n## Current Condition\ncurrent\n\n## Measurable Component\nmetric\n\n## Epics (Gaps)\n- [ ] define an Epic later",
    }
    assert classify_tbp_state(feature) == "NEEDS_GRILLING"


def test_feature_without_measurable_measure_needs_grilling_even_with_epic():
    feature = {
        **issue(),
        "labels": ["tbp:feature"],
        "body": "## Ideal Condition\nideal\n\n## Current Condition\ncurrent\n\n## Epics (Gaps)\n- [ ] [Epic: schema](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(feature) == "NEEDS_GRILLING"


def test_fleshed_out_theme_with_declared_feature_is_not_needs_grilling():
    theme = {
        **issue(),
        "labels": ["tbp:theme"],
        "body": "## Problem Statement\nproblem\n\n## Measurable Outcome\noutcome\n\n## Feature\n- [ ] [Feature: flow](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(theme) == "READY_TO_PULL"


def test_theme_without_linked_feature_for_its_measurable_gap_needs_grilling():
    theme = {
        **issue(),
        "labels": ["tbp:theme"],
        "body": "## Problem Statement\nproblem\n\n## Measurable Outcome\noutcome\n\n## Features\n- [ ] define a feature later",
    }
    assert classify_tbp_state(theme) == "NEEDS_GRILLING"


def test_theme_without_measurable_outcome_needs_grilling_even_with_feature():
    theme = {
        **issue(),
        "labels": ["tbp:theme"],
        "body": "## Problem Statement\nproblem\n\n## Features\n- [ ] [Feature: flow](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(theme) == "NEEDS_GRILLING"


def test_fleshed_out_epic_with_declared_experiment_is_not_needs_grilling():
    epic = {
        **issue(),
        "labels": ["tbp:epic"],
        "body": "## The 4Ws\n\n## Root Cause\nroot\n\n## Measurable Metric\nmetric\n\n## Experiments\n- [ ] [Experiment: schema](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(epic) == "READY_TO_PULL"


def test_feature_and_epic_with_children_keep_child_derived_state():
    feature = {
        **issue(),
        "labels": ["tbp:feature"],
        "body": "## Measurable Component\nmetric\n\n## Epics (Gaps)\n- [ ] [Epic: schema](https://github.com/example/project/issues/1)",
    }
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


def test_roadmap_view_labels_expected_issue_for_each_milestone(monkeypatch):
    issue = {
        "number": 551,
        "title": "Feature: Player-triggered JIT world generation and canon re-entry",
        "url": "https://github.com/vnvalentin/project0/issues/551",
        "state": "open",
        "labels": [],
    }
    monkeypatch.setattr("app.github_issues", lambda: {"available": True, "issues": [issue], "error": ""})
    page = render_roadmap()
    assert "Expected issue" in page
    assert "#551 Feature: Player-triggered JIT world generation and canon re-entry" in page
    assert "READY</span>" in page
    assert "READY TO PULL" not in page


def test_roadmap_view_renders_feature_epic_experiment_breakdown(monkeypatch):
    feature = {
        **issue(), "number": 551, "title": "Feature: JIT generation", "url": "https://example.test/551",
        "labels": ["tbp:feature"],
    }
    epic = {
        **issue(), "number": 985, "title": "Epic: Schema gate", "url": "https://example.test/985",
        "labels": ["tbp:epic"], "body": "Parent feature: #551\n## Experiments\n- [ ] #994",
    }
    experiment = {
        **issue(), "number": 994, "title": "Experiment: Blueprint fallback", "url": "https://example.test/994",
        "labels": ["tbp:experiment", "tbp:needs-grilling"], "body": "Parent epic: #985\n## Outcomes\n- [ ] Pass",
    }
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": [feature, epic, experiment], "error": "",
    })

    page = render_roadmap()

    assert "Feature: JIT generation" in page
    assert "Epic: Schema gate" in page
    assert "Experiment: Blueprint fallback" in page
    assert "TBP NEEDS GRILLING" in page
    assert "GitHub open" in page


def test_roadmap_view_applies_experiment_pass_gate_without_internal_type(monkeypatch):
    epic = {
        **issue(), "number": 561, "title": "Epic: Lore path", "url": "https://example.test/561",
        "labels": ["tbp:epic"],
    }
    experiment = {
        "number": 571, "title": "Experiment: Lore flow", "url": "https://example.test/571",
        "state": "closed", "labels": ["tbp:experiment"],
        "body": "Parent epic: #561\n## Outcomes\n- [x] other",
    }
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": [epic, experiment], "error": "",
    })

    page = render_roadmap()

    assert "#571 Experiment: Lore flow" in page
    assert "GitHub closed" in page
    assert "NEEDS GRILLING" in page


def test_roadmap_view_marks_undefined_epic_breakdown(monkeypatch):
    feature = {
        **issue(), "number": 964, "title": "Feature: Context bounds", "url": "https://example.test/964",
        "labels": ["tbp:feature"],
    }
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": [feature], "error": "",
    })

    page = render_roadmap()

    assert "#964 Feature: Context bounds" in page
    assert "No linked Epics defined yet" in page
    assert "No linked Experiments defined yet" in page
