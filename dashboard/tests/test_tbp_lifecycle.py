import sys
from pathlib import Path
import pytest
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

    page = render_roadmap("backlog")

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
    page = render_roadmap("backlog")
    assert "Unlinked TBP issues" in page
    assert "Feature: Orphan" in page

    monkeypatch.setattr("app.github_issues", lambda: {"available": False, "issues": [], "error": "network down"})
    assert "GitHub issues unavailable: network down" in render_roadmap("backlog")


@pytest.mark.parametrize("selection", [None, "", "delivery-a", "unknown"])
def test_default_roadmap_is_bands_with_explicit_backlog_link(monkeypatch, selection):
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": [],
        "milestones": [{"number": 1, "title": "Track A", "description": "Outcome: Trusted entry."}],
    })
    page = render_roadmap() if selection is None else render_roadmap(selection)
    assert page == render_roadmap("delivery-a")
    assert "<h2>Milestone delivery</h2>" in page
    assert 'href="/roadmap">Bands</a>' in page
    assert "Delivery plan mockup" not in page
    assert 'class="milestone-band"' in page
    assert 'href="/roadmap?mockup=backlog">Backlog</a>' in page
    assert "Full backlog" not in page


def test_default_bands_retains_source_warning(monkeypatch):
    monkeypatch.setattr("app.github_issues", lambda: {"available": False, "error": "network down"})
    assert "GitHub issues unavailable: network down" in render_roadmap()


@pytest.mark.parametrize("selection", ["", "delivery-a", "delivery-b", "delivery-c", "delivery-d"])
def test_numbered_milestones_sort_numerically_and_keep_original_links(monkeypatch, selection):
    milestones = [
        {"number": number, "title": f"Milestone {order}: Outcome", "description": ""}
        for number, order in [(2, 10), (15, 1), (14, 0), (1, 2)]
    ]
    milestones[2]["description"] = "## Slices\n" + _mapped_slice_definition("M0.1")
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True,
        "issues": [{**_roadmap_issue(7, "Standalone entry", []), "milestone_number": 14}],
        "milestones": milestones,
    })

    page = render_roadmap(selection)

    positions = [page.index(f"Milestone {order}: Outcome") for order in [0, 1, 2, 10]]
    assert positions == sorted(positions)
    if selection in {"", "delivery-a"}:
        assert 'data-slice-id="M0.1"' in page
        assert 'href="/roadmap?milestone=14&amp;slice=M0.1"' in page
        assert "Milestone 14:" not in page


def test_hybrid_view_combines_schedule_status_and_slice_details(monkeypatch):
    description = "## Slice Mapping\n" + _mapped_slice_definition("M0.1")
    issue = {**_roadmap_issue(7, "Closed work", []), "milestone_number": 1, "state": "closed"}
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True,
        "issues": [issue],
        "milestones": [{
            "number": 1,
            "title": "Milestone 1: Accepted",
            "state": "closed",
            "due_on": "2026-10-01T00:00:00Z",
            "description": description,
        }],
    })

    page = render_roadmap("delivery-d")

    assert "Hybrid" in page
    assert "Done" in page
    assert "2026-10-01" in page
    assert "Slices 1/1 done" in page
    assert 'data-slice-id="M0.1"' in page
    assert 'href="#hybrid-slice-1-M0-1"' in page
    assert 'id="hybrid-slice-1-M0-1" class="milestone-slice"' in page


