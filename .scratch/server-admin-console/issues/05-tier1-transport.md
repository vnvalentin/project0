Type: grilling
Status: open
Blocked-by: 01-ops-snapshot-contract

## Question

Decide the **tier-1 transport**: concretely how the ops snapshot (ticket 01) travels
from each running server to the operator console. Premise (settled): extend the
health-file mechanism; promote to an HTTP endpoint only if files prove insufficient.

Sub-questions to resolve here:

- **Write path.** Extend `HealthReporter` (`server/health_reporter.gd`) to write the
  fuller `OpsSnapshot` (not just the minimal health snapshot)? One file per server, or
  keep the existing health file and add a second ops-snapshot file? Refresh cadence
  (current health refresh is ~0.5 s / 30 physics frames)?
- **File location + read path.** Where do the files land so a **Dockerized console** can
  read them — a shared host directory bind-mounted read-only, `user://` resolved to a
  known host path, or SSH/scp pull? Fix the canonical on-host path convention.
- **Freshness / liveness.** How does the console distinguish "server healthy" from
  "snapshot stale / server dead" (timestamp age threshold vs. systemd active-state)?
- **Insufficiency triggers.** State the concrete conditions that would justify promoting
  to an HTTP read endpoint later (so that promotion is a bounded future slice, not a
  redesign).

Recommended direction: extend `HealthReporter` to also write a versioned
`ops_snapshot.json` per server into a fixed host directory bind-mounted read-only into
the console container; console treats a snapshot older than N× the refresh interval as
stale and cross-checks systemd active-state for liveness. Confirm or revise at
resolution.

## Answer

_Pending._
