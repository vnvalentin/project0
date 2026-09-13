# Handoff — Slice 040: Account authentication and session (server)

Filled-in [handoff template](../../docs/templates/claude-code-handoff-template.md)
by Copilot (orchestration/review layer) for implementation by Claude Code CLI.
Governing decision: [player-accounts spec](spec.md) Implementation Slice 3
("Account auth + session (server)") + ticket 04 (authentication & session).
Foundation gate closed. Consumes the now-delivered Slice 039 repository
([F-030](../../docs/FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository),
`server/account_character_repository.gd`) and Slice 038 engine
(`server/sqlite_store.gd`), both committed at `dae748f`.

## User outcome

A connected peer can **register** a new Account or **log in** to an existing one
over the ENet link; the server verifies credentials with **PBKDF2-HMAC-SHA256
off the main thread**, binds an **opaque in-memory session** to the peer on
success, and returns an `AccountHandle` or a **bounded rejection** — all
server-authoritative and fail-closed.

## Scope

- **In scope:**
  1. **`server/password_hasher.gd`** (`class_name PasswordHasher`), server-only:
     PBKDF2-HMAC-SHA256 built on Godot `Crypto` (`generate_random_bytes` for a
     **16-byte CSPRNG salt**, `hmac_digest(HashingContext.HASH_SHA256, …)` for
     the KDF, `constant_time_compare` for verification), **32-byte** derived
     key, iteration count stored with the record (spec example: 100000).
     Expose a **pure synchronous core** —
     `hash_password(password, iterations) -> {salt, hash, iterations}` and
     `verify_password(password, salt, hash, iterations) -> bool` — so it is
     unit-testable; the RPC path runs it **off the main thread**
     (`WorkerThreadPool`) so a slow hash never blocks the server tick.
  2. **`server/session_registry.gd`** (`class_name SessionRegistry`),
     server-only: in-memory `peer_id → { session_token, account_id, username,
     authenticated_at }` (opaque CSPRNG token). `bind(peer_id, account_id,
     username) -> token`, `is_authenticated(peer_id) -> bool`,
     `get_session(peer_id) -> Dictionary`, `clear(peer_id)`. **Never persisted;
     reconnect ⇒ no session ⇒ re-auth.**
  3. **RPC seam** (follow the existing `NetworkClient` pattern —
     `receive_input_intent_on_server` / `receive_authoritative_position`):
     - C→S `@rpc("any_peer","call_remote","reliable")`
       `receive_register_request_on_server(username, password)` and
       `receive_login_request_on_server(username, password)` on
       `client/network_client.gd`, forwarding via
       `multiplayer.get_remote_sender_id()` to the server-side auth logic (a
       `/root` auth-service node or `server_main.gd` dispatch, mirroring how the
       input receiver forwards to `ServerPlayerState_<id>`).
     - S→C `@rpc("authority","call_remote","reliable")`
       `receive_auth_result(outcome, account_id, username)` — `AccountHandle`
       fields on success, a bounded reason `String` on failure.
     - Minimal client `submit_register` / `submit_login` helpers (like
       `submit_input_intent`) for tests/harness — **not** the UI screens.
  4. **Server auth logic** (in `server_main.gd` boot + an auth dispatch/service):
     - **Boot wiring (first runtime consumer):** open a `SqliteStore` at a
       server `user://` path and call
       `AccountCharacterRepository.ensure_schema()`. **Fail closed** (refuse to
       start, like the existing hub-fixture check) if the DB cannot open.
     - **register:** validate inputs (`MALFORMED`), hash off-thread,
       `repo.create_account(username, salt, hash, iterations)`; on OK **bind a
       session** (register auto-authenticates) and return the `AccountHandle`;
       pass through `USERNAME_TAKEN`.
     - **login:** validate; `repo.find_account_by_username`; verify PBKDF2
       (constant-time, off-thread); on match bind a session + return the
       `AccountHandle`, else `BAD_CREDENTIALS`. **Unknown user and wrong
       password both return `BAD_CREDENTIALS`** (no user enumeration).
     - `ALREADY_AUTHENTICATED` if the peer already holds a session.
     - **On peer disconnect:** clear the peer's session.
  5. **Tests (test-first):**
     - `tests/unit/test_password_hasher.gd` — PBKDF2 round-trip (correct
       verifies, wrong fails), determinism (same salt+password+iterations ⇒ same
       hash), distinct salts ⇒ distinct hashes, salt is 16 bytes / key 32 bytes,
       and a **published PBKDF2-HMAC-SHA256 known-answer vector** to prove the
       KDF is correct (security-critical).
     - `tests/integration/test_account_auth_session.gd` — register binds session
       + persists via the repo/DB + returns an `AccountHandle`; duplicate
       username ⇒ `USERNAME_TAKEN`; login correct ⇒ success + session; login
       wrong password ⇒ `BAD_CREDENTIALS`; login unknown user ⇒
       `BAD_CREDENTIALS` (same reason); malformed ⇒ `MALFORMED`; second auth on
       the same peer ⇒ `ALREADY_AUTHENTICATED`; disconnect clears the session;
       the session token is never persisted.
  6. **Delivery records** (see gates below).