def test_bands_reads_description_slice_groups_not_issue_labels(monkeypatch):
    description = """Outcome: Trusted entry.
## Slice Mapping
### Slice A1: Trusted First Install
Outcome: Verified installation.
Included issues:
- #7
- #8
Complete when: Windows acceptance passes.
Dependency: Artifact trust first.
### Slice A2: Safe Update
Outcome: Verified update.
Included issues:
- #9
Complete when: Update acceptance passes.
## Required Scope Awaiting Slice Definition
- Controller parity remains required.
"""
    issues = [
        {**_roadmap_issue(7, "Feature: Install", ["tbp:feature"]), "milestone_number": 1},
        {**_roadmap_issue(8, "Experiment: Entry", ["tbp:experiment"], "Parent feature: #7"), "milestone_number": 1},
        {**_roadmap_issue(9, "Epic: Update", ["tbp:epic"]), "milestone_number": 1},
        {**_roadmap_issue(10, "Release continuity", ["tbp:theme"]), "milestone_number": 1},
        {**_roadmap_issue(11, "Input parity", ["tbp:theme"]), "milestone_number": 1},
        {**_roadmap_issue(12, "Legacy Slice", ["Slice"]), "milestone_number": 1},
    ]
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": issues,
        "milestones": [{"number": 1, "title": "Track A", "state": "open", "description": description}],
    })

    page = render_roadmap("delivery-a")

    assert "Slice delivery: 0/2 complete" in page
    assert page.count('class="milestone-slice"') == 2
    assert 'data-slice-id="A1"' in page
    assert 'data-slice-id="A2"' in page
    assert "Trusted First Install" in page and "Windows acceptance passes." not in page
    assert "Shared Context sections are not allowed" not in page
    assert "Unmapped milestone work (3)" in page and "Release continuity" in page
    assert "Unmapped milestone work" in page and "Input parity" in page
    assert "Required scope awaiting Slice definition" in page
    assert "Controller parity remains required." in page
    assert "### Slice" not in page


def test_solo_and_shared_milestones_keep_approved_slice_groups(monkeypatch):
    groups = {
        14: (0, ["Standalone Entry", "Movement and Traversal", "Solo Combat", "Mind versus Tool"]),
        15: (1, ["Shared Exploration", "Co-op Combat"]),
    }
    milestones, issues = [], []
    for milestone_number, (order, titles) in groups.items():
        description = "Outcome: Playable runtime proof.\n## Slice Mapping\n"
        for index, title in enumerate(titles, 1):
            number = milestone_number * 10 + index
            description += (
                f"### Slice M{order}.{index}: {title}\nOutcome: {title}.\n"
                f"Included issues:\n- #{number}\nComplete when: Runtime proof passes.\n"
                "Dependency: Existing authoritative runtime.\n"
            )
            issues.append({**_roadmap_issue(number, title, []), "milestone_number": milestone_number})
        milestones.append({"number": milestone_number, "title": f"Milestone {order}: Playable", "description": description})
    monkeypatch.setattr("app.github_issues", lambda: {"available": True, "issues": issues, "milestones": milestones})

    page = render_roadmap()

    assert page.count('class="milestone-band"') == 2
    assert page.count('class="milestone-slice"') == 6
    assert "Slice delivery: 0/4 complete" in page
    assert "Slice delivery: 0/2 complete" in page
    assert "Unmapped milestone work" not in page
    assert "Unresolved scope or mapping" not in page
    for order, titles in groups.values():
        for index, title in enumerate(titles, 1):
            assert f"Slice M{order}.{index}: {title}" in page


def _mapped_bands_page(monkeypatch, description, issues):
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": issues,
        "milestones": [{"number": 1, "title": "Track A", "state": "open", "description": description}],
    })
    return render_roadmap("delivery-a")


def _mapped_slice_definition(identifier="A1", members="- #7", evidence=""):
    return (
        f"### Slice {identifier}: Trusted entry\nOutcome: Verified installation.\n"
        f"Included issues:\n{members}\nComplete when: Windows acceptance passes.\n"
        f"{evidence}\n"
    )


