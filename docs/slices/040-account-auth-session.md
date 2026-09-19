# Slice 040 — Account authentication and session (server)
GitHub issue: #95

Status: **delivered** (server-side auth/session seam; additive RPCs; no
mandatory-auth gate, no client UI, no Character CRUD).

Phase: 14 (Player accounts and characters). New feature: **F-031**.

Design basis: [player-accounts spec](../../.scratch/player-accounts/spec.md)
(Implementation Slice 3, "Account auth + session (server)") and
[.scratch/player-accounts/handoff-040-account-auth-session.md](../../.scratch/player-accounts/handoff-040-account-auth-session.md)
(the bounded implementation brief for this slice). Consumes
[Slice 038](038-shared-sqlite-persistence-foundation.md)'s `SqliteStore`
(`server/sqlite_store.gd`, F-029) and
[Slice 039](039-accounts-characters-repository.md)'s
`AccountCharacterRepository` (`server/account_character_repository.gd`,
`shared/character_record.gd`, `shared/account_handle.gd`, F-030) — **all
consumed unmodified**, per the handoff's explicit "files to preserve" list.

## User outcome

A connected peer can **register** a new Account or **log in** to an existing
one over the ENet link. The server verifies credentials with
**PBKDF2-HMAC-SHA256 off the main thread**, binds an **opaque in-memory
session** to the peer on success, and returns an `AccountHandle` or a
**bounded rejection** — all server-authoritative and fail-closed. This is also
the first slice to boot-wire the Slice 038/039 persistence stack into the
running server (`server_main.gd` now opens a real `SqliteStore` and calls
`AccountCharacterRepository.ensure_schema()` at startup).

## Scope

**In scope (this slice):**

1. `server/password_hasher.gd` (`class_name PasswordHasher`), server-only:
   PBKDF2-HMAC-SHA256 built on Godot `Crypto` — `generate_random_bytes` for a
   16-byte CSPRNG salt, `hmac_digest(HashingContext.HASH_SHA256, ...)` as the
   PRF for a from-scratch PBKDF2 block construction (RFC 8018; Godot's
   `Crypto` has no built-in PBKDF2), `constant_time_compare` for verification.
   32-byte derived key; iteration count stored with the record (default
   100000, matching the spec example). Exposes a pure, synchronous, unit
   testable core: `hash_password(password, iterations) -> {salt, hash,
   iterations}` (hex-encoded strings) and `verify_password(password, salt_hex,
   hash_hex, iterations) -> bool`.
2. `server/session_registry.gd` (`class_name SessionRegistry`), server-only:
   in-memory `peer_id -> {session_token, account_id, username,
   authenticated_at}` keyed by peer id, an opaque CSPRNG token via `Crypto`.
   `bind`, `is_authenticated`, `get_session`, `clear`. Never persisted;
   reconnect finds no session and must fully re-authenticate.
3. `server/auth_service.gd` (`class_name AuthService`), server-only: wraps the
   repository, hasher, and session registry. `register`/`login` coroutines
   validate input, dispatch PBKDF2 to a `WorkerThreadPool` task (see
   Threading below), apply the repository/session rules, and return a bounded
   result Dictionary. `is_authenticated`/`clear_session` expose the session
   state to `server_main.gd`'s disconnect handler.
