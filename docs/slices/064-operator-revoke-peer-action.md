# Slice 064 — Operator control plane: audited revoke-peer action

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
("peer revocation … reuse the existing enrollment CLI seams through the
adapter"). Tenth delivery of the
[container-platform map](../../.scratch/container-platform/map.md).

## User outcome

An operator can revoke an enrolled WireGuard peer through the private,
authenticated control plane; the action is an auditable job, reusing the
enrollment `RevocationService` (delete the OPNsense peer, release its `/32`),
fail-closed.

## Scope and non-goals

In scope: a `PeerAdmin` adapter (`infra/operator/peers.py`) that reuses
`infra/enrollment/service.py`'s `RevocationService`, translating its bounded
`RevocationOutcome`/`RevocationRejected` into an outcome string or a bounded
`PeerRevocationError`; `OperationsService.revoke_peer(operator, public_key)`
returning an audited `Job`; `POST /peers/revoke` (bearer-authed, JSON body
`{public_key}`, `X-Operator` header); and pytest against a fake peer admin.

Out of scope (later slices): `/update`; start/stop; a durable audit sink;
changing the enrollment service. The endpoint uses a JSON body rather than the
decision's `/peers/{public_key}/revoke` path shape because a WireGuard public
key is base64 (contains `+`/`/`/`=`) and is not URL-path-safe. Revoke requires
the enrollment OPNsense credentials; when they are unset the peer admin is
unavailable and the endpoint returns a `failed` job (the rest of the operator
service still runs). No game `.gd` change; the GUT suite is unaffected.

## Public seam

- `infra/operator/peers.py` (`PeerAdmin` Protocol, `PeerRevocationError`,
  `RealPeerAdmin(revocation_service)`: `revoke_peer(public_key) -> outcome`).
- `infra/operator/operations.py` (`OperationsService.revoke_peer(operator,
  public_key) -> Job`): fail-closed to a `failed` job with a bounded reason when
  the admin is absent, rejects, or raises.
- `infra/operator/app.py` (`POST /peers/revoke` with body `{public_key}`).

## Safety invariant

Every revoke is an authenticated, audited job. Revoking an absent peer is a
successful `ALREADY_ABSENT` outcome (idempotent), not an error. An upstream
OPNsense failure is a `failed` job carrying only the bounded
`UPSTREAM_DELETE_FAILED` reason — never a stack trace or unbounded text. The
public key is not a secret (it is a public key), so it is recorded as the job
target; no OPNsense credential is ever logged or returned.

## ADR rationale

No new ADR. Reusing the enrollment revocation seam behind the job/audit model is
already fixed by the accepted operator control-plane decision; keying on the
public key mirrors Slice 049.

## BDD / TDD

`infra/operator/tests/test_peers.py`: `revoke_peer` on a healthy admin yields a
`succeeded` job with the `REVOKED`/`ALREADY_ABSENT` outcome and records it; a
`PeerRevocationError` yields a `failed` job carrying the bounded reason; an
absent admin is fail-closed. `infra/operator/tests/test_peers_api.py`: `POST
/peers/revoke` is 401 without a token, 403 with a wrong token, 200 with a
`succeeded` job on success (and `X-Operator` recorded), 200 with a `failed` job
on rejection; `GET /jobs` lists the revoke job. A fake peer admin is used — no
real OPNsense call.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host (reusing
  `.venv-enrollment`).
- `scripts/check_record_sync.sh` (exit 0); GUT unaffected (Python-only).
  Recorded on completion.

### Result (Linux host `192.168.1.254`, 2026-09-14)

`.venv-enrollment/bin/python -m pytest infra/operator/tests` passed **41 tests**
(32 from Slices 061–063 + 9 new: 4 `test_peers` + 5 `test_peers_api`), 0
failures — covering the audited revoke lifecycle, idempotent `ALREADY_ABSENT`
success, the bounded `UPSTREAM_DELETE_FAILED` rejection, and the empty-key 422.
`scripts/check_record_sync.sh` reported 0 errors, exit 0. GUT unaffected (no
`.gd` change).

## Root-cause learning

None yet.