- **Out of scope (explicit non-goals):**
  - **Making auth mandatory for world entry** / gating the existing
    spawn-on-connect flow. **The existing connect→(blueprint, spawn, house,
    replication) lifecycle stays UNCHANGED** so the vertical slice remains
    always-playable; the enforcement flip lands with the client screens
    (spec slice 5) or a dedicated later slice. Auth RPCs are **additive**.
  - Character CRUD over the wire (create/select/delete RPC) — spec slice 4.
  - Client login/register **screens** / `identity_gate.tscn` replacement — spec
    slice 5. (Minimal test-only submit helpers are fine; the UI is not.)
  - Character → Player instantiation / `start_for_peer` binding — spec slice 6.
  - Email verification, recovery, OAuth, MFA, CAPTCHA, rate limiting (spec
    out-of-scope).

## Repository context

- Governing ticket: [spec.md](spec.md) (Implementation Slice 3),
  [issue 04](issues/04-authentication-and-session-model.md).
- Primary phase / slice: **Phase 14** / **Slice 040** (reserve in
  [SLICE-REGISTRY.md](../../docs/slices/SLICE-REGISTRY.md)); **new feature
  F-031**.
- Files Claude may create/change: `server/password_hasher.gd`,
  `server/session_registry.gd`, an optional `server/` auth-service node,
  `client/network_client.gd` (additive auth RPCs + submit helpers),
  `server/server_main.gd` (boot DB wiring + auth dispatch + disconnect session
  clear), `tests/unit/test_password_hasher.gd`,
  `tests/integration/test_account_auth_session.gd`,
  `docs/slices/040-account-auth-session.md`, `docs/FEATURE-LIST.md`,
  `docs/PROJECT-TRACKER.md`, `docs/slices/SLICE-REGISTRY.md`.
- Files to preserve: `server/sqlite_store.gd`,
  `server/account_character_repository.gd`, `shared/character_record.gd`,
  `shared/account_handle.gd` (consume, do **not** modify); the existing
  movement/spawn/monster RPCs and connect-lifecycle spawn path in
  `server_main.gd`/`network_client.gd` (extend additively, do not alter
  existing behavior); the concurrent planning dirs `.scratch/client-auto-update/`
  and `.scratch/npcs/`.

## Public seam

The `PasswordHasher` and `SessionRegistry` classes, the `register`/`login`
client→server RPCs and the `auth_result` server→client RPC, and the server auth
dispatch — exercised by GUT unit and integration tests. No UI, no world-entry
change.

## Safety invariants

- **Server-only:** hasher, session registry, DB handle, and repository never
  appear in `shared/` or `client/`; `shared/` holds no secrets. Passwords are
  never logged, never stored in plaintext, and never returned to the client;
  `AccountHandle` (no salt/hash) is the only account data sent back.
