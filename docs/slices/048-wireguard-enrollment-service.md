# Slice 048: WireGuard invite-code enrollment service (logic + tests)

Status: delivered (service logic + automated tests; live deployment pending)

Tracker context: Phase 13 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
against the resolved design in
[issue 04 — enrollment service invite system](../../.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md).
Builds on [Slice 028](028-wireguard-remote-access-infrastructure-foundation.md)
(OPNsense `wg0` tunnel + firewall isolation, one hand-enrolled peer) and reuses
the request/error pattern from `infra/opnsense/setup_wireguard_game_tunnel.py`.

## SDD

**Problem.** Slice 028 proved the tunnel and firewall isolation with exactly
one hand-enrolled Windows peer. There is no self-serve way for an invited
player to redeem an invite and receive a peer configuration without an
operator manually calling the OPNsense UI/API. Growing beyond one tester
requires a bounded, single-use, auditable enrollment path that never grants an
invite code more than one successful redemption, never exhausts the `/32`
pool silently, and never leaves partial state (a consumed invite with no
registered peer, or a registered peer with no persisted allocation) if the
OPNsense call fails partway through.

**Outcome.** A small FastAPI service under `infra/enrollment/` accepts a
single-use invite code and a client-generated WireGuard **public** key,
allocates the next free `/32` from `10.77.0.0/24` (excluding `.0`, the
server's own `.1`, and `.255`), registers the peer with OPNsense
(`client/addClient` then `service/reconfigure`) through an injectable client
interface, and — only if that registration succeeds — durably marks the
invite redeemed and commits the IP allocation in one local SQLite
transaction. It returns the peer config bundle: server public key, endpoint
`game.valentin.vip:51900`, the assigned `/32`, split-tunnel
`AllowedIPs=192.168.1.254/32`, and a persistent-keepalive value. A CLI mints
new invite codes (CSPRNG, `secrets.token_urlsafe`, optional expiry).

**Boundary / scope.** In scope: invite minting and single-use redemption,
public-key format validation, `/32` pool allocation, the OPNsense
registration call through an injectable interface (a fake in tests, no live
call), the local SQLite store (invites + allocations, atomic redemption), the
FastAPI redeem endpoint, and the admin CLI. Everything is environment-config
driven (OPNsense base URL, API key/secret, server public key, endpoints, pool
CIDR) with no secrets committed.

**Non-goals (explicitly out of scope for this slice).**

- Live OPNsense deployment or issuing a real peer against a running instance.
  This slice is service logic proven by automated tests against a fake
  OPNsense client, mirroring how Slice 028's infra script was records-first
  before its live bring-up evidence landed separately.
- The `enroll.valentin.vip` nginx/HTTPS reverse-proxy configuration. This
  slice's FastAPI app is transport-agnostic; TLS termination and public DNS
  are a follow-up ops step.
- Revocation/ban lifecycle (issue 06, a separate future slice, tracked as S5
  in the P-024 roadmap).
- GeoIP allowlisting or request rate-limiting.
- Any change to Godot game/client/server code (`client/`, `server/`,
  `shared/`) or the `native/wgnetstack/` GDExtension. Nothing here touches
  `.gd` files.
- Any push to a remote or live network call of any kind during validation.

**Public seam.** `infra/enrollment/service.py`'s `EnrollmentService.redeem(
code: str, public_key_b64: str) -> PeerConfigBundle` is the single authoritative
entry point; `infra/enrollment/app.py` exposes it over HTTP as
`POST /redeem`, and `infra/enrollment/cli.py` exposes invite minting as
`python -m infra.enrollment.cli mint-invite [--expires-in-seconds N]`.
`OpnsenseWireguardClient` (an injectable `Protocol` in
`infra/enrollment/opnsense_client.py`) is the seam tests substitute a fake
for; `RealOpnsenseWireguardClient` is the only implementation that performs
network I/O, and it reuses `infra/opnsense/setup_wireguard_game_tunnel.py`'s
`OpnsenseApiError` type and `run_api_call` curl-based request helper directly
rather than re-implementing HTTP/auth handling.

**Invariants.**

- An invite code has exactly one successful redemption, ever. Redemption and
  the local IP-allocation commit happen in a single SQLite transaction keyed
  by the invite's primary key, so a second concurrent/retried redemption
  attempt against an already-redeemed code is rejected before any OPNsense
  call is made.
- The client's WireGuard **private** key is never part of any request,
  response, log line, or stored row. Only the client-supplied **public** key
  is accepted, validated, and persisted.
- If the OPNsense registration call raises, the transaction is rolled back:
  no row is inserted into `allocations`, and the invite's `redeemed_at`/
  `redeemed_by` fields are not set. The failed attempt is reported as a 5xx
  with a bounded reason and leaves the invite redeemable again.
- The `/32` allocator never returns the network address (`10.77.0.0`), the
  server's own address (`10.77.0.1`), or the broadcast address (`10.77.0.255`)
  and never double-allocates an address recorded in `allocations`.
- All public-facing rejections (bad code, expired code, already-redeemed code,
  malformed public key, exhausted pool, upstream failure) return a bounded
  reason string; none of them partially mutate durable state.
- Config (OPNsense base URL/key/secret, server public key, WireGuard
  endpoint, split-tunnel target, pool CIDR, keepalive) comes only from
  environment variables, mirroring `infra/opnsense/setup_wireguard_game_tunnel.py`'s
  `get_api_credentials`/`os.getenv` pattern. No secret or real key is
  committed; the local SQLite DB path is configurable via
  `ENROLLMENT_DB_PATH` and defaults to a repo-ignored `infra/enrollment/.data/`
  directory.

**Failure behavior.** Every rejection path (invalid/expired/already-redeemed
code, malformed public key, exhausted pool, upstream OPNsense error) is
first-class and side-effect-free: nothing is written to `invites` or
`allocations` unless redemption fully succeeds, matching the intent-validation
"rejection is a first-class result" contract in `CLAUDE.md`.

**Rollback.** Deleting `infra/enrollment/` and its two feature-list/tracker
edits fully reverts this slice; no OPNsense or Canon state is touched, and no
schema migration exists outside the enrollment service's own private SQLite
file.

**ADR-or-no-ADR rationale.** No new ADR. This slice implements the
already-`resolved` design decision recorded in
`.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md`
(FastAPI service, single-use invite codes, OPNsense `addClient` +
`reconfigure`, split-tunnel peer bundle) without deviating from it. The only
implementation-level choice not already pinned by that ticket is the storage
engine: plain Python stdlib `sqlite3` (not `godot-sqlite`, which is a Godot
GDExtension with no meaning outside the engine process) — a natural,
non-architectural choice for a standalone Python service, consistent with
`CLAUDE.md`'s instruction that only Canon/game persistence choices need a
recorded decision.

## BDD

### Normal redemption

Given a fresh, unexpired, unredeemed invite code and a syntactically valid
44-character base64 WireGuard public key
When the client calls `POST /redeem` with that code and public key
Then the service allocates the next free `/32` from `10.77.0.0/24`, calls the
fake OPNsense client's `add_client` then `reconfigure`, commits the invite as
redeemed and the allocation as durable in one transaction, and returns a peer
config bundle containing the server's public key, endpoint
`game.valentin.vip:51900`, the assigned `/32`, `AllowedIPs=192.168.1.254/32`,
and a persistent-keepalive value.

### Single-use re-redeem rejected

Given an invite code that has already been successfully redeemed
When a second redemption request is made with the same code (same or
different public key)
Then the service rejects it with a bounded `INVITE_ALREADY_REDEEMED` reason,
makes no OPNsense call, and allocates no additional `/32`.

### Pool exhausted

Given every allocatable `/32` in `10.77.0.0/24` (excluding `.0`, `.1`, and
`.255`) is already recorded in `allocations`
When a valid, unredeemed invite is redeemed with a valid public key
Then the service rejects it with a bounded `POOL_EXHAUSTED` reason before
calling OPNsense, and the invite remains unredeemed (redeemable once the pool
frees up).

### Invalid or expired code

Given a code that does not exist, or an invite whose `expires_at` is in the
past
When redemption is attempted
Then the service rejects it with `INVITE_NOT_FOUND` or `INVITE_EXPIRED`
respectively, makes no OPNsense call, and allocates nothing.

### Malformed public key

Given an invite that is valid and unredeemed
When the request supplies a public key that is not valid base64, does not
decode to exactly 32 bytes, or is not 44 characters ending in `=`
Then the service rejects it with a bounded `INVALID_PUBLIC_KEY` reason before
allocating an IP or calling OPNsense, and the invite remains unredeemed.

### OPNsense API failure rolls back with no local allocation

Given a valid, unredeemed invite, a valid public key, and a fake OPNsense
client configured to raise `OpnsenseApiError` on `add_client`
When redemption is attempted
Then the service returns a bounded 5xx `UPSTREAM_REGISTRATION_FAILED` result,
no row is written to `allocations`, the invite's `redeemed_at`/`redeemed_by`
remain unset, and a subsequent retry with the same invite is still possible
(proving no partial durable state was left behind).

## TDD

Public seam under test: `EnrollmentService.redeem()` (called directly, and
indirectly through the FastAPI `TestClient` for the HTTP contract), plus the
public-key validator, the `/32` allocator, and the sqlite store's atomic
redemption transaction.

Test plan (`infra/enrollment/tests/`):

- `test_store.py` — invite CRUD/expiry, allocator sequencing and pool
  boundaries (`.0`/`.1`/`.255` excluded, exhaustion), atomic redemption commit
  and rollback-on-exception, applied-invite idempotency.
- `test_pubkey_validation.py` — accepts a well-formed 44-char base64 32-byte
  key; rejects non-base64, wrong-length-decoded, and non-`=`-terminated
  input, each with a bounded reason.
- `test_opnsense_client.py` — the injectable `Protocol` seam; a fake records
  calls with no real network access (`no_real_subprocess`-style guard mirrored
  from `infra/opnsense/tests/test_setup_wireguard_game_tunnel.py`).
- `test_service.py` — the six BDD scenarios above via `EnrollmentService`
  directly, using a temp sqlite DB (`tmp_path`) and a fake OPNsense client;
  explicitly asserts no private-key field or value exists anywhere in the
  request path, the response, or the persisted rows.
- `test_app.py` — the FastAPI `POST /redeem` contract via `TestClient`: 200 on
  success, 404/409/410/422 for invalid/already-redeemed/expired/malformed
  input, 502 on upstream OPNsense failure, using dependency overrides to inject
  the fake OPNsense client and a temp DB.
- `test_cli.py` — invite minting produces a high-entropy, previously-unseen
  code and an optional expiry that the store records.

Every scenario runs against a temporary sqlite file (via `tmp_path`), never
the developer's real filesystem state, and never a real OPNsense endpoint.

## Validation

Commands run from the repository root:

```
python3 -m pytest infra/enrollment/tests -q
```

Result: 39 passed, exit 0. (System Python 3.12.3 already had `fastapi`,
`httpx`, and `pytest` importable; no venv was required.)

```
scripts/check_record_sync.sh
```

Result: 0 errors, 6 pre-existing historical warnings (unchanged from before
this slice), exit 0.

No `.gd` files were changed in this slice, so `scripts/run_gut_validation.sh`
was not run, per this slice's ticket instructions — the existing GUT suite is
unaffected by a Python-only, `infra/`-scoped change.

## Assumptions

- `PERSISTENT_KEEPALIVE_SECONDS` defaults to `25`, matching the existing
  hand-enrolled peer's `keepalive` value in
  `infra/opnsense/setup_wireguard_game_tunnel.py`'s `cmd_add_peer`.
- The redeem endpoint is a single `POST /redeem` accepting
  `{"invite_code": str, "public_key": str}` and returning the peer bundle as
  JSON; no additional endpoints (status/health) were added since none were
  requested.
- The default local DB path (`infra/enrollment/.data/enrollment.sqlite3`) is
  git-ignored; `ENROLLMENT_DB_PATH` overrides it for deployment.
