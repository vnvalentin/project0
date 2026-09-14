# Slice 058 — In-process login gateway seam over AuthService/CharacterService

Status: **in progress**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md)
(step 1: extract a narrow internal login interface from the existing services,
in-process, without changing current behavior). Fourth delivery of the
[container-platform map](../../.scratch/container-platform/map.md).

## User outcome

The server's login/character request handling flows through one narrow login
interface (`LoginGateway`) instead of two separate services, establishing the
single seam a future out-of-process login service (signed assertions over
private HTTPS, Slices 059–060) will satisfy — with no change to current
behavior, RPCs, or persistence.

## Scope and non-goals

In scope: a server-only `LoginGateway` node that composes the existing
`AuthService` (register/login/session) and `CharacterService` (Character CRUD +
selected-Character resolution) behind one documented interface by pure
delegation; wiring `server_main.gd` to construct it; rerouting the login and
character RPC receivers in `client/network_client.gd` to resolve the single
`/root/LoginGateway` node; and a focused delegation test.

Out of scope (later slices): signed session assertions and the assertion
validation seam (Slice 059); the separate out-of-process login service over
private HTTPS (Slice 060); splitting accounts into a separate database; any
change to `AuthService`, `CharacterService`, `SessionRegistry`, the repository,
PBKDF2, the wire contract, or the RPC method names/shapes. Behavior is
byte-for-byte identical; `AuthService` and `CharacterService` are consumed
unmodified.

## Public seam

`server/login_gateway.gd` (`class_name LoginGateway`, a `/root` Node like
`AuthService`), constructed with the `AuthService` and `CharacterService`
instances:

- `register(peer_id, username, password)` / `login(...)` — delegate to
  `AuthService` (coroutines; PBKDF2 stays off-thread there).
- `is_authenticated(peer_id)` / `clear_session(peer_id)` — game-server-local
  session state.
- `list_characters` / `create_character` / `select_character` /
  `delete_character` / `get_selected_character` — delegate to
  `CharacterService`, which still derives the account from the peer's session.

`client/network_client.gd` login/character/enter-world RPC receivers resolve
`/root/LoginGateway` and call it, instead of `/root/AuthService` and
`/root/CharacterService` directly.

## Safety invariant

Pure delegation, server-only. The client still never supplies an `account_id`;
`CharacterService` still derives it from the peer's session. No credential
material, DB handle, or `detail` string crosses the wire. If the gateway node
is absent, the receivers no-op exactly as they did when a service node was
absent — fail-closed with no side effect.

## ADR rationale

No new ADR. The login-boundary decision (accepted) already fixes this seam as
migration step 1; this slice implements it without deviation.

## BDD / TDD

`tests/integration/test_login_gateway.gd` (written first) constructs a
`LoginGateway` over a real `AuthService` + `CharacterService` on a temporary
SQLite store and proves the facade delegates: `register` binds a session
(`is_authenticated` true); `login` re-authenticates; `create_character` /
`list_characters` / `select_character` / `get_selected_character` /
`delete_character` return the same results as the underlying service; and
`clear_session` clears the session. The existing `test_account_auth_session.gd`
and `test_character_crud_rpc.gd` stay green (services unchanged).

## Validation

- Focused: `tests/integration/test_login_gateway.gd`.
- Full GUT gate on the Linux host: `scripts/run_gut_validation.sh` (expected
  green, including the real-server e2e harnesses that exercise the rerouted RPC
  dispatch); `scripts/check_record_sync.sh` exit 0. Recorded on completion.

## Root-cause learning

None yet.