def test_bands_compact_members_link_to_slice_description(monkeypatch):
    members = [
        {**_roadmap_issue(7, "Closed work", ["tbp:in-progress"]), "milestone_number": 1, "state": "closed"},
        {**_roadmap_issue(8, "Active work", [], "Status: In Progress"), "milestone_number": 1},
        {**_roadmap_issue(9, "Open work", []), "milestone_number": 1},
    ]
    description = "## Slices\n" + _mapped_slice_definition(members="- #7\n- #8\n- #9") + "Dependency: Verified payload.\n"
    page = _mapped_bands_page(monkeypatch, description, members)

    assert '>#7</a>' in page and '>#8</a>' in page and '>#9</a>' in page
    for status in ("closed", "active", "open"):
        assert f'class="issue-status {status}"' in page
        assert f'>{status.title()}</span>' in page
    assert "Verified installation." not in page
    assert "Windows acceptance passes." not in page
    assert "Verified payload." not in page
    assert 'class="milestone-counts"' not in page
    assert 'class="milestone-slice-state"' not in page
    assert "New · 7 issues · Member readiness not established" not in page
    assert 'href="/roadmap?milestone=1&amp;slice=A1"' in page

    detail = render_roadmap(milestone_number="1", slice_id="A1")
    assert "Slice A1: Trusted entry" in detail
    assert "<dt>Outcome</dt><dd>Verified installation.</dd>" in detail
    assert "<dt>Completion description</dt><dd>Windows acceptance passes.</dd>" in detail
    assert "<dt>Dependency</dt><dd>Verified payload.</dd>" in detail
    assert '>Back to roadmap</a>' in detail


def test_slice_description_is_scoped_to_milestone_and_escapes_text(monkeypatch):
    description = "## Slices\n" + _mapped_slice_definition("A&B").replace("Verified installation.", "<script>unsafe</script>")
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "issues": [], "milestones": [
            {"number": 1, "title": "Track A", "description": description},
            {"number": 2, "title": "Track B", "description": description.replace("<script>unsafe</script>", "Second milestone outcome.")},
        ],
    })
    assert 'href="/roadmap?milestone=1&amp;slice=A%26B"' in render_roadmap()
    first = render_roadmap(milestone_number="1", slice_id="A&B")
    assert "&lt;script&gt;unsafe&lt;/script&gt;" in first
    assert "<script>unsafe</script>" not in first
    assert "<dt>Dependency</dt><dd>Not specified</dd>" in first
    second = render_roadmap(milestone_number="2", slice_id="A&B")
    assert "Second milestone outcome." in second
    assert "unsafe" not in second


@pytest.mark.parametrize("milestone,slice_id,duplicate", [
    ("999", "A1", False),
    ("1", "missing", False),
    ("1", "", False),
    ("1", "A1", True),
])
def test_slice_description_rejects_missing_or_ambiguous_selection(monkeypatch, milestone, slice_id, duplicate):
    description = "## Slices\n" + _mapped_slice_definition() * (2 if duplicate else 1)
    _mapped_bands_page(monkeypatch, description, [])
    page = render_roadmap(milestone_number=milestone, slice_id=slice_id)
    assert "Slice description unavailable" in page
    assert "Verified installation." not in page
    assert '>Back to roadmap</a>' in page


def test_slice_description_retains_source_warning(monkeypatch):
    monkeypatch.setattr("app.github_issues", lambda: {"available": False, "error": "network down"})
    page = render_roadmap(milestone_number="1", slice_id="A1")
    assert "GitHub issues unavailable: network down" in page
    assert '>Back to roadmap</a>' in page


@pytest.mark.parametrize("labels,closed,evidence,expected,reason", [
    ([], False, "", "new", "Member readiness not established"),
    (["tbp:ready-to-pull"], False, "", "ready", "All remaining members ready"),
    (["tbp:in-progress"], False, "", "doing", "Included work in progress"),
    (["blocked", "tbp:ready-to-pull"], False, "", "new", "Blocked or needs definition"),
    ([], True, "", "doing", "Awaiting outcome evidence"),
    ([], True, "Outcome evidence: https://example.test/acceptance", "done", "outcome evidence linked"),
    ([], True, "Outcome evidence: TBD", "doing", "Awaiting outcome evidence"),
])
def test_bands_group_status_requires_explicit_readiness_and_outcome_evidence(monkeypatch, labels, closed, evidence, expected, reason):
    member = {**_roadmap_issue(7, "Entry", labels), "milestone_number": 1, "state": "closed" if closed else "open"}
    page = _mapped_bands_page(monkeypatch, "## Slices\n" + _mapped_slice_definition(evidence=evidence), [member])
    assert f'data-slice-id="A1" data-state="{expected}"' in page
    assert reason in page
    assert f'Slice delivery: {1 if expected == "done" else 0}/1 complete' in page


