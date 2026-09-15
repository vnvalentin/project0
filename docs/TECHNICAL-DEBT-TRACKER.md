# Project0 Technical Debt Tracker

Status: active
Last reviewed: 2026-09-12
Owner: valentin.vn@gmail.com

## Rule

Every outstanding liability found during project work is recorded here before
work continues. Each item has exactly one classification and debt type, plus an
owner, creation date, benefit or reason, impact, remediation plan, status, and
related work.

Planned work is visible here when useful but is not called Technical Debt unless
it passes all four conditions: intentional decision, understood benefit,
explicit visibility, and known remediation path. Keep this tracker synchronized
with `PROJECT-TRACKER.md`: update its phase work index and status badge whenever
an item's status or scope changes.

Mandatory drift rule: a debt item or feature cannot be left in a stale open or
in-progress state once the public seam has already been implemented and
validated. When a mismatch is discovered, treat it as a process defect, correct
the repository status immediately, and record the root cause and remediation in
the relevant feature or debt history before closing the task.

### Classifications

- `Strategic Technical Debt`: An intentional temporary shortcut with an
  understood benefit, explicit visibility, and a known remediation path.
- `Delinquent Debt`: A discovered liability without an accepted tradeoff. It
  must be remediated or reclassified; it cannot be treated as an accepted
  shortcut.
- `Not Technical Debt`: Visible work that fails the four-condition test, such
  as planned foundational work, intentional scope boundaries, unresolved
  design/integration choices, or governance controls.

### Debt types

Use one type per item: `Quality`, `Security`, `Infrastructure`, `Architecture`,
`Integration`, `Operations`, or `Governance`.

## Lifecycle

1. **Discover:** Add the item immediately. Do not leave it only in a
   conversation, code comment, issue, or private task list.
2. **Track:** Keep it outstanding while any liability remains. Update its scope,
   classification, owner, impact, remediation, status, and links as knowledge
   changes.
3. **Close:** Resolve it only after focused validation. Preserve its ID and
   record the outcome, benefit realized or risk reduced, and validation evidence.
4. **Accept permanently:** Record the decision, conditions reviewed, and why
   remediation is no longer justified. Only permanent acceptance closes an item.

## Outstanding Items

### DT-009: Public `/login` on the enrollment service has no rate-limiting, lockout, or anti-enumeration

- Classification: `Strategic Technical Debt`
- Debt type: `Security`
- Owner: valentin.vn@gmail.com
- Date created: 2026-09-15
- Benefit or reason: [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md)
  adds the first public, unauthenticated credential-verification HTTP surface
  the enrollment service has ever exposed (`POST /login`, delegating to the
  login authority's loopback endpoint). ADR 0004's Consequences section names
  rate-limiting/lockout/anti-enumeration as *required* before this path is
  advertised publicly, but implementing it is a distinct, boundable unit of
  work (likely a token-bucket or fixed-window limiter plus a lockout policy on
  the enrollment service, or a Cloudflare/WAF-level rule) that would have
  enlarged Slice 088's scope beyond its stated login-delegation seam. The
  shortcut is intentional and bounded: `AuthService.login` (server/auth_service.gd)
  already pays a fixed PBKDF2 cost on an unknown username (no timing
  enumeration) and returns the identical `BAD_CREDENTIALS` reason for both
  "unknown user" and "wrong password" (no message enumeration) — so the
  liability is specifically the absence of a cap on *repeated* attempts, not a
  missing baseline.
- Impact: Until remediated, an attacker with network access to the public
  `/login` endpoint can attempt unlimited username/password combinations
  (online brute-force / credential-stuffing), bounded only by whatever
  Cloudflare's WAF in front of the enrollment service does by default (not a
  substitute for application-level lockout, per the slice record). No other
  path is affected: `POST /redeem` (invite-code based) and the ENet login port
  (loopback/LAN-only per its own bind default) are unchanged.
- Remediation plan: A follow-up slice adds request throttling (e.g. a
  fixed-window or token-bucket limiter keyed by source IP and/or username) and
  an account or IP lockout policy to `infra/enrollment/app.py`'s `POST /login`
  route (and/or an OPNsense/Cloudflare WAF rule), with test coverage proving
  the limiter rejects excess attempts with a bounded reason and does not
  regress the no-enumeration property already provided by `AuthService.login`.
  This item closes when that slice lands and its validation evidence is
  linked here, or is explicitly accepted permanently with a recorded
  compensating control (e.g. a documented WAF rule) if a follow-up slice is
  judged unnecessary.
