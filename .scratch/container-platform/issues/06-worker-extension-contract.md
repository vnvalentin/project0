# Future worker extension contract

Status: resolved
Assignee: Copilot
Type: grilling
Blocked by: 02-account-login-service-boundary, 03-persistence-and-data-ownership

## Question

What common job/worker interface should future world-builder and mobile-object
workers use without making the first container migration depend on them? Decide
input/output envelopes, authority boundary, idempotency, timeouts, retries,
provisional versus Canon state, resource isolation, and how generated output is
validated before the game server can use it.

## Required decision output

A minimal extension contract and explicit non-goals for future workers; no
world-builder or mobile-object implementation is implied by this ticket.

## Resolution

Future world-builder and mobile-object workers share one minimal job contract,
but the first container migration does not depend on any worker. A worker is a
bounded, replaceable job runner that proposes data; it never holds authority.

Contract:

```text
request : schema_version, job_id, job_kind, bounded params, issued_at, deadline
result  : job_id, outcome, bounded payload | bounded rejection reason
```

Rules:

- The authoritative game server, not the worker, decides outcomes. Worker
  output is provisional and untrusted until validated, mirroring the existing
  Ollama/blueprint rule in `CLAUDE.md`.
- Jobs are idempotent by `job_id`; a duplicate returns the original result and
  never double-applies.
- Jobs are bounded by an explicit deadline; timeouts and retries are bounded
  and observable, and a failed job never mutates authoritative state.
- Provisional worker output only becomes Canon through the server-owned
  validation and persistence path; a worker cannot write Canon directly.
- Workers run with isolated resources and no gameplay authority, no direct
  SQLite handle to Canon, and no OPNsense/login credentials.
- The operator control plane observes worker jobs through the same job/event
  model.

This ticket defines only the seam. No world-builder or mobile-object worker is
implemented or scheduled by resolving it.

## Acceptance evidence

A future worker slice must prove bounded request/result validation, idempotent
replay, deadline/timeout handling, provisional-not-Canon enforcement, resource
isolation, and server-side validation before use.

## Decision status

Resolved by user confirmation on 2026-09-14. No production files were changed
by this planning decision.