def test_closed_milestone_accepts_closed_groups_without_duplicate_outcome_evidence(monkeypatch):
    member = {**_roadmap_issue(7, "Accepted entry", []), "milestone_number": 1, "state": "closed"}
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True,
        "issues": [member],
        "milestones": [{
            "number": 1,
            "title": "Milestone 1: Accepted",
            "state": "closed",
            "description": "## Slice Mapping\n" + _mapped_slice_definition(),
        }],
    })

    page = render_roadmap("delivery-a")

    assert 'data-slice-id="A1" data-state="done"' in page
    assert "All members closed; milestone is closed" in page
    assert "Slice delivery: 1/1 complete" in page


def test_bands_reports_duplicate_missing_and_foreign_members(monkeypatch):
    description = "## Slice Mapping\n" + _mapped_slice_definition(members="- #7\n- #7\n- #404\n- #9") + _mapped_slice_definition("A2")
    issues = [
        {**_roadmap_issue(7, "Entry", ["tbp:ready-to-pull"]), "milestone_number": 1},
        {**_roadmap_issue(9, "Other track", ["tbp:ready-to-pull"]), "milestone_number": 2},
    ]
    page = _mapped_bands_page(monkeypatch, description, issues)
    assert "Duplicate membership #7" in page
    assert "Unresolved issue #404" in page
    assert "Issue #9 is not assigned to this milestone." in page
    assert 'data-slice-id="A1" data-state="new"' in page
    assert 'data-slice-id="A2" data-state="new"' in page
    assert "Slice delivery: 0/2 complete" in page
    assert page.count("Issues: 0/1 closed") == 3
    assert "Issues: 0/4 closed" not in page


def test_bands_accepts_slice_annotations_between_members_and_completion(monkeypatch):
    description = """## Slice Mapping
### Slice M2.2: Make a Lasting Change
Outcome: A valid player interaction unlocks the selected gate.
Included issues:
- #7
Capability owner: #8.
Complete when: The committed change is durable.
Dependency: M2.1.
"""
    member = {**_roadmap_issue(7, "Closed work", []), "milestone_number": 2, "state": "closed"}
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True,
        "issues": [member],
        "milestones": [{
            "number": 2,
            "title": "Milestone 2: Durable return",
            "state": "closed",
            "description": description,
        }],
    })

    page = render_roadmap("delivery-a")

    assert 'data-slice-id="M2.2" data-state="done"' in page
    assert "Invalid member entry: Capability owner: #8." not in page


def test_bands_shows_member_activity_without_relaxing_acceptance(monkeypatch):
    members = [
        {**_roadmap_issue(7, "Accepted change", []), "milestone_number": 1, "state": "closed"},
        {**_roadmap_issue(8, "Current experiment", [], "## Status\n\nIn progress: collecting evidence."), "milestone_number": 1},
        {**_roadmap_issue(9, "Undefined work", []), "milestone_number": 1},
    ]
    page = _mapped_bands_page(monkeypatch, "## Slices\n" + _mapped_slice_definition(members="- #7\n- #8\n- #9"), members)

    assert page.count("Issues: 1/3 closed") == 2
    assert page.count("Active 1") == 2
    assert 'class="issue-status active"' in page
    assert 'data-slice-id="A1" data-state="new"' in page
    assert "Member readiness not established" in page
    assert "Slice delivery: 0/1 complete" in page


def test_bands_fenced_examples_and_other_sections_are_not_membership(monkeypatch):
    description = "Outcome: Safe entry.\n## Slice Mapping\n```markdown\n" + _mapped_slice_definition("DEMO") + "```\n"
    description += _mapped_slice_definition() + "## Shared Context\n- #9\n## Notes\n### Slice NOT-A-SLICE: Example\nIncluded issues:\n- #10\n"
    description = description.replace("\n", "\r\n")
    members = [{**_roadmap_issue(number, f"Issue {number}", []), "milestone_number": 1} for number in (7, 9, 10)]
    page = _mapped_bands_page(monkeypatch, description, members)
    assert page.count('class="milestone-slice"') == 1
    assert "Slice delivery: 0/1 complete" in page
    assert "Unmapped milestone work (2)" in page


