# Slice 041 — DT-006 remaining-smoke-test GUT migration
GitHub issue: #95

Status: **delivered** (test-tooling/records only; no gameplay, schema, or
network-contract change).

Phase: 1 (residual), 2, 4, 5, 8 (residual), 11 — same phases DT-006 was carried
against. Feature: none new — this closes
[DT-006](../TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut).

## User outcome

Every remaining hand-rolled `scripts/test_*.gd` smoke test now reports through
the standard GUT run (`build/validation/gut.xml`,
`scripts/run_gut_validation.sh`) instead of a separately invoked
`godot --headless -s <script>.gd` check with manual PASS/FAIL parsing. Closing
this migration also surfaced and fixed a latent, previously undetected break:
Slice 030's town collision silently defeated the real-socket melee E2E proof,
because the harness's hard-coded walk and the server's hard-coded dummy
position both now sit inside solid starting-town geometry.

## Scope

**In scope (this slice):**

1. Deleted `scripts/test_sector_blueprint_contract.gd` — an exact duplicate of
   the already-migrated `tests/integration/test_sector_blueprint_contract.gd`
   (Slice 008/DT-006 prior work); no unique coverage lost.
2. Renamed `scripts/test_ollama.gd` to `scripts/probe_ollama.gd` — this script
   makes a live call to a real local Ollama endpoint and has no assertions; it
   is a manual connectivity probe, not a test, so it is reclassified out of the
   `test_*.gd` migration surface rather than wrapped. Updated its one
   in-repo cross-reference in `scripts/sector_blueprint_fixtures.gd`'s comment.
3. Added three GUT wrappers, one per remaining real two/three-process E2E
   harness, following the established `tests/integration/*_e2e.gd` wrapper
   pattern (a single `GutTest` test function that shells out to the unmodified
   harness via `OS.execute`, asserts exit code 0 and an `ALL PASS` marker in
   its output, and honors `PROJECT0_SKIP_E2E` for sandboxes with no loopback
   networking):
   - `tests/integration/test_prediction_reconciliation_e2e.gd` wraps
     `scripts/test_prediction_reconciliation.gd` (Slice 005 evidence).
   - `tests/integration/test_multi_peer_replication_e2e.gd` wraps
     `scripts/test_multi_peer_replication.gd` (Slice 007 evidence).
   - `tests/integration/test_authoritative_melee_strike_socket_e2e.gd` wraps
     `scripts/test_authoritative_melee_strike_e2e.gd` (Slice 012/013 evidence).
   None of the three wrapped harness scripts were modified or renamed
   (DT-006's accepted "Option A": wrap, don't rewrite, the process-spawning
   scripts) — **except** the melee harness's env-var addition below, needed to
   make it pass again after an unrelated, unrecorded regression.
4. **Latent break found and fixed (E2E flat-arena isolation seam).** Root
   cause: `server/server_player_state.gd` has resolved movement through
   `_collision_map.resolve_move()` since Slice 030 (server-side town
   collision), and `server/server_main.gd` injects the real starting-town
   collision map into every connected peer's `ServerPlayerState`
   unconditionally. The melee E2E harness
   (`scripts/test_authoritative_melee_strike_e2e.gd`, unchanged since Slice
   012/013) spawns its first peer at the server's hard-coded
   `START_POSITIONS[0] = (3, 1, 3)` and walks forward+left toward the
   server's hard-coded `TARGET_DUMMY_POSITION = (0, 1, -2)` — both points now
   sit inside the starting-town hub, so town wall/building geometry deflects
   that hard-coded walk and the player never reaches melee range. The
   RPC/socket path itself was never broken (connect+spawn and the
   ActionIntent/ActionResolution RPCs already passed). Fix: added an
   E2E-only, default-off isolation seam —
   `PROJECT0_E2E_DISABLE_TOWN_COLLISION=1` (read via `OS.get_environment` in
   `server/server_main.gd`, following the file's existing
   `PROJECT0_ACCOUNTS_DB_PATH` pattern) skips the one line that calls
   `player_state.set_collision_map(_town_collision)`, so `_collision_map`
   stays `null` and `ServerPlayerState`'s existing null-safe fallback
   (`server_player_state.gd:240`) bypasses `resolve_move()` entirely,
   restoring unconstrained flat-arena movement. The harness sets that
   environment variable via `OS.set_environment` immediately before
   `OS.create_process` spawns the child server, which inherits it. Real
   gameplay, the LAN server path, `START_POSITIONS`, and
   `TARGET_DUMMY_POSITION` are all unchanged; the seam is additive and
   localized to one guarded line in the peer-connect path.
5. This delivery record and the synchronized `TECHNICAL-DEBT-TRACKER.md`,
   `PROJECT-TRACKER.md`, `FEATURE-LIST.md`, `SLICE-REGISTRY.md`, and
   `dashboard/app.py` updates.

**Out of scope (explicit non-goals):**

- No change to `server/server_player_state.gd`'s collision resolution logic,
  `shared/sector_collision_map.gd`, or any other Slice 030 behavior.
- No change to the harness's assertions, thresholds, or purpose — only the one
  env-var call was added, with a comment explaining why.
- No change to the two other wrapped harnesses
  (`test_prediction_reconciliation.gd`, `test_multi_peer_replication.gd`) —
  neither spawns near town geometry, so neither was affected by the Slice 030
  regression.
