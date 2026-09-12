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

### DT-006: Remaining hand-rolled smoke tests not yet migrated to GUT

- Classification: `Strategic Technical Debt`
- Debt type: `Quality`
- Owner: valentin.vn@gmail.com
- Date created: 2026-09-12
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
- Impact: Those scripts remain outside the standard GUT report/CI shape
  (still individually invoked `godot --headless -s <script.gd>` checks with
  manual PASS/FAIL parsing) until migrated. No loss of coverage versus before
  DT-002; only the reporting/tooling consistency gap remains.
- Remediation plan: Migrate each remaining `scripts/test_*.gd` smoke test
  into a `tests/unit/` or `tests/integration/` GUT test file, one script at a
  time, verified by `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
  (and a `tests/integration/` dir for the networking/multi-process scripts),
  deleting the superseded `scripts/test_*.gd` file in the same change that
  adds its replacement.
- Status: `Open`
- Phase: 1 (residual), 2, 4, 5, 8 (residual removed by this migration), 11 — carried from DT-002 for the scripts
  still pending migration.
- Links: [Project Tracker](PROJECT-TRACKER.md#implementation-slice-index),
  [Slice 002](slices/002-client-connects-to-server.md),
  [Slice 004](slices/004-authoritative-player-movement.md),
  [Slice 005](slices/005-prediction-reconciliation.md),
  [Slice 007](slices/007-multi-peer-player-replication.md)
- Rationale: Intentional, visible scope cut (migrate incrementally rather
  than as one large batch) with a known benefit (bounded, reversible slices)
  and a known remediation path (one script migrated per follow-on change).
- Change history: On 2026-09-12, migrated `scripts/test_lan_config.gd` to
  `tests/unit/test_lan_config.gd`; focused GUT validation passed 4/4 tests and
  8 assertions, and the full configured unit run passed 7/7 tests and 14
  assertions. Also migrated the Slice 008 contract to
  `tests/integration/test_sector_blueprint_contract.gd`; focused validation
  passed 7/7 tests and 38 assertions. The remaining scripts stay in scope for
  later small lots.

## Resolved Items

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
  → `3/3 passed`, exit 0. Remaining hand-rolled scripts are tracked for
  incremental migration under
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