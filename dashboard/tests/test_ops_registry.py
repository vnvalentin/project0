import json
from pathlib import Path

from dashboard.ops_registry import scan_registry


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def test_scan_registry_reads_healthy_snapshot(tmp_path: Path) -> None:
    manifest = tmp_path / "servers.json"
    snapshots = tmp_path / "snapshots"
    write_json(manifest, {"servers": [{"server_id": "game", "server_type": "world", "unit": "project0-server"}]})
    write_json(snapshots / "game" / "ops_snapshot.json", {
        "snapshot_schema_version": 1,
        "server_id": "game",
        "server_type": "world",
        "timestamp": 100,
    })

    rows = scan_registry(manifest, snapshots, now=102, stale_after=3)

    assert rows[0]["state"] == "healthy"
    assert rows[0]["age_seconds"] == 2


def test_scan_registry_marks_stale_and_absent(tmp_path: Path) -> None:
    manifest = tmp_path / "servers.json"
    snapshots = tmp_path / "snapshots"
    write_json(manifest, {"servers": [
        {"server_id": "game", "server_type": "world"},
        {"server_id": "login", "server_type": "login"},
    ]})
    write_json(snapshots / "game" / "ops_snapshot.json", {
        "snapshot_schema_version": 1,
        "server_id": "game",
        "server_type": "world",
        "timestamp": 90,
    })

    rows = scan_registry(manifest, snapshots, now=100, stale_after=3)

    assert [row["state"] for row in rows] == ["stale", "absent"]


def test_scan_registry_rejects_unknown_type_and_mismatched_snapshot(tmp_path: Path) -> None:
    manifest = tmp_path / "servers.json"
    snapshots = tmp_path / "snapshots"
    write_json(manifest, {"servers": [
        {"server_id": "unknown", "server_type": "worker"},
        {"server_id": "game", "server_type": "world"},
    ]})
    write_json(snapshots / "game" / "ops_snapshot.json", {
        "snapshot_schema_version": 1,
        "server_id": "other",
        "server_type": "world",
        "timestamp": 100,
    })

    rows = scan_registry(manifest, snapshots, now=100)

    assert len(rows) == 1
    assert rows[0]["state"] == "unreadable"