def test_bands_shared_context_section_is_a_mapping_warning_not_an_exemption(monkeypatch):
    description = "Outcome: Safe entry.\n## Slice Mapping\n" + _mapped_slice_definition() + "## Shared Context\n- #9 Parent theme\n"
    members = [{**_roadmap_issue(number, f"Issue {number}", []), "milestone_number": 1, "state": "closed"} for number in (7, 9)]
    page = _mapped_bands_page(monkeypatch, description, members)
    assert "Shared Context sections are not allowed" in page
    assert "Unresolved scope or mapping requires attention." in page
    assert "Unmapped milestone work (1)" in page


def test_slice_context_line_is_shown_without_creating_membership(monkeypatch):
    definition = _mapped_slice_definition(evidence="Context: #495 Vision and authority boundaries.")
    members = [{**_roadmap_issue(7, "Issue 7", []), "milestone_number": 1, "state": "closed"}]
    _mapped_bands_page(monkeypatch, "Outcome: Safe entry.\n## Slice Mapping\n" + definition, members)
    detail = render_roadmap(milestone_number="1", slice_id="A1")
    assert "<dt>Context</dt><dd>#495 Vision and authority boundaries.</dd>" in detail
    assert "Vision" not in detail.split("Included issues", 1)[1]
    page = render_roadmap("delivery-a")
    assert "Unresolved scope or mapping requires attention." not in page


def test_bands_no_definition_does_not_infer_slices_from_labels(monkeypatch):
    members = [
        {**_roadmap_issue(7, "Legacy Slice", ["Slice"]), "milestone_number": 1, "state": "closed"},
        {**_roadmap_issue(8, "Current Slice", ["Slice"], "Status: In Progress"), "milestone_number": 1},
    ]
    page = _mapped_bands_page(monkeypatch, "Outcome: Safe entry.", members)
    assert "No Slices defined in milestone description." in page
    assert "Outcome acceptance: not defined" in page
    assert "Slice delivery: 0/0 complete" not in page
    assert "Issues: 1/2 closed" in page and "Active 1" in page
    assert "Unmapped milestone work (2)" in page
    assert 'class="milestone-slice"' not in page


def test_bands_gate_only_slice_is_visible_but_excluded_from_delivery_count(monkeypatch):
    description = """## Slice Mapping
### Slice M8.1: Delivery work
Outcome: The delivery issue is resolved.
Included issues:
- #7
Complete when: The issue is closed.
Dependency: None.
### Slice M8.2: Validation authority
Outcome: Required validation gates are explicit.
Membership: acceptance-gate-only
Included issues:
Complete when: All applicable gates pass.
Dependency: Exact-source candidate.
"""
    member = {**_roadmap_issue(7, "Delivery issue", []), "milestone_number": 1}
    page = _mapped_bands_page(monkeypatch, description, [member])

    assert 'data-slice-id="M8.2" data-state="gate"' in page
    assert "Acceptance gate" in page
    assert "Slice delivery: 0/1 complete" in page
    assert "No included issues defined." not in page
    assert "Unresolved scope or mapping requires attention." not in page


@pytest.mark.parametrize(
    "membership,members,expected_warning",
    [
        ("acceptance-gate-only", "- #7", "Acceptance-gate-only groups cannot include delivery issues."),
        ("future-membership", "", "Unknown membership type: future-membership."),
    ],
)
def test_bands_invalid_gate_membership_fails_closed(monkeypatch, membership, members, expected_warning):
    description = (
        "## Slice Mapping\n"
        "### Slice M8.2: Validation authority\n"
        "Outcome: Required validation gates are explicit.\n"
        f"Membership: {membership}\n"
        f"Included issues:\n{members}\n"
        "Complete when: All applicable gates pass.\n"
        "Dependency: Exact-source candidate.\n"
    )
    issues = [{**_roadmap_issue(7, "Issue 7", []), "milestone_number": 1}] if members else []
    page = _mapped_bands_page(monkeypatch, description, issues)

    assert expected_warning in page
    assert "Unresolved scope or mapping requires attention." in page


