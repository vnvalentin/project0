# Slice 073 — Login→game handoff e2e (over real ENet, two server processes)
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Nineteenth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it proves the client login→game cutover **end-to-end over real ENet across two
separate server processes** — the payoff of Slices 068–072.

## User outcome

A real client connects to the standalone login process, authenticates and selects
a Character, obtains a signed assertion, disconnects, connects to the game
process, and the game server establishes its session **purely from the
assertion** — with the login and game servers running as two separate OS
processes that share only the HMAC secret, not a database.

## Scope and non-goals

In scope:
- `scripts/login_handoff_client_harness.gd`: a real client process that drives the
  full handoff through the production seams (connect→register→create/select
  Character→request assertion→disconnect→connect to game→present assertion) and
  writes its observable public-seam state to a JSON file.
- `scripts/test_login_handoff_e2e.gd`: an orchestrator that spawns the login
  server, the game server (two real processes sharing one `PROJECT0_ASSERTION_SECRET`
  but separate accounts DBs), and the client harness, polls the harness state,
  and asserts the game server established the session from the login assertion.

Out of scope (later sub-slices): world entry / loading the selected Character's
data on the game server (the Character record lives only in the login DB — the
cross-DB Character-data handoff is a separate slice); rewiring the login-screen
scenes; dropping the game server's in-process login; the DB split on disk. The
harness stops at `session_established == "ok"`, the achievable cutover today.

## Public seam

- `scripts/login_handoff_client_harness.gd`, `scripts/test_login_handoff_e2e.gd`
  (test-only orchestration over the existing production seams).

## Safety invariant

The two servers share only the HMAC assertion secret (set once by the
orchestrator), never a database — the game server binds the session from the
validated token alone, proving the trust boundary works across real processes.
The harness observes only public seams (`NetworkClient.status`, the relay
signals) a real client exposes; the orchestrator makes all pass/fail decisions
from the state file. Test artifacts (temp DBs, state file, health files) are
cleaned up.

## ADR rationale

No new ADR. This is the runtime proof of the already-accepted login-boundary
decision, using the repo's established multi-process e2e harness pattern
(`scripts/test_multi_peer_replication.gd`).

## BDD / TDD

`scripts/test_login_handoff_e2e.gd` asserts: both servers start and report
healthy; the client connects to the login process and registers; it creates and
selects a Character and receives a non-empty assertion; it disconnects and
connects to the game process; and the game server returns
`session_established == "ok"` for the presented assertion — even though the game
server's DB holds no such account. Prints `ALL PASS` and exits 0 only if every
assertion holds.

## Validation

- Runtime (Linux host): `godot --headless --path . -s scripts/test_login_handoff_e2e.gd`
  printed **`ALL PASS`** — login+game processes start, both report healthy, the
  client registers, creates+selects a Character, and receives an assertion on the
  login process, then reconnects to the game process where
  `session_established == "ok"` (the game DB holds no such account). Both servers
  logged `PROJECT0_ASSERTION_SECRET configured`, confirming the shared secret.
  Note: in a fresh git worktree the project's import cache must be built first
  (`godot --headless --path . --import`) so `class_name` types resolve in the
  spawned server processes; a normal checkout already has `.godot`.
- GUT gate unaffected (the harness is a separate `-s` script, not part of the
  GUT suite): `scripts/run_gut_validation.sh` — 54/54, exit 0.
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
