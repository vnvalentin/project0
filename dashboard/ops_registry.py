"""Read-only server registry and OpsSnapshot freshness handling."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

SUPPORTED_SERVER_TYPES = {"world", "login"}


def scan_registry(manifest_path: Path, snapshot_root: Path, now: int | None = None, stale_after: int = 3) -> list[dict[str, Any]]:
    current_time = int(time.time()) if now is None else now
    manifest = _read_json(manifest_path)
    rows: list[dict[str, Any]] = []
    for item in manifest.get("servers", []):
        server_id = str(item.get("server_id", "")).strip()
        server_type = str(item.get("server_type", "")).strip()
        if not server_id or server_type not in SUPPORTED_SERVER_TYPES:
            continue
        snapshot = _read_json(snapshot_root / server_id / "ops_snapshot.json")
        row = {"server_id": server_id, "server_type": server_type, "unit": str(item.get("unit", "")), "state": "absent", "snapshot": {}}
        if snapshot:
            if int(snapshot.get("snapshot_schema_version", -1)) != 1:
                row["state"] = "unreadable"
            elif snapshot.get("server_id") != server_id or snapshot.get("server_type") != server_type:
                row["state"] = "unreadable"
            else:
                age = max(0, current_time - int(snapshot.get("timestamp", 0)))
                row["state"] = "stale" if age > stale_after else "healthy"
                row["age_seconds"] = age
                row["snapshot"] = snapshot
        rows.append(row)
    return rows


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}
    return value if isinstance(value, dict) else {}
