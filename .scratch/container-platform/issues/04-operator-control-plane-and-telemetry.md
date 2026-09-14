# Operator control plane and telemetry

Status: resolved
Assignee: Copilot
Type: grilling
Blocked by: 01-runtime-boundary-and-container-adapter

## Question

What private operator interface governs status, telemetry, invite minting, peer
revocation, service restart, deployment update, bounded logs, and audit? Decide
transport exposure, authentication/authorization, action allowlists, job state,
correlation IDs, retention, and fail-closed behavior. It must remain separate
from the public enrollment `/redeem` route.

## Required decision output

A small, testable operator interface and event model that can control native or
containerized services without arbitrary shell execution.

## Resolution

A private operator service, separate from the public enrollment `/redeem`
route, provides a small deep interface over the host lifecycle. It binds only
to the host loopback or the management/WireGuard network on `192.168.1.254`,
never to the public WAN path, and is operator-authenticated.

The interface is intentionally small:

```text
GET  /status
GET  /telemetry
GET  /events
GET  /logs/{service}
POST /invites
POST /peers/{public_key}/revoke
POST /services/{name}/start
POST /services/{name}/stop
POST /services/{name}/restart
POST /update
```

Every action is allowlisted, never arbitrary shell execution. `{service}` and
`{name}` resolve only to known units — `project0-server`,
`project0-enrollment`, `project0-login`, and `project0-flow` — through a
systemd/container adapter. An unknown target fails closed.

Mutating actions become jobs with a bounded lifecycle:

```text
requested -> running -> succeeded
                     -> failed
```

Each job and event carries a correlation id, operator identity, target,
action, timestamp, and bounded outcome. Invite minting and peer revocation
reuse the existing enrollment CLI seams (`mint-invite`, `revoke-peer`) through
the adapter rather than reimplementing them. Telemetry aggregates each
service's health, version/commit, uptime, and bounded runtime counters without
sensitive payloads, secrets, or key material.

Authorization is fail-closed: unauthenticated or unauthorized requests are
rejected with a bounded reason and no side effect. Audit records are durable
and append-only. Logs are bounded and redacted. The control plane can operate
the native services now and the containerized services after migration through
the same allowlisted adapter.

## Acceptance evidence

The implementation route must prove private-only exposure, operator
authentication, allowlisted targets, fail-closed unknown/unauthorized actions,
job lifecycle transitions, correlation-id audit records, and redacted bounded
telemetry/logs, without invoking arbitrary commands.

## Decision status

Resolved by user confirmation on 2026-09-14. No production files were changed
by this planning decision.
