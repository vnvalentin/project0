import json
import time
from pathlib import Path

from operator_console.app import render_detail, render_fleet


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def test_fleet_and_detail_render_read_only_state(tmp_path: Path, monkeypatch) -> None:
    manifest = tmp_path / "servers.json"
    snapshots = tmp_path / "snapshots"
    write_json(manifest, {"servers": [{"server_id": "game", "server_type": "world", "unit": "project0-server"}]})
    write_json(snapshots / "game" / "ops_snapshot.json", {
        "snapshot_schema_version": 1,
        "server_id": "game",
        "server_type": "world",
        "timestamp": int(time.time()),
    })
    monkeypatch.setattr("operator_console.app.MANIFEST", manifest)
    monkeypatch.setattr("operator_console.app.SNAPSHOTS", snapshots)

    assert "game" in render_fleet()
    assert "healthy" in render_detail("game")