def test_bands_unmarked_empty_delivery_group_still_warns(monkeypatch):
    page = _mapped_bands_page(monkeypatch, "## Slice Mapping\n" + _mapped_slice_definition(members=""), [])

    assert "No included issues defined." in page
    assert "Unresolved scope or mapping requires attention." in page
    assert "Slice delivery: 0/1 complete" in page


@pytest.mark.parametrize("labels,body,state,active,blocked", [
    (["tbp:in-progress", "blocked"], "", "open", 1, 1),
    (["tbp:in-progress", "blocked"], "Status: In Progress", "closed", 0, 0),
    ([], "Status: Blocked", "open", 0, 1),
    ([], "## Status\nStatus: Awaiting evidence", "open", 1, 0),
    ([], "## Delivery Status\nActive: validating", "open", 1, 0),
    ([], "## Status\nIn progress: running\nStatus: Blocked", "open", 0, 1),
    ([], "## History\nIn progress: previously running\nStatus: In Progress", "open", 0, 0),
    ([], "## Status\n```text\nIn progress: example\n```", "open", 0, 0),
    ([], "Status: Blocked\n## History\n### Status\nIn progress: previous attempt", "open", 0, 1),
    ([], "## Status\nBlocked\n````markdown\n```text\nIn progress: example\n```\n````", "open", 0, 1),
    ([], "Status: Blocked\n~~~text\n~~~not-a-closing-fence\nStatus: In Progress\n~~~", "open", 0, 1),
    ([], "Status: Blocked\n\n    Status: In Progress", "open", 0, 1),
    ([], "Status: Blocked\n\n \tStatus: In Progress", "open", 0, 1),
    ([], "Status: Blocked\n\n  \tStatus: In Progress", "open", 0, 1),
    ([], "Status: Blocked\n\n   \tStatus: In Progress", "open", 0, 1),
    ([], "## Status\n> In progress: quoted\n- [ ] In progress: pending", "open", 0, 0),
    ([], "We will put this In progress: later.", "open", 0, 0),
])
def test_bands_activity_uses_current_explicit_status_only(monkeypatch, labels, body, state, active, blocked):
    member = {**_roadmap_issue(7, "Entry", labels, body), "milestone_number": 1, "state": state}
    page = _mapped_bands_page(monkeypatch, "Outcome: Safe entry.", [member])
    assert f"Active {active}" in page
    assert f"Blocked {blocked}" in page
    if state == "open":
        assert ('class="issue-status active"' in page) is bool(active)
        assert (', blocked"' in page) is bool(blocked)


def test_bands_unscheduled_issues_show_activity_without_inventing_groups(monkeypatch):
    monkeypatch.setattr("app.github_issues", lambda: {
        "available": True, "milestones": [], "issues": [
            {**_roadmap_issue(7, "Delivered work", []), "state": "closed"},
            _roadmap_issue(8, "Active work", ["tbp:in-progress"]),
        ],
    })
    page = render_roadmap()
    assert "Unscheduled backlog" in page
    assert "Issues: 1/2 closed" in page and "Active 1" in page
    assert "Outcome acceptance: not defined" in page
    assert 'class="milestone-slice"' not in page


def test_bands_rejects_incomplete_definition_and_escapes_external_text(monkeypatch):
    definition = _mapped_slice_definition(members="- #7\n<script>alert(1)</script>").replace("Verified installation.", "TBD")
    page = _mapped_bands_page(monkeypatch, "## Slice Mapping\n" + definition, [
        {**_roadmap_issue(7, "<script>member</script>", []), "milestone_number": 1},
    ])
    assert "Missing or unfinished outcome." in page
    assert "Invalid member entry:" in page
    assert "<script>alert" not in page and "<script>member" not in page
    assert "&lt;script&gt;" in page
    assert 'data-slice-id="A1" data-state="new"' in page
