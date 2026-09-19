#!/usr/bin/env python3
"""Validate the Nakama v1 smoke/operations gate.

Static mode is safe for CI and does not need Docker, credentials, or a live
server. ``--live`` performs one bounded unauthenticated health probe against
PROJECT0_NAKAMA_SMOKE_URL; it never prints response bodies or secrets.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "deploy" / "nakama-smoke-checks.json"
FOUNDATION_CHECK = ROOT / "scripts" / "check_nakama_deployment_foundation.py"
REQUIRED_STAGES = {
    "container_health",
    "nakama_api_health",
    "nakama_login_session",
    "project0_character_crud",
    "project0_world_entry_ticket",
    "gameplay_bridge_presence",
    "private_admin_surface",
    "backup_before_migration",
}


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def load_manifest() -> dict:
    with MANIFEST.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("manifest must be an object")
    return value


def validate_static(manifest: dict) -> list[str]:
    failures: list[str] = []
    if manifest.get("version") != 1:
        failures.append("manifest version must be 1")
    stages = manifest.get("required_stages")
    if not isinstance(stages, list) or set(stages) != REQUIRED_STAGES:
        failures.append("manifest required_stages does not match the v1 gate")
    probe = manifest.get("live_probe")
    if not isinstance(probe, dict) or probe.get("method") != "GET":
        failures.append("live_probe must declare GET")
    if not isinstance(probe.get("timeout_seconds"), int) or not 1 <= probe["timeout_seconds"] <= 10:
        failures.append("live_probe timeout must be bounded from 1 to 10 seconds")
    if not FOUNDATION_CHECK.is_file():
        failures.append("deployment foundation checker is missing")
    return failures


def run_static_foundation_check() -> int:
    result = subprocess.run(
        [sys.executable, str(FOUNDATION_CHECK)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def live_probe(manifest: dict) -> int:
    raw_url = os.environ.get("PROJECT0_NAKAMA_SMOKE_URL", "").strip().rstrip("/")
    if not raw_url:
        return fail("--live requires PROJECT0_NAKAMA_SMOKE_URL")
    parsed = urlparse(raw_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return fail("PROJECT0_NAKAMA_SMOKE_URL must be an http(s) URL")
    path = str(manifest["live_probe"]["path"])
    request = Request(f"{raw_url}{path}", method="GET")
    try:
        with urlopen(request, timeout=int(manifest["live_probe"]["timeout_seconds"])) as response:
            status = int(response.status)
    except HTTPError as error:
        return fail(f"live Nakama probe returned HTTP {error.code}")
    except (URLError, TimeoutError, OSError) as error:
        return fail(f"live Nakama probe failed: {type(error).__name__}")
    if not 200 <= status < 300:
        return fail(f"live Nakama probe returned HTTP {status}")
    print(f"PASS: live Nakama probe HTTP {status}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true", help="probe the explicitly configured Nakama URL")
    args = parser.parse_args()

    try:
        manifest = load_manifest()
    except (OSError, json.JSONDecodeError, ValueError) as error:
        return fail(f"cannot load smoke manifest: {error}")

    failures = validate_static(manifest)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    if run_static_foundation_check() != 0:
        return fail("deployment foundation check failed")
    print("PASS: static Nakama v1 smoke manifest and foundation gate")
    if args.live:
        return live_probe(manifest)
    print("INFO: live probe skipped; use --live with PROJECT0_NAKAMA_SMOKE_URL")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())