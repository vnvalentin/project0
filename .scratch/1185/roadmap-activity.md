# Roadmap Activity Visibility

Governing issue: https://github.com/vnvalentin/project0/issues/1185
Parent issue: #1152
Phase: 13 - Delivery workflow capabilities
Outcome: G Telemetry and operational observability

The user approved separate issue activity and outcome acceptance on the
read-only `/roadmap` Bands view. Preserve explicit group membership and
acceptance gates. Do not invent milestone commitments or Slice definitions.

Public validation seam: `render_roadmap` with fixture GitHub issues, followed
by live desktop/mobile browser verification after delivery.

Focused command: `python -m pytest -q dashboard/tests/test_tbp_lifecycle.py`.
Required gates: all dashboard tests, full GUT, record sync, PR checks and review.

Claude CLI is absent from PATH on OKAMI. Standing authorization permits direct
Copilot implementation in an isolated worktree, preserving concurrent #1181.
GitHub #1185 owns current status, root-cause learning and validation evidence.
Rollback: revert the dashboard PR; restore any documented milestone edits
independently. No game, Windows, dependency or credential changes.