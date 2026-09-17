# Slice 049: WireGuard peer revocation/ban lifecycle (logic + tests)
GitHub issue: #95

Status: delivered (revocation logic + automated tests; live OPNsense
deletion and the real ~25s tunnel-teardown timing remain pending)

Tracker context: Phase 13 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
against the resolved design in
[issue 06 — peer revocation and ban lifecycle protocol](../../.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md).
Builds directly on
[Slice 048](048-wireguard-enrollment-service.md)'s `infra/enrollment/` code:
the same injectable `OpnsenseWireguardClient` seam, the same sqlite3
`EnrollmentStore`, and the same fail-closed/records-first discipline.

## SDD

**Problem.** Slice 048 can enroll a peer but has no way to remove one. Once a
player is banned or an account is revoked, the peer's WireGuard entry and its
allocated `/32` stay live and allocated forever — the pool leaks addresses and
a banned player keeps a working tunnel. Revocation must reuse the same
fail-closed discipline as enrollment: a peer must never be recorded as gone
locally unless OPNsense actually dropped it, or a ban silently does nothing
while looking like it succeeded.

**Outcome.** `infra/enrollment/opnsense_client.py` gains `delete_client(uuid)`
on the injectable `OpnsenseWireguardClient` seam, implemented in
`RealOpnsenseWireguardClient` by calling OPNsense
`wireguard/client/delClient/<uuid>` (POST) and then reusing the existing
`reconfigure()` — mirroring `add_client`'s call shape and reusing
`run_api_call`/`OpnsenseApiError` exactly. `infra/enrollment/store.py` gains
`release_allocation_by_public_key`, a single-transaction lookup-then-delete
that returns the allocation's `opnsense_client_uuid` for the caller to have
already used, and only removes the `allocations` row (freeing its `/32` back
to the pool) once the caller confirms upstream success.
`infra/enrollment/service.py` gains `RevocationService.revoke(public_key)`,
mirroring `EnrollmentService.redeem`'s structure: look up the allocation,
call OPNsense `delete_client` then `reconfigure`, and only then commit the
local release — fail-closed, so an upstream failure leaves the peer fully
allocated and enrolled for an operator retry. `infra/enrollment/cli.py` gains
a `revoke-peer <public_key>` admin subcommand. No HTTP endpoint is added (see
Boundary below).

**Boundary / scope.** In scope: the `delete_client` OPNsense seam method, the
store's atomic release-by-public-key transaction (and its `next_free_address`
interaction so a released `/32` is handed out again), `RevocationService`,
and the CLI subcommand. Everything is proven against a fake OPNsense client
and a temp sqlite DB, exactly like Slice 048.

**Non-goals (explicitly out of scope for this slice).**

- Any live OPNsense call or a real ban against a running instance. This is
  service logic proven by automated tests against a fake OPNsense client, the
  same records-first posture Slice 048 used.
