from __future__ import annotations

import pytest

from infra.operator.services import StatusService, UnknownServiceError
from infra.operator.tests.fakes import FakeServiceInspector


def _services() -> dict[str, tuple[str, str]]:
    return {
        "game-server": ("systemd", "project0-server"),
        "dashboard": ("docker", "project0-flow"),
    }


def test_status_all_reports_each_allowlisted_service():
    inspector = FakeServiceInspector(
        systemd={"project0-server": "active"},
        docker={"project0-flow": "running"},
    )
    statuses = {s.name: s for s in StatusService(_services(), inspector).status_all()}
    assert statuses["game-server"].active is True
    assert statuses["game-server"].state == "active"
    assert statuses["dashboard"].active is True
    assert statuses["dashboard"].state == "running"


def test_inactive_service_is_not_active():
    inspector = FakeServiceInspector(systemd={"project0-server": "inactive"})
    assert StatusService(_services(), inspector).status_one("game-server").active is False


def test_unknown_state_is_not_active():
    # A service the inspector cannot read reports state "unknown", not active.
    assert StatusService(_services(), FakeServiceInspector()).status_one("game-server").state == "unknown"


def test_unknown_service_is_fail_closed():
    with pytest.raises(UnknownServiceError):
        StatusService(_services(), FakeServiceInspector()).status_one("not-allowlisted")
