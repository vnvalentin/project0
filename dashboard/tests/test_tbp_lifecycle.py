import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1]))
from app import _delivery_slice_ready, _delivery_slice_state, _tbp_next_branch, _tbp_render_node, classify_tbp_state, render_roadmap

def issue(state="open", body="## Outcomes\n- [x] validated"):
    return {"state": state, "body": body, "labels": []}
def test_refinement_ready():
    assert classify_tbp_state(issue()) == "READY_TO_PULL"


def test_slice_is_new_without_parent_and_delivery_contract():
    slice_issue = {"labels": ["Slice"], "state": "open", "body": "Acceptance: define this later"}
    assert _delivery_slice_ready(slice_issue) is False
    assert _delivery_slice_state(slice_issue) == "NEEDS_GRILLING"


def test_slice_is_ready_with_parent_and_delivery_contract():
    slice_issue = {"labels": ["Slice"], "state": "open", "body": "Parent feature: #42\n\nAcceptance:\n- validated"}
    assert _delivery_slice_ready(slice_issue) is True
    assert _delivery_slice_state(slice_issue) == "READY_TO_PULL"


def test_slice_state_prioritizes_doing_and_done():
    doing = {"labels": ["Slice", "tbp:in-progress"], "state": "open", "body": "Parent feature: #42"}
    done = {"labels": ["Slice"], "state": "closed", "body": "Parent feature: #42"}
    assert _delivery_slice_state(doing) == "IN_PROGRESS"
    assert _delivery_slice_state(done) == "DONE"
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


def test_closed_epic_with_metric_and_done_experiment_is_done():
    epic = {
        "state": "closed",
        "labels": ["tbp:epic"],
        "body": "## Measurable Metric\nA completed metric.\n\n## Experiments\n- [Experiment](https://github.com/vnvalentin/project0/issues/571)",
    }
    experiment = {"tbp_state": "DONE"}
    assert classify_tbp_state(epic, [experiment]) == "DONE"


def test_fleshed_out_feature_with_declared_epic_is_not_needs_grilling():
    feature = {
        **issue(),
        "labels": ["tbp:feature"],
        "body": "## Ideal Condition\nideal\n\n## Current Condition\ncurrent\n\n## Measurable Component\nmetric\n\n## Epics (Gaps)\n- [ ] [Epic: schema](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(feature) == "READY_TO_PULL"


def test_fleshed_out_feature_does_not_inherit_child_grilling_state():
    feature = {
        **issue(),
        "labels": ["tbp:feature"],
        "body": "## Measurable Component\nmetric\n\n## Epics (Gaps)\n- [ ] [Epic](https://github.com/example/project/issues/1)",
    }
    assert classify_tbp_state(feature, [{"tbp_state": "NEEDS_GRILLING"}]) == "READY_TO_PULL"


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


def _roadmap_issue(number, title, labels, body="", updated_at=""):
    return {
        "number": number, "title": title, "url": f"https://example.test/{number}",
        "state": "open", "labels": labels, "body": body, "updated_at": updated_at,
    }


def test_roadmap_view_renders_collapsible_layered_story_map(monkeypatch):
    hoshin = _roadmap_issue(1, "Hoshin: World", ["tbp:hoshin"])
    theme = _roadmap_issue(2, "Theme: Identity", ["tbp:theme"], "Parent Hoshin: #1\n## Problem Statement\nproblem\n## Measurable Outcome\noutcome\n## Feature\n- [ ] #3")
    feature = _roadmap_issue(3, "Feature: Enrollment", ["tbp:feature"], "Parent Theme: #2\n## Measurable Component\nmetric\n## Epics (Gaps)\n- [ ] #4")
    epic = _roadmap_issue(4, "Epic: Account", ["tbp:epic"], "Parent Feature: #3\n## Experiments\n- [ ] #5")
    experiment = _roadmap_issue(5, "Experiment: Login", ["tbp:experiment", "tbp:needs-grilling"], "Parent Epic: #4")
    monkeypatch.setattr("app.github_issues", lambda: {"available": True, "issues": [hoshin, theme, feature, epic, experiment], "error": ""})

    page = render_roadmap()

    assert "Full backlog" in page
    assert 'class="story-map-root"' in page
    assert 'class="story-map-node level-hoshin" open' not in page
    assert 'class="story-map-node level-theme"' in page
    assert 'class="story-map-node level-theme" open' not in page
    for label in ("Hoshin", "Theme", "Feature", "Epic", "Experiment"):
        assert f'class="story-map-layer-label level-{label.lower()}">{label}</span>' in page
    assert "Hoshin: World" not in page and "Experiment: Login" not in page
    assert "#2 Identity" in page
    assert "story-map-node-preview" not in page
    assert "story-map-counts" in page
    assert "Ready 1" in page
    assert "New 0" in page
    assert "Doing 0" in page
    assert "Done 0" in page
    assert "NEEDS GRILLING" not in page


def test_next_branch_prefers_most_recent_in_progress_leaf():
    older = {**_roadmap_issue(5, "Experiment: Older", ["tbp:experiment", "tbp:in-progress"], updated_at="2026-01-01"), "children": []}
    newer = {**_roadmap_issue(6, "Experiment: Newer", ["tbp:experiment", "tbp:in-progress"], updated_at="2026-02-01"), "children": []}
    result = _tbp_next_branch([
        {**_roadmap_issue(1, "Hoshin", ["tbp:hoshin"]), "children": [{**_roadmap_issue(2, "Theme", ["tbp:theme"]), "children": [{**_roadmap_issue(3, "Feature", ["tbp:feature"]), "children": [{**_roadmap_issue(4, "Epic", ["tbp:epic"]), "children": [older, newer]}]}]}]}
    ])
    assert result["active"] is True
    assert result["path"][-1]["number"] == 6


def test_next_branch_labels_ready_fallback_as_inactive():
    ready = {**_roadmap_issue(9, "Experiment: Ready", ["tbp:experiment"]), "children": []}
    result = _tbp_next_branch([{**_roadmap_issue(1, "Hoshin", ["tbp:hoshin"]), "children": [ready]}])
    assert result["active"] is False
    assert result["path"][-1]["number"] == 9


def test_roadmap_view_keeps_unlinked_and_unavailable_states_visible(monkeypatch):
    unlinked = _roadmap_issue(964, "Feature: Orphan", ["tbp:feature"])
    monkeypatch.setattr("app.github_issues", lambda: {"available": True, "issues": [unlinked], "error": ""})
    page = render_roadmap()
    assert "Unlinked TBP issues" in page
    assert "Feature: Orphan" in page

    monkeypatch.setattr("app.github_issues", lambda: {"available": False, "issues": [], "error": "network down"})
    assert "GitHub issues unavailable: network down" in render_roadmap()
