---
status: accepted
---

# Stable Compose deployment authority

## Context

Production containers were created from Compose files inside ephemeral CI
checkouts. Their Docker metadata therefore pointed at a disposable workspace,
and the deployment command could recreate or remove unrelated services. Image
tag rollback also left a changed Compose definition active.

## Decision

The single durable full-stack deployment artifact is
`/apps/project0/deploy/compose.yml`, managed under Compose project `project0`.
The repository file is a candidate input. The deployment script validates it,
atomically publishes it to the stable path, and runs pull, up, health, and
rollback from that published artifact.

Every deployment names its mutable services with repeatable `--service`
arguments. Targeted repair changes only those services; it does not remove
orphans. A failed health gate restores the previous Compose artifact before
redeploying the previous recorded image tag.

Runtime state remains under `/var/lib/project0`, and secrets and host-managed
configuration remain under `/etc/project0`. The dashboard checkout and
dashboard Compose file retain independent ownership and are not a game-server
deployment root.

## Consequences

Docker Compose metadata points to a durable operator-owned artifact instead of
a CI workspace. Releases must enumerate the five core services explicitly,
while bounded repairs can recreate only one service. Rollback covers both
configuration and image identity. Adding or removing a production service now
requires an explicit caller change rather than silently widening deployment
scope.