- **PBKDF2 correctness:** 16-byte CSPRNG salt, 32-byte key, stored iteration
  count, HMAC-SHA256, constant-time compare, proven by a known-answer vector.
  Hashing runs off the main thread so it cannot stall the tick.
- **No user enumeration:** unknown-user and wrong-password both ⇒
  `BAD_CREDENTIALS`.
- **Sessions:** opaque, in-memory only, cleared on disconnect, never persisted;
  reconnect ⇒ full re-auth.
- **Fail-closed:** malformed/oversized/unsupported-version ⇒ bounded reason; a
  boot DB-open failure refuses to start the server (matches the existing
  hub-fixture fail-closed pattern).
- **Non-breaking:** existing RPCs and the connect-lifecycle spawn path are
  unchanged.
- **Bounded telemetry** (CLAUDE.md "Telemetry And Andon Signals"): auth
  accepted/rejected with reason + peer id, and **no** password/secret material.

## Acceptance scenarios (write the failing tests first)

1. Given a fresh server, when a peer sends `register("alice","pw")`, then an
   account is persisted (PBKDF2, via the repo), a session is bound to the peer,
   and `auth_result` returns an `AccountHandle{account_id, "alice"}`.
2. Given "alice" exists, when another `register("alice", …)` arrives, then
   `USERNAME_TAKEN` and no second row.
3. Given "alice" exists, when `login("alice","pw")` with the correct password,
   then success + a bound session + `AccountHandle`; with a wrong password,
   `BAD_CREDENTIALS`; for an unknown username, `BAD_CREDENTIALS` (identical
   reason).
4. Given an authenticated peer, when it sends a second `register`/`login`, then
   `ALREADY_AUTHENTICATED`.
5. Given an authenticated peer, when it disconnects, then its session is
   cleared (a reconnect must re-authenticate).
6. `PasswordHasher`: a published PBKDF2-HMAC-SHA256 test vector reproduces the
   expected derived key; `verify_password` is true for the right password and
   false for a wrong one; two `hash_password` calls for the same password use
   distinct salts and produce distinct stored hashes.

## Validation

Run from the repository root and report exit codes + counts:

1. `godot --headless --import` then the full GUT suite
   (`godot --headless -s addons/gut/gut_cmdln.gd -gjunit_xml_file=/tmp/gut_040.xml -gdisable_colors -gexit`);
   confirm the two new suites are green.
2. `scripts/run_gut_validation.sh` → **exit 0**;
   `build/validation/validation-summary.json` `"status":"passed"` with
   `scripts_expected == scripts_ran`. Baseline before this slice: **30 scripts /
   233 tests**; expect **+2 scripts**.

## Delivery gates (satisfy BEFORE implementation, verify AFTER)

1. Reserve **Slice 040** and **feature F-031** in
   [SLICE-REGISTRY.md](../../docs/slices/SLICE-REGISTRY.md).
2. Create `docs/slices/040-account-auth-session.md` (SDD, BDD, TDD, no-ADR
   rationale or an ADR, validation, related work) — mirror Slice 038/039.
3. Create the **F-031** feature record in `docs/FEATURE-LIST.md` (In Progress);
   consider promoting **F-030** to `Implemented` since this slice makes the
   repository runtime-active (boot-wired). **Atomically sync all 4 sections of
   `docs/PROJECT-TRACKER.md`**: update the Phase 14 work-index badges + progress
   %, set the Phase 14 **Current slice** to 040, add Slice 040 to the slice
   index, and update the Work queue.
4. **Test-first** (red → green → refactor). Do **not** `git commit`.
5. **Jidoka:** stop on any unexpected failure and report; if `git status` shows
   new concurrent edits to `server_main.gd`/`network_client.gd` at start, stop
   and report rather than clobbering.

## Return report

Report: files changed; exact commands + exit codes; behavior observed (suite
counts, sample accept/reject outcomes, the PBKDF2 KAT result); the threading
approach used; known limitations (auth not yet mandatory; no client UI); and any
scope deviation for Copilot review.
