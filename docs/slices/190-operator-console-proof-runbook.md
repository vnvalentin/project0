# Slice 190 - Operator console proof and runbook

GitHub issue: #165

Status: **in progress**

Phase: 17 (Fleet operations console)

Feature: [F-041](../FEATURE-LIST.md#f-041-fleet-operations-console)

## Outcome

The fleet-operations design and implementation slices have a durable operator
runbook and a final proof boundary. The authoritative control path is proven
live, and both Godot authorities now emit validated OpsSnapshots for the
read-only console. A deployed read-side proof remains.

## Evidence boundary

Slices 184-188 are focused-tested. Slice 189 verifies the Python assertion,
scope seam, and fixed-allowlist host helper. The private `/control` adapter now
routes lifecycle actions through the audited operator service and fails closed
with `executor_unavailable` for gameplay actions until the Godot transport is
wired. The authoritative `OperatorControlService` and `OperatorControlAdapter`
are covered by focused tests for drain, degraded state, peer-target validation,
assertion rejection, scope rejection, and authorized dispatch. The privileged
control transport proof is complete. World and login snapshot emitters are
wired to the existing atomic writer and share the console's snapshot directory;
stale/unreadable states remain non-authoritative.

### Deployment evidence

On 2026-09-20, the merged control transport was deployed on `okami` with the
paired Project0/Nakama stack. All five services passed the deployment health
gate and the enrollment smoke checks returned HTTP 401 and HTTP 200 as
expected. The game server logged `Operator control HTTP endpoint listening on
internal port 8097`. A request with an invalid operator assertion reached
`/internal/control` and returned HTTP 403 with no action execution.

The operator-console forwarding service was enabled on LAN port 18090 with the
deployed Project0 image and host-managed assertion configuration. A
Project0-native `project0-console` assertion with `control` scope set degraded
state and was accepted with HTTP 200; the same path immediately cleared the
state and was accepted with HTTP 200. No gameplay or Nakama service was
restarted. Invalid bearer proof remains HTTP 403. Focused OpsSnapshot and
HealthReporter validation passed 13/13 tests with 30 assertions.

## Runbook

See [fleet-operator-runbook.md](../fleet-operator-runbook.md) for bind/mount,
secret, rollback, Nakama migration, and current validation rules.

## Non-goals

This record does not claim a complete production operator-console cutover. The
remaining gate is a deployed read-side proof showing fresh world/login rows in
the LAN console.

## Root-cause learning

The full local GUT gate remains red on unrelated multi-peer/prediction tests
and a pre-existing SQLite test parse/cache skip; the focused tests for this
slice pass. Docker compose validation was unavailable on Windows because the
Docker CLI is not installed. These limitations require remote deployment
validation before the slice can be marked complete.