- No change to the concurrent, uncommitted account-auth work
  (`server/auth_service.gd`, `server/session_registry.gd`,
  `server/password_hasher.gd`, `client/network_client.gd`,
  `server/server_main.gd`'s accounts-boot section,
  `tests/integration/test_account_auth_session.gd`,
  `tests/unit/test_password_hasher.gd`,
  `docs/slices/040-account-auth-session.md`) — preserved as-is.

## BDD scenarios

1. **Duplicate script removed without coverage loss.** Given
   `scripts/test_sector_blueprint_contract.gd` was byte-for-byte superseded by
   `tests/integration/test_sector_blueprint_contract.gd`, deleting the former
   leaves the latter's 7 tests/38 asserts covering the same validator/service
   contract, unchanged.
2. **Probe reclassification.** Given `scripts/test_ollama.gd` makes a live,
   unasserted call to a real Ollama endpoint, renaming it to
   `scripts/probe_ollama.gd` removes it from the `test_*.gd` migration surface
   without deleting its manual-verification utility.
3. **Wrapped harnesses report through the standard GUT shape.** Given the
   three remaining real-process E2E harnesses, each now appears as its own
   `testsuite` in `build/validation/gut.xml` with a pass/fail assertion,
   sourced from the harness's real exit code and `ALL PASS` marker rather than
   a separately parsed console log.
4. **Latent melee regression: red before the fix, green after.** Given the
   town-collision-armed server and the melee harness's original hard-coded
   walk, the wrapped melee test failed (player deflected by town geometry,
   never reaching melee range, so no `CombatEvent.HIT` and thus no `ALL
   PASS`). Given the `PROJECT0_E2E_DISABLE_TOWN_COLLISION=1` seam set by the
   harness before spawning its child server, the same walk now reaches the
   dummy (closest approach ≈1.41 m, under the loop's 1.5 m and the reach
   assertion's 2.0 m thresholds) and the wrapped test passes.
5. **Isolation seam is inert by default.** Given no environment variable is
   set (the real LAN server's launch path), `server/server_main.gd` injects
   the town collision map exactly as before Slice 041 — proven by every other
   suite in the full run (including `test_server_player_state_collision.gd`
   and `test_sector_collision_map.gd`) staying green with no behavior change.

## TDD / validation evidence

All commands run from the repository root on this host (Godot
`4.3.stable.official.77dcf97d8`, x86_64 Linux).

```
scripts/run_gut_validation.sh
```

Exit code: **0**. `build/validation/validation-summary.json`:
`"status": "passed"`, `"scripts_expected": 35`, `"scripts_ran": 35` (DT-007
gate satisfied — no test script silently skipped). Full run totals from
`build/validation/gut.xml`/console summary: **35 scripts, 251 tests, 251
passing, 954 asserts, exit 0.**

Of those 35 scripts, the three GUT wrappers added by this slice all pass,
including the previously-red melee one:

- `tests/integration/test_prediction_reconciliation_e2e.gd` —
  `test_prediction_reconciliation_harness_passes`: **1/1 passed**.
- `tests/integration/test_multi_peer_replication_e2e.gd` —
  `test_multi_peer_replication_harness_passes`: **1/1 passed**.
- `tests/integration/test_authoritative_melee_strike_socket_e2e.gd` —
  `test_authoritative_melee_strike_socket_harness_passes`: **1/1 passed**,
  child process prints `ALL PASS` (all of: server starts and stays up, client
  connects and its Player spawns, the red predicted Player's position comes
  within melee reach of the server's stationary target dummy, the server
  accepts the first melee `ActionIntent` from `IDLE`, and the client receives
  a real authoritative `CombatEvent.HIT` naming `target_dummy_0` over the real
  ENet socket).

Before the `PROJECT0_E2E_DISABLE_TOWN_COLLISION` seam was added, this same
wrapped test failed: the harness's move loop hit its 300-tick cap without
closing to within 1.5 m of the dummy (town geometry deflection), and the
subsequent `distance_to < 2.0` assertion and the melee-intent/hit assertions
downstream of it all failed — confirming the root cause before the fix and its
resolution after.

## No-ADR rationale

No new ADR. This slice performs the already-accepted DT-006 remediation plan
(wrap remaining hand-rolled scripts into GUT one script/small-lot at a time,
delete true duplicates, reclassify non-test probes) and fixes a regression
against the already-accepted Slice 012/030 authority model (server-owned
collision, environment-gated only for hermetic test isolation, never for real
gameplay) — no new architectural decision is introduced.

## Known limitations

- The E2E isolation seam is scoped to town-collision injection only; if a
  future slice adds another server-side spatial constraint independent of
  `_collision_map` (e.g. a second authoritative system with its own geometry
  query), that system is not automatically covered by this seam and would need
  its own consideration.
- The melee harness's move loop and reach thresholds were not changed; they
  were already correct for a flat arena and are simply reachable again now
  that the harness's spawned server runs flat-arena-only.
- `scripts/probe_ollama.gd` still requires a live local Ollama endpoint to
  produce meaningful output; it remains a manual utility, not part of the
  automated gate.

## Related work

[PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-work-index),
[TECHNICAL-DEBT-TRACKER.md#dt-006](../TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut),
[Slice 012](012-authoritative-melee-strike.md),
[Slice 013](013-melee-strike-visual-indicator.md),
[Slice 030](030-server-side-collision.md),
[Slice 005](005-prediction-reconciliation.md),
[Slice 007](007-multi-peer-player-replication.md),
[Slice 008](008-sector-blueprint-contract.md).
