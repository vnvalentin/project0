# Slice 109 - Host-assumption sweep and post-deploy smoke checks

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing P-014.

## User outcome

A configuration value that silently assumes "everything runs on one host" now
fails the deploy and rolls back, instead of reaching a player as a broken
request. Three defects of exactly this kind shipped during the container
cutover; each kept every health check green while it was broken.

## Scope and non-goals

In scope: an audit of hardcoded loopback/host-path assumptions across
`server/`, `shared/`, and `infra/`; correcting the last host-assumed value in
`/etc/project0/enrollment.env`; `deploy/smoke-checks.json`; and a smoke-check
phase in `scripts/deploy_containers.sh` that rolls back on failure.

Out of scope: changing the ADR 0005 loopback bind, splitting the login image
([DT-012](../TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase)),
shipping the wgnetstack GDExtension
([DT-014](../TECHNICAL-DEBT-TRACKER.md#dt-014-container-images-ship-without-the-wgnetstack-gdextension)),
and adding smoke coverage for tunnel provisioning or world entry.

## Public seam

`scripts/deploy_containers.sh` gains a smoke-check phase after the health gate.
Checks are declared in `deploy/smoke-checks.json`; adding one is a single entry.

## Audit findings

Every hardcoded loopback in production code was reviewed against the container
topology:

| Location | Verdict |
| --- | --- |
| `login_loopback_http_endpoint.gd` `BIND_ADDRESS` | Correct and deliberate (ADR 0005). Resolved by sharing a network namespace, not by rebinding. |
| `sector_blueprint_service.gd`, `provisional_sector_generator.gd` `ollama_host` | Safe: the value is the default sentinel, so `configure_from_env()` overrides it (Slice 106 fix). |
| `shared/local_llm_client.gd` `DEFAULT_OLLAMA_HOST` | Safe: sentinel default, env-overridable. |
| `shared/network_config.gd` `SERVER_ADDRESS` | Client-side default, not a server topology assumption. |
| `infra/enrollment/config.py` `LOGIN_AUTHORITY_HOST` | Correct now that enrollment shares the login namespace. |
| `infra/operator/config.py` `OPERATOR_BIND_HOST` | Would be unreachable in a container, but compose passes `--host 0.0.0.0` explicitly, so the default is never used. |
| `/etc/project0/enrollment.env` `ENROLLMENT_DB_PATH` | **Wrong** — still the retired in-tree path. Corrected at source. |

## Design notes

- Smoke checks run **inside the enrollment container**, because the targets are
  loopback-bound by design and are deliberately unreachable from the host.
- A failing smoke check reuses the same rollback path as a failing health check,
  so the two failure modes behave identically.
- `ENROLLMENT_DB_PATH` was fixed in the host env file rather than left to the
  compose override alone. The override remains as defence in depth, but the
  source of truth is no longer lying.
- The `enrollment-healthz` check is kept deliberately as a control: it passed
  throughout the login outage, which is exactly why health alone is insufficient.

## Safety invariants

- Smoke checks are read-only probes with deliberately invalid credentials; they
  create no account, session, or peer.
- A smoke failure never leaves the new tag running: it rolls back to the last
  tag observed healthy.
- No secret is read, written, or logged by a check.

## Acceptance scenarios

1. Given a healthy stack, when a deploy runs, then every smoke check passes and
   the tag is recorded.
2. Given a cross-boundary delegation that is broken, when a deploy runs, then
   the smoke check fails and the previous tag is redeployed.
3. Given no `deploy/smoke-checks.json`, then the deploy proceeds unchanged.

## Validation

Focused validation: the countermeasure was proven in both directions against
the live stack — passing on the fixed topology, and catching the original
defect after it was deliberately reintroduced.

## Validation evidence

- **Passes on the fixed stack:**
  `OK enrollment-delegates-to-login-authority: HTTP 401`,
  `OK enrollment-healthz: HTTP 200`, then `Deployed tag v0.1.3`.
- **Catches the real defect:** the Slice 106 topology (enrollment in its own
  network namespace) was deliberately reintroduced, producing
  `FAIL enrollment-delegates-to-login-authority: expected HTTP 401, got 502` →
  `ROLLBACK: redeploying previous tag v0.1.3` → deploy failed. This is the exact
  failure that reached the user as a malformed client response.
- Stack restored afterwards; both checks pass and `v0.1.3` is deployed.
- Host env audit after correction: no `/etc/project0/*.env` value references a
  host-only path.

## Root-cause learning

- Symptom: three separate defects in one cutover — Ollama unreachable, the
  enrollment DB path invalid, and login delegation failing — each presenting
  differently.
- Confirmed common root cause: configuration that silently assumed a single
  host. Under systemd every process shared one filesystem and one loopback, so
  `127.0.0.1` and absolute host paths were correct by accident of topology.
  Containers broke that assumption per process, and nothing in the system
  detected it.
- Why existing tests missed it: unit tests inject fakes for exactly these
  boundaries, and container health checks only prove a process answers for
  itself. Both stayed green through every one of the three outages.
- Countermeasure: assert the boundary, not the process. Smoke checks exercise
  calls that cross a process or container boundary and fail the deploy when one
  breaks.
- Remaining limitation: coverage is currently the login delegation path only.
  Tunnel provisioning, character selection, and world entry still have no
  automated cross-boundary check and remain dependent on a human client test.

## Record links

- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Prior slices: [106](106-container-runtime-cutover.md), [108](108-retire-archive-deploy.md)
- Decision: [ADR 0005](../adr/0005-character-selection-over-https.md)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 109
