# Slice 061 — Operator control plane: read-only status service

Status: **in progress**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md).
Seventh delivery of the
[container-platform map](../../.scratch/container-platform/map.md); it lays the
private, operator-authenticated foundation of the control plane with read-only
status only — mutating actions (restart, invites, revoke, update) are follow-up
slices, each adding one allowlisted action behind an audit/job model.

## User outcome

An operator can query one private, authenticated endpoint for the live state of
the Project0 host services (native game server, enrollment, dashboard) without
SSHing into each unit — over loopback/management only, never the public path,
and without any ability to run arbitrary commands.

## Scope and non-goals

In scope: a Python (FastAPI) `infra/operator/` service mirroring
`infra/enrollment/`'s structure — `config.py` (env-driven, required operator
token, allowlisted service map), `services.py` (a `ServiceInspector` Protocol
with a read-only `RealServiceInspector` running fixed `systemctl is-active` /
`docker inspect` against allowlisted identifiers only, and a `StatusService`),
`app.py` (`create_app` factory; `GET /healthz` unauthenticated, `GET /status`
and `GET /status/{name}` bearer-token authenticated, fail-closed), `asgi.py`,
`requirements.txt`, `operator.env.example`, `project0-operator.service`
(loopback-bound), a `README.md`, and pytest tests against a fake inspector.

Out of scope (later slices): every mutating action (`POST /services/{name}/
{start,stop,restart}`, `/invites`, `/peers/{key}/revoke`, `/update`) and the
job lifecycle + audit store they require; `/telemetry` beyond service state;
`/logs`; a UI; TLS/reverse-proxy exposure; live deployment. No game `.gd` code
changes — this slice is Python-only and validated by pytest, so the GUT suite
is unaffected.

## Public seam

- `infra/operator/config.py` (`OperatorConfig`, `load_config`): bind host/port,
  required `OPERATOR_TOKEN`, and the allowlisted `name -> (kind, identifier)`
  service map (defaults: `game-server`→systemd `project0-server`,
  `enrollment`→systemd `project0-enrollment`, `dashboard`→docker `project0-flow`).
- `infra/operator/services.py` (`ServiceStatus`, `ServiceInspector` Protocol,
  `RealServiceInspector`, `StatusService`): `status_all()` /
  `status_one(name)`; unknown names are fail-closed.
- `infra/operator/app.py` (`create_app(status_service, operator_token)`): the
  bearer-auth dependency (constant-time compare), `/healthz`, `/status`,
  `/status/{name}`.

## Safety invariant

Private and fail-closed. The service binds loopback/management only and is never
published on the public enrollment path. Every state-reading command is a fixed
argument vector against an allowlisted identifier — no shell, no
caller-supplied command, no mutation. `GET /status*` requires a bearer token
compared with `hmac.compare_digest`; a missing token is 401, a wrong token 403,
an unknown service 404 — none leak internal detail.

## ADR rationale

No new ADR. The private operator interface, allowlisting, token auth, and
loopback-only exposure are already fixed by the accepted operator control-plane
decision. FastAPI + env config mirror the existing `infra/enrollment/` service.

## BDD / TDD

`infra/operator/tests/` (pytest + FastAPI `TestClient` + a `FakeServiceInspector`,
mirroring `infra/enrollment/tests`): `test_config` (missing `OPERATOR_TOKEN`
fails loud; host/port defaults); `test_services` (`status_all` reports each
allowlisted service from the fake inspector; `status_one` on an unknown name is
fail-closed); `test_app` (`/healthz` open; `/status` 401 without token, 403 with
a wrong token, 200 with the right token; `/status/{unknown}` 404;
`/status/{known}` 200). No real `systemctl`/`docker` call is made in tests.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host (reusing
  the existing `.venv-enrollment`, which already has FastAPI + pytest).
- `scripts/check_record_sync.sh` (exit 0). The GUT suite is unaffected
  (Python-only slice). Recorded on completion.

## Root-cause learning

Observed: `python -m pytest infra/operator/tests` failed at collection with
`ModuleNotFoundError: No module named 'operator.tests'; 'operator' is not a
package`.

Hypothesis and check: `infra/` had no `__init__.py`, so pytest's prepend import
mode walked up only to `operator/` and named the test module `operator.tests.*`,
which resolves to Python's built-in stdlib `operator` module (not a package).
Discriminating check: the enrollment package avoided this only because there is
no stdlib module named `enrollment`.

Root cause and countermeasure: a package named `operator` collides with the
stdlib when `infra` is a namespace package. Added `infra/__init__.py` so `infra`
is a real package and its tests import as `infra.operator.tests.*` (and
`infra.enrollment.*`, `infra.opnsense.*`), never bare `operator`. Regression
evidence: the operator pytest suite now collects and passes, and the existing
enrollment suite still passes under the same import naming.
