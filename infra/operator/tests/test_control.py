from __future__ import annotations

import pytest

from infra.operator.control import RealServiceController


@pytest.mark.parametrize("action", ["reload", "kill", "", "rm", "exec"])
def test_run_rejects_non_lifecycle_action_without_executing(action):
    ok, detail = RealServiceController().run("systemd", action, "project0-server")
    assert ok is False
    assert detail == "unknown action"


def test_run_rejects_unknown_service_kind():
    ok, detail = RealServiceController().run("nomad", "start", "project0-server")
    assert ok is False
    assert detail == "unknown service kind"
