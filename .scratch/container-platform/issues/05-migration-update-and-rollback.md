# Migration, update, and rollback protocol

Status: resolved
Assignee: Copilot
Type: grilling
Blocked by: 01-runtime-boundary-and-container-adapter, 03-persistence-and-data-ownership, 04-operator-control-plane-and-telemetry

## Question

How does the Linux host move from the native systemd game server to the
containerized platform safely? Decide shadow/canary topology, port cutover,
image provenance, update sequencing, health gates, persistence compatibility,
rollback triggers, operator visibility, and the point at which the old native
service may be retired.

## Required decision output

A reversible deployment and rollback runbook with executable acceptance
criteria, not a one-shot replacement procedure.

## Resolution

Migration on `192.168.1.254` is staged and reversible; it is never a one-shot
replacement. The native `project0-server.service` is the rollback unit and
stays available until the cutover gate is accepted.

Topology:

```text
Native game server  : UDP 9999 (current authority, rollback)
Container game server: isolated UDP port or address (candidate)
```

The container runs beside the native server on an isolated port or address so
both can be exercised without contending for authority or the same data files.

Sequence:

1. Build the pinned image and publish it with a recorded digest/provenance
   into `/apps/project0`.
2. Run the container against a temporary data volume and prove boot, health,
   fixed tick, UDP reachability, graceful shutdown, and restart persistence.
3. Run the container beside the native server and prove connection, world
   entry, movement, and replication equivalence.
4. Perform the one-time persistence migration per the persistence decision,
   keeping the original database as rollback.
5. Cut the host service over to the container only after the health and
   equivalence gates pass, via the operator control plane.
6. Keep the native service defined and startable until the acceptance window
   closes; retire it only after rollback evidence is complete.

Update protocol: a new image is deployed by digest, started as the candidate,
gated on health and equivalence, then promoted; a failed gate triggers
automatic rollback to the last-good image or the native service. Rollback
triggers are unhealthy startup, failed equivalence, persistence
incompatibility, or operator abort. Every migration and update step is an
operator job with a correlation id and audit record.

## Acceptance evidence

The implementation route must prove a beside-running candidate, health and
equivalence gates, digest-pinned deployment, persistence migration with a
retained rollback copy, an executed rollback path, and operator-visible job
records, before the native service is retired.

## Decision status

Resolved by user confirmation on 2026-09-14. No production files were changed
by this planning decision.
