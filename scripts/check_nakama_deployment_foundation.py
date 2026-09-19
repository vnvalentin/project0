#!/usr/bin/env python3
"""Static validation for the Nakama v1 deployment foundation.

The repository intentionally keeps Nakama secrets and the live Nakama YAML
outside git. This check validates the committed contract around those external
files without requiring Docker, a running database, or secret material.
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "deploy" / "compose.yml"
RUNBOOK = ROOT / "docs" / "nakama-v1-deployment-foundation.md"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    failures: list[str] = []
    compose = COMPOSE.read_text(encoding="utf-8")
    runbook = RUNBOOK.read_text(encoding="utf-8")

    require("nakama-db:" in compose, "compose defines nakama-db service", failures)
    require("image: postgres:16.8-alpine" in compose, "nakama-db uses pinned PostgreSQL image", failures)
    require('profiles: ["nakama"]' in compose, "Nakama services are profile-gated", failures)
    require("/var/lib/project0/nakama-postgres" in compose, "PostgreSQL data persists under /var/lib/project0", failures)
    require("/etc/project0/nakama-db.env" in compose, "PostgreSQL secrets come from /etc/project0", failures)
    require("registry.heroiclabs.com/heroiclabs/nakama" in compose, "compose uses official Nakama image", failures)
    require("nakama migrate up" in compose, "Nakama startup runs migrations explicitly", failures)
    require("/etc/project0/nakama" in compose, "Nakama config is host-mounted from /etc/project0", failures)
    require("depends_on:" in compose and "condition: service_healthy" in compose, "Nakama waits for healthy database", failures)
    require("${NAKAMA_BIND:-192.168.1.254}:7350:7350" in compose, "client API/socket surface is the only public Nakama binding", failures)
    require("${NAKAMA_CONSOLE_BIND:-127.0.0.1}:7351:7351" in compose, "Nakama Console defaults to loopback", failures)
    require("7349:" not in compose and "7348:" not in compose, "Nakama gRPC/admin gRPC ports are not published", failures)

    forbidden_defaults = ["defaultkey", "defaultencryptionkey", "defaulthttpkey", "admin/password"]
    lower_compose = compose.lower()
    for forbidden in forbidden_defaults:
        require(forbidden not in lower_compose, f"compose does not contain Nakama default secret {forbidden}", failures)

    for expected in [
        "single-node self-hosted Nakama",
        "PostgreSQL",
        "CockroachDB",
        "Only Nakama's client API/realtime socket surface is public",
        "/etc/project0/nakama-db.env",
        "/etc/project0/nakama/nakama.yml",
        "Rotate every Nakama default key/password",
        "Backup-before-migration gate",
        "Image-only rollback is not sufficient",
    ]:
        require(expected in runbook, f"runbook contains: {expected}", failures)

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    print("Nakama deployment foundation static check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())