- Status: `Open`
- Phase: 13 (Public game access)
- Links: [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md)
  (Scope/Safety invariants sections), [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md)
  (Consequences section), [PROJECT-TRACKER.md](PROJECT-TRACKER.md#phase-13--public-game-access)

## Resolved Items

### DT-006: Remaining hand-rolled smoke tests not yet migrated to GUT

- Classification: `Strategic Technical Debt`
- Debt type: `Quality`
- Owner: valentin.vn@gmail.com
- Date created: 2026-09-12
- Closure date: 2026-09-13
- Benefit or reason: DT-002 remediated the primary liability (no test
  framework) by installing GUT and migrating Slice 001's smoke test as the
  proof-of-concept. Migrating the remaining hand-rolled
  `push_error`/exit-code scripts (`scripts/test_client_server_connection.gd`,
  `scripts/test_authoritative_movement.gd`,
  `scripts/test_prediction_reconciliation.gd`,
  `scripts/test_multi_peer_replication.gd`, `scripts/test_ollama.gd`) in
  the same change would be a large batch spanning networking/process
  orchestration, contrary to TPSA small-lot delivery; deferring it to
  incremental follow-on slices keeps each migration independently reversible
  and verifiable.
- Impact: Those scripts remained outside the standard GUT report/CI shape
  (still individually invoked `godot --headless -s <script.gd>` checks with
  manual PASS/FAIL parsing) until migrated. No loss of coverage versus before
  DT-002; only the reporting/tooling consistency gap remained.
- Remediation plan: Migrate each remaining `scripts/test_*.gd` smoke test
  into a `tests/unit/` or `tests/integration/` GUT test file, one script at a
  time, verified by `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
  (and a `tests/integration/` dir for the networking/multi-process scripts),
  deleting the superseded `scripts/test_*.gd` file in the same change that
  adds its replacement.
- Status: `Resolved`
- Phase: 1 (residual), 2, 4, 5, 8 (residual removed by this migration), 11 — carried from DT-002 for the scripts
  that were pending migration.
- Links: [Project Tracker](PROJECT-TRACKER.md#implementation-slice-index),
  [Slice 002](slices/002-client-connects-to-server.md),
  [Slice 004](slices/004-authoritative-player-movement.md),
  [Slice 005](slices/005-prediction-reconciliation.md),
  [Slice 007](slices/007-multi-peer-player-replication.md),
  [Slice 041](slices/041-dt-006-remaining-smoke-test-gut-migration.md)
- Rationale: Intentional, visible scope cut (migrate incrementally rather
  than as one large batch) with a known benefit (bounded, reversible slices)
  and a known remediation path (one script migrated per follow-on change).
- Closure outcome: All five originally-named scripts are now in the standard
  GUT report shape. `scripts/test_lan_config.gd` and the Slice 008 contract
  script were already migrated in earlier small lots (see prior change
  history below). [Slice 041](slices/041-dt-006-remaining-smoke-test-gut-migration.md)
  closed the remainder: `scripts/test_sector_blueprint_contract.gd` deleted
  as an exact duplicate of the already-migrated
  `tests/integration/test_sector_blueprint_contract.gd`;
  `scripts/test_ollama.gd` renamed to `scripts/probe_ollama.gd` and
  reclassified as a manual connectivity probe (no assertions, calls a live
  Ollama endpoint) rather than wrapped as a test; and three real-process E2E
  harnesses (`scripts/test_prediction_reconciliation.gd`,
  `scripts/test_multi_peer_replication.gd`,
  `scripts/test_authoritative_melee_strike_e2e.gd`) each got a thin GUT
  wrapper (`tests/integration/test_prediction_reconciliation_e2e.gd`,
  `tests/integration/test_multi_peer_replication_e2e.gd`,
  `tests/integration/test_authoritative_melee_strike_socket_e2e.gd`) that
  shells out to the unmodified harness and asserts its exit code and `ALL
  PASS` marker. Wrapping the melee harness surfaced a latent break: Slice 030's
  town collision silently defeated it, because the harness's hard-coded
  forward+left walk from `START_POSITIONS[0]` and the server's hard-coded
  `TARGET_DUMMY_POSITION` both sit inside the starting-town hub, so town
  geometry deflected the walk before it reached melee range — the RPC/socket
  path itself was always fine. Fixed with an additive, default-off E2E
  isolation seam: `PROJECT0_E2E_DISABLE_TOWN_COLLISION=1` (read in
  `server/server_main.gd`) skips injecting the town collision map into
  connected peers, so `ServerPlayerState`'s existing null-safe fallback
  bypasses `resolve_move()` and restores the original flat-arena path; the
  harness sets this variable for its own spawned child server only. Real
  gameplay and the LAN server path are unaffected.
- Benefit realized: Every `tests/**/test_*.gd` script — including the three
  multi-process E2E harnesses — now reports through one standard GUT
  run/report (`scripts/run_gut_validation.sh`, `build/validation/gut.xml`)
  instead of separately invoked scripts with hand-parsed console output, and a
  previously undetected melee-E2E regression from Slice 030 is now fixed and
  covered going forward.
- Validation evidence: `scripts/run_gut_validation.sh` exit 0;
  `build/validation/validation-summary.json` reports
  `"scripts_expected": 35`, `"scripts_ran": 35` (DT-007 gate satisfied). Full
  run: 35 scripts, 251 tests, 251 passing, 954 asserts. The three new wrapper
  testsuites each pass 1/1, including
  `test_authoritative_melee_strike_socket_harness_passes`, whose wrapped child
  process prints `ALL PASS`. See
  [Slice 041](slices/041-dt-006-remaining-smoke-test-gut-migration.md) for the
  full before/after evidence.
- Change history: On 2026-09-12, migrated `scripts/test_lan_config.gd` to
  `tests/unit/test_lan_config.gd`; focused GUT validation passed 4/4 tests and
  8 assertions, and the full configured unit run passed 7/7 tests and 14
  assertions. Also migrated the Slice 008 contract to
  `tests/integration/test_sector_blueprint_contract.gd`; focused validation
  passed 7/7 tests and 38 assertions. On 2026-09-13, Slice 041 closed the
  remainder as described in the closure outcome above.

### DT-008: Per-tile StaticBody3D geometry did not scale to city size

- Closure date: 2026-09-12
- Closure outcome: Slice 024 replaced the one-`StaticBody3D`-per-tile
  translation with a merged geometry pass in
  `client/sector_geometry_translator.gd`: non-solid ground tiles (floor/corridor)
  are combined into one merged `ArrayMesh` per kind rendered by a single
  body-free `MeshInstance3D` (`Ground_<kind>`), and wall tiles are greedy-merged
  along each row into box colliders under ONE shared `Walls` `StaticBody3D`.
  `shared/sector_geometry_lookup.gd` gained `tile_is_solid(kind)` to classify
  tiles. The starting town (~869 tiles) now renders with a single physics body
  plus per-kind ground meshes plus 13 structure instances, versus ~869 bodies
  before — decoupling rendered town size from the physics body count.
- Benefit realized or risk reduced: The F-026 large-districted-city scale is no
  longer bounded by a per-tile-body budget; floor-heavy sectors produce zero
  ground bodies and a whole town is one wall body regardless of tile count. This
  unblocks the schema-v3 vocabulary + LLM-generated layout slices (024–025) that
  would otherwise multiply the body count.
- Validation evidence: `test_sector_geometry_translation` 8/8 (incl.
  `test_floor_only_sector_produces_zero_physics_bodies` and the wall-run merge
  tests), `test_blueprint_replication` 4/4 (hub renders with ONE merged `Walls`
  body and no `Tile_*` nodes), `test_sector_geometry_lookup` 8/8; full suite
  `scripts/run_gut_validation.sh` 19/19 scripts, 146/146 tests, 558 asserts,
  exit 0. See [Slice 024](slices/024-scalable-geometry-pass.md).
- Residual note: wall colliders merge along horizontal runs only; a further
  vertical/2-D merge to shrink the collision-shape count on vertical wall columns
  is a possible future optimization but is not required — every wall tile already
  shares ONE body. Recorded here rather than as a new open item.
- Links: [Slice 024](slices/024-scalable-geometry-pass.md),
  [Slice 023](slices/023-organic-districted-town.md),
  [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation),
  [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city)

### DT-007: LAN-config tests spawned a real server on the fixed default port 9999 (non-hermetic)

- Closure date: 2026-09-12
- Closure outcome: Added a validated `--server-port=<n>` override to
  `shared/network_config.gd` (`resolve_server_port()` and `_parse_port()`;
  precedence CLI arg -> `PROJECT0_SERVER_PORT` env -> default, with a malformed
  or out-of-range value falling back to the default so a bad override can never
  bind port 0). `server/server_main.gd` now binds and reports that resolved
  port. The two real-server tests in `tests/unit/test_lan_config.gd` reserve an
  OS-assigned ephemeral free port (`PacketPeerUDP.bind(0, ...)`) and pass it to
  the spawned server, so they no longer depend on port 9999. Also hardened
  `scripts/run_gut_validation.sh` to reimport before running, so a stale
  GDScript class cache can no longer silently drop a test script and still
  report green.
- Benefit realized or risk reduced: The GUT suite no longer false-reds when
  port 9999 is occupied (e.g. by a developer-run game server), and a
  cache-skipped test script can no longer masquerade as a passing suite —
  restoring the F-005 automated validation gate to a trustworthy signal.
- Validation evidence: Under collision — with a decoy server holding
  `0.0.0.0:9999` — `test_lan_config` passed 8/8 (exit 0) where it previously
  failed 2 tests. Clean full suite (`scripts/run_gut_validation.sh`, now
  reimporting first): 19/19 scripts, 146/146 tests, 557 asserts, exit 0.

### DT-002: No automated GDScript test framework

- Closure date: 2026-09-12
- Closure outcome: GUT (Godot Unit Test) v9.4.0, the Godot 4.3-compatible
  release, is vendored at `addons/gut/` and enabled as an editor plugin in
  `project.godot`. Slice 001's hand-rolled smoke test
  (`scripts/test_identity_gate_and_movement.gd`) is migrated to
  `tests/unit/test_identity_gate_and_movement.gd` as real GUT test cases and
  the superseded script deleted.
- Benefit realized or risk reduced: A headless-runnable, regression-safe
  GDScript test framework now exists (`godot --headless -s
  addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`), replacing
  `push_error`/exit-code smoke tests with real assertions and a standard
  pass/fail report for the migrated seam.
- Validation evidence: `godot --headless --import` (clean, no errors) then
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
  → `3/3 passed`, exit 0. Remaining hand-rolled scripts were migrated
  incrementally and closed under
  [DT-006](#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut).

### DT-003: No interactive GUI confirmation of Slice 002's visual result

- Closure date: 2026-09-12
- Closure outcome: Interactive GUI visual confirmation performed by the user
  across client/server runs (confirming identity gate, status label updates,
  visual distinction of red local Player, blue NetworkedPlayer, and yellow
  RemotePlayer nodes, and smooth movement rendering under prediction/
  reconciliation).
- Benefit realized or risk reduced: Visual rendering, status labels, camera
  view, and predicted/smoothed movement are verified interactively in a
  windowed GUI run.
- Validation evidence: User-confirmed manual interactive GUI verification
  across Slices 002, 004, 005, and 007.

### DT-004: No physical two-machine (Windows/Linux) LAN run of Slice 003

- Closure date: 2026-09-12
- Closure outcome: Physical two-machine Windows client to Linux server LAN run
  performed and validated by the user across LAN connection (Slice 003),
  authoritative movement (Slice 004), prediction/reconciliation (Slice 005), and
  multi-peer replication (Slice 007).
- Benefit realized or risk reduced: The complete client-server networking
  stack (ENet connection, input intent RPCs, authoritative position updates,
  sequence reconciliation, and peer replication) is verified over an actual
  physical LAN network hop between Windows and Linux.
- Validation evidence: User-confirmed manual two-machine LAN run and
  verification across Slices 003, 004, 005, and 007.

### DT-005: Windows export artifact was unavailable in the original sandbox

- Closure date: 2026-09-12
- Closure outcome: The portable Windows client was exported, launched outside
  the Godot editor/source share, and connected to the Linux server over LAN.
- Benefit realized or risk reduced: The client distribution boundary is now
  proven with a real artifact and real client/server launch.
- Validation evidence: User-confirmed Windows export and LAN connection using
  the packaged client; the client reached `Server: connected: player spawned`.

### DT-001: Foundation records left as unpopulated templates

- Closure date: 2026-09-11
- Closure outcome: `AGENTS.md`, `CONTEXT.md`, `docs/PROJECT-TRACKER.md`,
  `docs/FEATURE-LIST.md`, and `docs/TECHNICAL-DEBT-TRACKER.md` were completed
  with concrete, conservative Project0 details (real commands, boundaries,
  domain terms, Phase 0/1 status, and the first feature/debt entries), and
  cross-checked for agreement.
- Benefit realized or risk reduced: Removes the risk of implementation
  proceeding against placeholder boundaries, undocumented commands, or
  undefined domain terms; closes the foundation gate defined in
  `docs/PROJECT-SETUP-CHECKLIST.md`.
- Validation evidence: `rg "\{\{[^}]+\}\}" AGENTS.md CONTEXT.md
  docs/PROJECT-TRACKER.md docs/FEATURE-LIST.md docs/TECHNICAL-DEBT-TRACKER.md
  docs/slices` returned no matches (see `docs/slices/001-identity-gate-flat-plane-movement.md`
  for the full validation record).