- The actual ~25 second tunnel-teardown timing after `delClient`/
  `reconfigure` succeed. That is a live/runtime property of OPNsense's
  WireGuard keepalive handling, not something a unit test can assert; this
  document describes the expected behavior (issue 06's answer: within one
  keepalive interval, handshakes fail and the client's tunnel drops) without
  claiming to have measured it.
- Idempotent re-enrollment (issue 06's point 4: "an existing account can
  re-enroll with a new public key by updating the existing peer UUID rather
  than leaking stale peers"). This slice does **not** build that path. It is
  recorded as a deliberate, documented follow-up — see Assumptions.
- An account/auth model or any public-facing admin API authentication.
  Revocation stays CLI/operator-only in this slice (see Invariants).
- GeoIP allowlisting or request rate-limiting.
- Any change to Godot game/client/server code (`client/`, `server/`,
  `shared/`) or `native/wgnetstack/`. No `.gd` files are touched.
- Any push to a remote or live network call of any kind during validation.

**Public seam.** `infra/enrollment/service.py`'s
`RevocationService.revoke(public_key: str) -> RevocationResult` is the single
authoritative entry point. `infra/enrollment/cli.py` exposes it as
`python -m infra.enrollment.cli revoke-peer <public_key>`.
`OpnsenseWireguardClient.delete_client(uuid: str) -> None` (the same
injectable `Protocol` from Slice 048) is the seam tests substitute a fake
for; `RealOpnsenseWireguardClient.delete_client` is the only implementation
that performs network I/O, reusing `run_api_call`/`OpnsenseApiError` exactly
as `add_client` does.

**Identifier choice.** Revocation is keyed on the peer's **public_key**, not
`ip_address` or `invite_code`. Rationale: an operator banning a player
identifies "which WireGuard peer" the same way OPNsense's own client list
does — by the client's public key — and `public_key` is the value a
support/ops workflow is most likely to have on hand when acting on an abuse
report (it is also visible in the OPNsense UI's client list, unlike the
single-use invite code, which is discarded after redemption and not
associated with the peer in the operator's mental model). `ip_address` was
rejected because it is an internal allocation detail the operator should not
need to look up first, and it is only present in the local store, not in
OPNsense's UI. `invite_code` was rejected because after redemption it is a
one-time-use historical artifact, not how a live peer is identified. The
allocations table's `public_key` column, already written by
`EnrollmentStore.redeem_invite`, is the lookup key.

**Invariants.**

- **Fail-closed ban.** If `delete_client` raises `OpnsenseApiError`, the
  service raises `RevocationRejected(UPSTREAM_DELETE_FAILED)` and performs
  **no** local store mutation: the allocation row, its `/32`, and the
  OPNsense peer registration all remain exactly as they were. A banned peer
  must never keep working WireGuard access because a delete error was
  swallowed; the operator retries the same `revoke()` call.
- **Idempotent no-op on an absent peer.** Revoking a `public_key` with no
  matching allocation row (never enrolled, or already revoked by a prior
  successful call) is a successful no-op: `RevocationResult.outcome ==
  ALREADY_ABSENT`. No OPNsense call is made (there is no `opnsense_client_uuid`
  to call `delete_client` with), and no exception is raised. Replaying a
  revocation is always safe.
- **Reconfigure failure is also fail-closed.** If `delete_client` succeeds
  but the subsequent `reconfigure()` raises, the service still raises
  `UPSTREAM_DELETE_FAILED` and still makes no local release — OPNsense's
  running config may not have picked up the deletion yet, so the local state
  must not claim the peer is gone until both calls are confirmed to have
  succeeded. (This mirrors `EnrollmentService.redeem`'s existing treatment of
  `add_client` vs. `reconfigure` failures identically.)
- **Local release only after confirmed upstream success.** The store's
  release only ever runs after the caller (the service) has already
  completed both OPNsense calls without raising. The store method itself
  never calls OPNsense; it is a pure, atomic sqlite transaction.
- **Released `/32` re-enters the pool immediately.** Once the allocation row
  is deleted, `next_free_address` (unchanged since Slice 048) recomputes the
  free set from the current `allocations` table on every call, so the
  released address is eligible for the very next redemption.
- **Invite history is preserved.** Revoking a peer does **not** touch the
  `invites` table. The invite stays `redeemed_at`-set and is never made
  redeemable again — issue 06's optional re-enrollment path (reusing the
  existing peer UUID for the same account) is not built here; only the
  `allocations` row for that peer is removed. See Assumptions for the
  follow-up this leaves open.
- **Operator-only surface.** No HTTP endpoint is added for revocation in
  this slice. `infra/enrollment/app.py`'s only route remains the public
  `POST /redeem`. Revocation is reachable only via
  `infra.enrollment.cli revoke-peer`, run by whoever holds shell/CLI access
  to the enrollment host — the same trust boundary as
  `cli.py mint-invite` already relies on. Adding an HTTP admin route with no
  authentication model would let anyone on the network revoke any peer,
  which is a worse security posture than not having an HTTP admin route at
  all; this is a deliberate scope decision, not an oversight.
- **Bounded rejection reasons.** `RevocationRejected.reason` is one
  of the `RevocationRejectionReason` enum values; no free-text or exception
  string leaks as a client-facing "reason".

**Failure behavior.** `UPSTREAM_DELETE_FAILED` is the only rejection path
and, per the invariants above, is always side-effect-free — no partial local
mutation, matching the intent-validation "rejection is a first-class result"
contract in `CLAUDE.md`. `ALREADY_ABSENT` is not a rejection; it is a
successful, idempotent outcome value.

**Rollback.** Deleting the new `delete_client`/`RevocationService`/
`release_allocation_by_public_key`/CLI-subcommand code and this document
fully reverts the slice; `EnrollmentService.redeem`'s behavior and schema are
untouched (no migration, no column added or removed).

**ADR-or-no-ADR rationale.** No new ADR. This slice implements the
already-`resolved` design decision recorded in
`.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md` (OPNsense
`delClient` + `reconfigure`, local `/32` reclamation) without deviating from
its fail-closed intent, and makes one implementation-level choice not pinned
by that ticket — keying on `public_key` rather than `ip_address` or
`invite_code` (justified above) — which is a non-architectural storage/API
detail of a standalone Python service, the same class of decision Slice 048
made for its storage engine.

## BDD

### Revoking an active peer succeeds and frees its `/32`

Given an invite that has been redeemed, producing an `allocations` row with a
known `public_key`, `ip_address`, and `opnsense_client_uuid`
When `RevocationService.revoke(public_key)` is called against a fake OPNsense
client configured to succeed
Then the fake's `delete_client` is called once with that row's
`opnsense_client_uuid`, `reconfigure` is called once, the service returns
`RevocationResult(outcome=REVOKED)`, the `allocations` row for that
`public_key` no longer exists, and a subsequent `next_free_address` call
returns that now-freed `/32` (proven by re-redeeming a fresh invite in a
pool with exactly one address and observing it receives the same address
back).

### Revoking an unknown or already-revoked peer is an idempotent no-op

Given a `public_key` with no matching row in `allocations` (never enrolled,
or already successfully revoked by an earlier call)
When `RevocationService.revoke(public_key)` is called
Then the service returns `RevocationResult(outcome=ALREADY_ABSENT)`, makes no
OPNsense call at all, and calling `revoke()` again with the same key produces
the identical result with no error and no side effect.

### OPNsense `delClient` failure is fail-closed (no local release)

Given a redeemed allocation and a fake OPNsense client configured to raise
`OpnsenseApiError` on `delete_client`
When `RevocationService.revoke(public_key)` is called
Then the service raises `RevocationRejected(UPSTREAM_DELETE_FAILED)`, the
`allocations` row for that `public_key` still exists unchanged (same
`ip_address`, same `opnsense_client_uuid`), `reconfigure` was never called,
and a subsequent retry with a healthy fake OPNsense client succeeds and
releases the row (proving no partial state blocked the retry).

### OPNsense `reconfigure` failure after a successful `delClient` is also fail-closed

Given a redeemed allocation and a fake OPNsense client whose `delete_client`
succeeds but whose `reconfigure` raises `OpnsenseApiError`
When `RevocationService.revoke(public_key)` is called
Then the service raises `RevocationRejected(UPSTREAM_DELETE_FAILED)` and the
`allocations` row still exists unchanged, matching the `delClient`-failure
scenario's guarantee — the local state never claims the peer is released
unless both upstream calls are confirmed to have succeeded.

## TDD

Public seam under test: `RevocationService.revoke()` (called directly), plus
`RealOpnsenseWireguardClient.delete_client`'s request shape and the store's
`release_allocation_by_public_key` atomic transaction.

Test plan (`infra/enrollment/tests/`):

- `test_opnsense_client.py` (extended) — `delete_client` sends `POST` to
  `wireguard/client/delClient/<uuid>` and raises `OpnsenseApiError` on a
  non-`saved`/non-`deleted` result, mirroring the existing `add_client`/
  `reconfigure` request-shape tests; no real network access
  (`no_real_subprocess`-style guard reused).
- `test_store.py` (extended) — `release_allocation_by_public_key` deletes the
  row and returns the freed `opnsense_client_uuid`; returns `None` for an
  absent `public_key` without raising; the freed `/32` is handed out again by
  `next_free_address`.
- `test_service.py` (extended, or a new `test_revocation_service.py`) — the
  four BDD scenarios above via `RevocationService`, using a temp sqlite DB
  and a fake OPNsense client extended with `delete_client` recording/failure
  configuration (`fakes.py` extended).
- `test_cli.py` (extended) — `revoke-peer <public_key>` invokes
  `RevocationService.revoke` and prints a bounded outcome string.

Every scenario runs against a temporary sqlite file (`tmp_path`) or
in-memory DB, never a real OPNsense endpoint.

## Validation

Commands run from the repository root:

```
python3 -m pytest infra/enrollment/tests -q
```

Result: 54 passed, exit 0 (39 pre-existing Slice 048 tests unchanged, plus 15
new revocation tests).

```
scripts/check_record_sync.sh
```

Result: 0 errors, 6 pre-existing historical warnings (unchanged from before
this slice), exit 0.

No `.gd` files were changed in this slice, so `scripts/run_gut_validation.sh`
was not run — the existing GUT suite is unaffected by a Python-only,
`infra/`-scoped change.

## Assumptions

- Idempotent re-enrollment (issue 06 point 4 — reusing an existing peer UUID
  so a revoked account can immediately re-enroll under a new public key
  without leaking the old peer) is **not** built in this slice. It is a
  documented, deliberately deferred follow-up: today, after revocation, the
  only way back in for that player is a fresh invite code (a new
  `mint-invite`), which allocates a new `/32` and a new OPNsense peer. This
  is safe (no stale peer is leaked; the old one is actually deleted) but is
  less convenient than issue 06's optional re-enrollment shortcut.
- No HTTP endpoint is added for revocation; it is CLI-only, per the
  Invariants section's operator-only-surface rationale.
- The `~25s` tunnel-teardown timing is described, not asserted, since it
  depends on live OPNsense/WireGuard keepalive behavior outside this
  service's process.