4. RPC seam on `client/network_client.gd` (additive, follows the existing
   `receive_input_intent_on_server`/`receive_authoritative_position` pattern):
   - C→S `@rpc("any_peer", "call_remote", "reliable")`
     `receive_register_request_on_server(username, password)` and
     `receive_login_request_on_server(username, password)`, forwarding via
     `multiplayer.get_remote_sender_id()` to the server's `/root/AuthService`
     node with a plain function call (no second RPC hop), mirroring how
     `receive_action_intent_on_server` forwards to
     `ServerPlayerState_<id>`.
   - S→C `@rpc("authority", "call_remote", "reliable")`
     `receive_auth_result(outcome, account_id, username)` — an `AccountHandle`
     shape on success, a bounded reason String with empty account fields on
     rejection. Never carries a free-text `detail` string over the wire.
   - `submit_register(username, password)` / `submit_login(username,
     password)` client-side helpers (test/harness only, matching
     `submit_input_intent`'s shape) and an `auth_result_received` signal
     (matching `authoritative_position_received`'s relay-only pattern).
5. `server/server_main.gd` boot wiring and dispatch:
   - Opens a `SqliteStore` at `user://accounts.db` (overridable via
     `PROJECT0_ACCOUNTS_DB_PATH`) and calls
     `AccountCharacterRepository.ensure_schema()` **before** the ENet socket
     opens. **Fails closed** (push_error + `quit(1)`, no socket) on either
     failure, mirroring the existing starting-town-hub-fixture check.
   - Builds one `AuthService` instance as `/root/AuthService`, consumed by
     `NetworkClient`'s new RPC targets.
   - `_on_peer_disconnected` now also calls `AuthService.clear_session(peer_id)`
     — additive, before the existing house-release/player-state-teardown
     logic, which is otherwise unchanged.
6. Tests (test-first): `tests/unit/test_password_hasher.gd` (7 tests) and
   `tests/integration/test_account_auth_session.gd` (8 tests).
7. This delivery record, the F-031 feature record, the F-030 promotion, and
   the synchronized `PROJECT-TRACKER.md`/`SLICE-REGISTRY.md` entries.

**Out of scope (explicit non-goals, unchanged from the handoff):**

- Making authentication mandatory for world entry, or changing the existing
  connect → (blueprint, spawn, house, replication) lifecycle in any way. Every
  existing RPC and the spawn-on-connect path in `server_main.gd`/
  `network_client.gd` is byte-for-byte unchanged except for the two additive
  hooks named above (boot wiring before the socket opens; a `clear_session`
  call in the disconnect handler). The world stays always-playable with no
  login required; auth RPCs are purely additive.
- Character CRUD over the wire (create/select/delete RPC) — spec slice 4.
- Client login/register **screens** / `identity_gate.tscn` replacement — spec
  slice 5. `submit_register`/`submit_login` are test/harness helpers only, not
  UI.
- Character → Player instantiation / `start_for_peer` binding — spec slice 6.
- Email verification, recovery, OAuth, MFA, CAPTCHA, rate limiting (spec
  out-of-scope, unchanged).

## Threading

Godot's `Crypto` class has no built-in PBKDF2 primitive, so
`server/password_hasher.gd` builds the RFC 8018 block construction directly on
top of `Crypto.hmac_digest(HashingContext.HASH_SHA256, ...)` as the PRF — this
was verified byte-for-byte against Python's `hashlib.pbkdf2_hmac` before
writing the GUT test (see Validation below).

PBKDF2 at a real iteration count (100000) is deliberately slow — on this host,
a single `hash_password`/`verify_password` call costs roughly 1 second of CPU.
Running that on the main thread would stall the authoritative simulation tick
(and every connected peer's movement/combat) for the duration of every
register/login call. `AuthService.register`/`login` are coroutines: the actual
`PasswordHasher.hash_password`/`verify_password` call runs inside a
`WorkerThreadPool.add_task()` closure, and the calling coroutine `await`s a
`get_tree().process_frame` poll loop until `WorkerThreadPool.is_task_completed`
reports true, then calls the non-blocking `wait_for_task_completion` to fetch
the result. This suspends only the calling coroutine (the RPC dispatch that
called `register`/`login`) — the main thread's per-frame/per-tick work
(`_on_physics_frame`, other peers' `ServerPlayerState._physics_process`, etc.)
keeps running unblocked while a hash is in flight on the worker thread. This
mirrors the existing non-blocking pattern in `server/provisional_sector_generator.gd`
and `server/sector_blueprint_service.gd`, which `await` an `HTTPRequest`
signal instead of a `WorkerThreadPool` task, for the same reason (an
Ollama round-trip must not stall the tick either).

`login()`'s unknown-username path also runs a full off-thread
`hash_password` call against the submitted password before returning
`BAD_CREDENTIALS`, so an unknown username costs the same latency as a wrong
password — not just the same reason string — closing the timing side-channel
the no-enumeration rule is meant to prevent.

## No-ADR rationale

No new ADR. This slice implements the already-accepted ticket 04 design
(PBKDF2-HMAC-SHA256, opaque in-memory sessions, no-enumeration
`BAD_CREDENTIALS`, additive RPC lifecycle) with one implementation-level
decision not dictated by the spec: hand-rolling the PBKDF2 block construction
on `Crypto.hmac_digest` because Godot 4.3 exposes no native PBKDF2 API. This is
an ordinary implementation detail (a standard, unambiguous RFC 8018
construction, proven against a published KAT), not an architectural,
ownership, or persistence decision, so it does not warrant its own ADR.

## Public seam

- `server/password_hasher.gd` (`PasswordHasher`): `SALT_BYTES` (16),
  `KEY_BYTES` (32), `DEFAULT_ITERATIONS` (100000),
  `hash_password(password, iterations) -> {"salt", "hash", "iterations"}`,
  `verify_password(password, salt_hex, hash_hex, iterations) -> bool`.
- `server/session_registry.gd` (`SessionRegistry`): `bind(peer_id, account_id,
  username) -> String`, `is_authenticated(peer_id) -> bool`,
  `get_session(peer_id) -> Dictionary`, `clear(peer_id) -> void`.
- `server/auth_service.gd` (`AuthService`): `_init(repository:
  AccountCharacterRepository)`, `register(peer_id, username, password) ->
  Dictionary` (coroutine), `login(peer_id, username, password) -> Dictionary`
  (coroutine), `is_authenticated(peer_id) -> bool`, `clear_session(peer_id) ->
  void`. Result shape: `{"outcome": "ok", "account_id", "username"}` or
  `{"outcome": REJECT_*, "detail"}` using `CharacterRecord`'s existing bounded
  reason constants (`MALFORMED`, `BAD_CREDENTIALS`, `USERNAME_TAKEN`,
  `ALREADY_AUTHENTICATED`).
- `client/network_client.gd`: `submit_register(username, password)`,
  `submit_login(username, password)`, `auth_result_received(outcome,
  account_id, username)` signal, plus the four new RPC targets
  (`receive_register_request_on_server`, `receive_login_request_on_server`,
  `receive_auth_result`).
- `server/server_main.gd`: boots `/root/AuthService`; `_on_peer_disconnected`
  clears that peer's session.

No UI, no world-entry change, no Character CRUD.

## BDD scenarios

Numbered to match the handoff's acceptance scenarios, all covered by
`tests/integration/test_account_auth_session.gd`:

1. **Register persists + auto-authenticates.** A fresh peer's `register`
   creates a durable Account (verified via `find_account_by_username`), binds
   a session, and returns `{"outcome": "ok", "account_id", "username"}`.
2. **Duplicate username.** A second `register` for the same username ->
   `USERNAME_TAKEN`; the rejected peer holds no session; no second account
   row is created.
3. **Login correct/wrong/unknown.** Correct password -> success + bound
   session; wrong password -> `BAD_CREDENTIALS`; unknown username ->
   `BAD_CREDENTIALS` (the *same* reason, proven by asserting equality against
   the same constant in one test).
4. **Already authenticated.** A second `register` *or* `login` on an
   already-authenticated peer -> `ALREADY_AUTHENTICATED`; the rejected
   `register` creates no new account.
5. **Disconnect clears session.** `clear_session` removes the binding; the
   same `peer_id` must submit `login` again to regain access (a bare
   `is_authenticated` flip does not silently restore access).
6. **PasswordHasher KAT.** `tests/unit/test_password_hasher.gd` reproduces a
   published PBKDF2-HMAC-SHA256 known-answer vector at 1 and 2 iterations,
   confirms 16-byte salt / 32-byte key shape, confirms
   `verify_password` accepts the right password and rejects a wrong one,
   confirms two `hash_password` calls for the same password use distinct
   salts and produce distinct hashes, and confirms determinism (same
   salt+password+iterations always derives the same key).

Additionally covered: malformed (empty username/password) input is rejected
as `MALFORMED` without touching the repository or binding a session; a fresh
`AuthService` instance sharing the same durable repository (simulating a
server restart) starts with no session for any peer, proving the session
token itself is never persisted — only the durable account row survives a
restart.

## TDD

- `tests/unit/test_password_hasher.gd` — 7 test functions, written and run
  red (missing `server/password_hasher.gd`) before the implementation file
  existed, then green.
- `tests/integration/test_account_auth_session.gd` — 8 test functions against
  a temporary per-test `user://` SQLite database (unique filename, cleaned up
  in `after_each`, mirroring `tests/integration/test_account_character_repository.gd`),
  written and run red (missing `server/auth_service.gd`) before the
  implementation existed, then green.
- No changes to any existing test file. `client/network_client.gd` and
  `server/server_main.gd` changes are additive only (new consts/vars,
  new functions, two new call sites in already-existing handlers); every
  pre-existing test in the full suite still passes unmodified.

## Validation

All commands run from the repository root on this host (Godot
`4.3.stable.official.77dcf97d8`, x86_64 Linux).

1. **PBKDF2 correctness proof (pre-implementation, informal):** the from-
   scratch `_derive`/`_derive_block` block construction was cross-checked
   against CPython's `hashlib.pbkdf2_hmac("sha256", ...)` for
   `password`/`salt` at 1 and 2 iterations (32-byte output) and for
   `passwordPASSWORDpassword`/`saltSALTsaltSALTsaltSALTsaltSALTsalt` at 4096
   iterations (40-byte output, truncated to this class's 32-byte `KEY_BYTES`)
   — all four matched byte-for-byte before the GUT known-answer test was
   written.
2. **Reimport + full GUT run:**
   ```
   godot --headless --import
   godot --headless -s addons/gut/gut_cmdln.gd -gjunit_xml_file=/tmp/gut_040.xml -gdisable_colors -gexit
   ```
   Result: `tests/unit/test_password_hasher.gd` **7/7 passed**;
   `tests/integration/test_account_auth_session.gd` **8/8 passed**. Full run:
   **32 scripts, 248 tests, 248 passing, 948 asserts, exit 0** (+2 scripts and
   +15 tests over Slice 039's baseline of 30 scripts / 233 tests).
3. **Full validation gate:**
   ```
   scripts/run_gut_validation.sh
   ```
   **Exit 0.** `build/validation/validation-summary.json`:
   `"status": "passed"`, `"scripts_expected": 32`, `"scripts_ran": 32`
   (DT-007 gate satisfied — no test script silently skipped).
4. **Runtime boot smoke (manual, not part of the automated gate):** ran the
   real headless server (`godot --headless --path . -s server/server_main.gd
   -- --server-bind-address=127.0.0.1`) and confirmed, in order: the starting
   town hub fixture validates, the accounts database opens and its schema is
   ensured (`Accounts database ready at user://accounts.db (schema ensured).`),
   and the server reaches `Server listening on 127.0.0.1:9999` — proving the
   new boot wiring does not block or break the existing always-playable
   connect lifecycle.

Sample accept/reject outcomes observed in the suite: `register("alice",
"hunter2")` succeeds, binds a session, and persists the account; a duplicate
`register("alice", ...)` rejects `USERNAME_TAKEN` with no second row;
`login("alice", "hunter2")` succeeds; `login("alice", "wrong-password")` and
`login("nobody", "whatever")` both reject the identical `BAD_CREDENTIALS`
reason; a second `register`/`login` on an already-bound peer rejects
`ALREADY_AUTHENTICATED`; `clear_session` followed by a fresh `login` succeeds
again; a fresh `AuthService` sharing the same repository starts
unauthenticated for every peer even though the account itself persists.

## Known limitations

- Authentication is **not** mandatory for world entry — by design, per the
  handoff's explicit non-goal. A peer can still connect and play without ever
  calling `register`/`login`; the enforcement flip is a later, separately
  scoped slice (spec slice 5 or beyond).
- No client login/register UI screens — `submit_register`/`submit_login` are
  test/harness helpers, not `identity_gate.tscn` replacements.
- No Character CRUD wiring (spec slice 4) and no Character → Player
  instantiation (spec slice 6).
- No rate limiting, account lockout, email verification, recovery, OAuth, or
  MFA — all explicit spec out-of-scope items, unchanged.
- `AuthService`'s off-thread polling uses `get_tree().process_frame`, so it
  depends on `AuthService` being inside the SceneTree (`server_main.gd` adds
  it under `root` at boot); it cannot be exercised as a bare, non-tree
  `RefCounted` the way `AccountCharacterRepository` can — this is why its
  tests use `add_child_autofree` (matching this codebase's existing Node-based
  test fixture pattern) rather than a plain `.new()`.
- The accounts database path defaults to `user://accounts.db` and is
  overridable via `PROJECT0_ACCOUNTS_DB_PATH`, but there is no migration path
  yet beyond `SqliteStore`'s existing fail-closed `user_version` check — an
  operational/rollback plan is left to a future persistence-focused slice, as
  already noted in Slice 038/039's own known limitations.

## Related work

[PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-work-index) (Phase 14),
[FEATURE-LIST.md](../FEATURE-LIST.md#f-031-account-authentication-and-session-server)
(F-031),
[FEATURE-LIST.md](../FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository)
(F-030, promoted to Implemented by this slice's boot wiring),
[Slice 038](038-shared-sqlite-persistence-foundation.md) (consumed
`SqliteStore`, F-029), [Slice 039](039-accounts-characters-repository.md)
(consumed `AccountCharacterRepository`/`CharacterRecord`/`AccountHandle`,
F-030), [player-accounts spec](../../.scratch/player-accounts/spec.md),
[handoff-040](../../.scratch/player-accounts/handoff-040-account-auth-session.md).
