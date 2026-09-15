# Slice 067 — Server runtime health file + container HEALTHCHECK

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [runtime-boundary decision](../../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
(the container needs a truthful liveness signal — "health output"). Thirteenth
delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it turns the pure `ServerHealth` contract from
[Slice 055](055-server-fixed-tick-and-health-contract.md) into a runtime health
file the container `HEALTHCHECK` consumes, replacing the port-only check.

## User outcome

The game-server container reports **healthy only while the authoritative tick
loop is actually running**: the server writes a fresh, versioned health snapshot
every ~0.5 s, and the container `HEALTHCHECK` fails when that file is missing,
stale, or not `healthy` — a truer signal than "a UDP socket is bound".

## Scope and non-goals

In scope: a server-only `HealthReporter` that resolves the health-file path from
`PROJECT0_HEALTH_FILE` and writes a `ServerHealth` snapshot to disk fail-closed;
wiring it into `server_main.gd` (write `starting` at boot, `healthy` once
listening, refresh each throttled physics frame, best-effort `stopping` on
shutdown); a `deploy/game-server/healthcheck.sh` that checks existence,
freshness, and `status == "healthy"`; and the Dockerfile `HEALTHCHECK` + env.

Out of scope (later slices): binding the engine's physics tick to the resolved
20–30 Hz rate (this slice only *reports* the resolved rate, matching Slice 055's
note); exposing health over a socket/endpoint; operator telemetry ingestion of
the snapshot. No new dependency.

## Public seam

- `server/health_reporter.gd` (`HealthReporter.resolve_health_file_path(raw)`,
  `HealthReporter.write_snapshot(path, snapshot)`), server-only per CLAUDE.md.
- `server/server_main.gd` (health path/status wiring + throttled refresh).
- `deploy/game-server/healthcheck.sh` and the Dockerfile `HEALTHCHECK`/`ENV`.

## Safety invariant

`HealthReporter` writes only a `ServerHealth`-validated snapshot; a write failure
is best-effort and never crashes or blocks the tick loop. The file carries no
secret (status, tick rate, uptime, tick, peer counts, versions, timestamp). The
healthcheck treats a missing/stale/degraded file as unhealthy (fail-closed), so
a frozen tick loop is detected even while the socket stays bound.

## ADR rationale

No new ADR. A truthful container liveness signal is already required by the
runtime-boundary decision; this consumes the existing `ServerHealth` seam rather
than adding a parallel health model.

## BDD / TDD

`tests/unit/test_health_reporter.gd`: `resolve_health_file_path` defaults when
blank and returns a trimmed override; `write_snapshot` round-trips a validated
`healthy` snapshot to disk (read back, parse, assert `status`/`tick_rate`);
`write_snapshot` fails closed (returns an error outcome) for an unwritable path;
and an end-to-end `ServerHealth.build_snapshot → write_snapshot` proves a
`healthy` file lands on disk.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 50/50 scripts, exit 0** (+1 new `tests/unit/test_health_reporter.gd`).
- Runtime on Linux (headless boot, `PROJECT0_HEALTH_FILE` set, non-colliding
  port): the health file reports `"status":"healthy"` (`tick_rate` 30,
  `server_tick` advancing), `Server listening` confirmed, and
  `healthcheck.sh` returns success while running; a stale (old-mtime) file and a
  missing file both fail closed (`STALE_CORRECTLY_UNHEALTHY`,
  `MISSING_CORRECTLY_UNHEALTHY`).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
