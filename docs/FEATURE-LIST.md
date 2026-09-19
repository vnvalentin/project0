# Project0 Feature List

Status: active
Last reviewed: 2026-09-15
Owner: valentin.vn@gmail.com

## Rule

This record owns product capabilities. Each capability moves through the
delivery lifecycle defined in `DEVELOPMENT-WORKFLOW.md`: `Planned` → `Ready` →
`In Progress` (Active) → `Implemented` (Done). A capability is `Ready` only when
every originating implementation (`task`) issue under its `.scratch/<goal>/` map
is `resolved`; it becomes `Implemented` only after focused validation passes. Do
not describe planned, ready, or unvalidated work as implemented.

Stable identifiers: a feature keeps ONE identifier for life and carries its
stage in the `Status:` field. The legacy `P-`/`IP-`/`F-` prefixes are frozen,
opaque history and no longer signal status — never rename an item when its
status changes. New features take the next unused number as `F-<n>`.

Each feature identifies the user capability, problem solved, current status,
linked phase, implementation slices, public seam, and validation evidence. On
every behavior change, update the feature and append a change record stating
what changed, why, when, related work, and validation evidence.

Keep this list synchronized with `PROJECT-TRACKER.md`: update the phase work
index and its status badge whenever a feature's status or scope changes.

Delivery rule: prefer small, independently observable slices delivered
frequently over large feature batches. Every Matt Pocock, Wayfinder, or other
agent-created slice must name the feature IDs it advances, check for an
existing matching feature before adding one, and update this list and the
Project Tracker together. A slice is not complete without its SDD, BDD, TDD,
telemetry, validation, and review evidence.

Mandatory sync rule: a feature may not remain `In Progress` or `Planned` after
its public seam is live and validated. If a live implementation exists but the
status record is outdated, treat it as a process defect and correct the record in
the same change set. Document the root cause in the change history for the
feature so future drift is easier to detect.

## Planned Features

### F-039: Nakama v1 entry and realtime foundation

- Status: `In Progress`
- Feature: Project0 uses Nakama as the v1 Account/session root and
  client-facing realtime socket entry while Project0 remains authoritative for
  Character semantics, gameplay simulation, and Canon/Sector writes.
- Problem solved: Project0's current bespoke login/session and direct ENet/RPC
  entry path does not provide the Nakama account/session/realtime foundation
  needed for the next playtester-visible access path.
- Phase: 12. Authoritative runtime and action input
- Public seam: The Nakama deployment profile and validation command first, then
  the future Nakama Godot auth/session entry, Project0 Character service keyed
  by Nakama user ID, world-entry ticket contract, Nakama socket gameplay bridge,
  and shared playtest-world routing.
- Implementation slices: [Slice 166](slices/166-nakama-v1-deployment-foundation.md)
  (single-node Nakama/PostgreSQL deployment foundation, private admin posture,
  host-side secrets, backup-before-migration runbook, and static validation),
  [Slice 167](slices/167-nakama-godot-auth-session-entry.md) (Godot Nakama
  auth/session client, account-gate entry path, and in-memory Nakama identity
  state), [Slice 168](slices/168-nakama-character-service.md) (Project0
  Character service Account materialization and session binding keyed by Nakama
  user ID), [Slice 169](slices/169-nakama-world-entry-ticket.md) (server-only
  world-entry ticket issue/consume contract for Nakama sessions).
  Remaining implementation issues are tracked by the parent Goal
  [#354](https://github.com/vnvalentin/project0/issues/354): auth/session
  [#356](https://github.com/vnvalentin/project0/issues/356), Character service
  [#357](https://github.com/vnvalentin/project0/issues/357), world-entry ticket
  [#358](https://github.com/vnvalentin/project0/issues/358), gameplay bridge
  [#359](https://github.com/vnvalentin/project0/issues/359), shared-world
  routing [#360](https://github.com/vnvalentin/project0/issues/360), and smoke
  gate [#361](https://github.com/vnvalentin/project0/issues/361).
- Related work: [Nakama adoption map](https://github.com/vnvalentin/project0/issues/336),
  [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354),
  and [deployment foundation issue #355](https://github.com/vnvalentin/project0/issues/355).
- Change history:
  - Date: 2026-09-19
    What changed: Delivered Slice 166 as the deployment foundation for Nakama
    v1: an opt-in `nakama` compose profile with single-node Nakama plus
    PostgreSQL, host-mounted config/secrets under `/etc/project0`, loopback
    Console posture, backup-before-migration runbook, and executable static
    validation.
    Why: The Nakama Wayfinder map resolved the adoption boundary and v1 scope;
    implementation must begin with a safe operational foundation before auth,
    Character, or realtime bridge code depends on Nakama.
    Related work: [Slice 166](slices/166-nakama-v1-deployment-foundation.md),
    #354, #355.
    Validation evidence: focused static check and Python compile pass locally;
    Linux host validation passed record sync with 0 errors and full GUT with
    811/811 tests passing.
  - Date: 2026-09-19
    What changed: Delivered Slice 167 as the Godot Nakama auth/session entry
    path: a feature-flagged Nakama HTTP client, account-gate login/register
    path, Nakama endpoint/server-key configuration, and in-memory Nakama user,
    auth-token, and refresh-token state in PlayerIdentity.
    Why: After the deployment foundation, the first player-facing Nakama value
    is replacing Project0's bespoke account credential/session entry with
    Nakama user/session identity.
    Related work: [Slice 167](slices/167-nakama-godot-auth-session-entry.md),
    #354, #356.
    Validation evidence: SSH-on-okami validation with native addon artifacts
    overlaid passed record sync with 0 errors and full GUT with 826/826 tests
    and 2558 asserts passing.
  - Date: 2026-09-19
    What changed: Delivered Slice 168 to key the Project0 Character service by
    Nakama user ID: `AccountCharacterRepository.ensure_nakama_account()`
    materializes an idempotent Project0 Account row with `account_id` equal to
    the Nakama user id and non-login PBKDF sentinels, while
    `CharacterService.bind_nakama_account_session()` binds the existing
    session-derived Character CRUD service to that Account key.
    Why: The next v1 milestone after Nakama login is Project0 Character CRUD
    under Nakama Account identity, before world-entry tickets or gameplay bridge
    work.
    Related work: [Slice 168](slices/168-nakama-character-service.md), #354,
    #357.
    Validation evidence: local record sync passed with 0 errors; SSH-on-okami
    full validation passed 831 tests / 2585 asserts.
  - Date: 2026-09-19
    What changed: Delivered Slice 169 for the Project0 world-entry ticket
    contract on top of Nakama-bound Account/Character sessions: a server-only
    `WorldEntryTicketService` issues selected-Character tickets using the
    existing signed assertion contract, consumes them once into game-server
    session state, rejects replay/expiry/wrong-audience failures, and supports
    explicit invalidation.
    Why: The v1 path needs a short-lived, server-validated handoff from Nakama
    identity + selected Character into the authoritative game-server world-entry
    session before socket gameplay routing can be built.
    Related work: [Slice 169](slices/169-nakama-world-entry-ticket.md), #354,
    #358.
    Validation evidence: local record sync passed with 0 errors; SSH-on-okami
    full validation passed 114 scripts / 836 tests / 2617 asserts.

### F-038: Cross-cutting telemetry pipeline (envelope, transport, storage, dashboard)

- Status: `Implemented`
- Feature: Client and server subsystems emit structured, bounded, privacy-safe
  telemetry events (connection lifecycle, combat outcomes, and future
  families) into a dedicated server-owned database, queryable through a new
  read-only `dashboard/` page — for both engineering diagnosis and
  understanding how players use the system.
- Problem solved: Existing telemetry is ad-hoc `print()`/`push_warning()`
  calls with no shared schema, no aggregation/storage, and no query surface,
  so neither engineering diagnosis nor player-behavior analysis has durable,
  structured data to work from.
- Phase: 13. Delivery workflow capabilities
- Public seam: `shared/telemetry_event.gd` (`TelemetryEvent.build`/`validate`),
  `server/telemetry_sink.gd` + `server/telemetry_ingest_service.gd` (writer
  over a dedicated `telemetry.db`), the `receive_client_telemetry_batch_on_server`
  RPC, `server/telemetry_rate_limiter.gd` + `client/telemetry_batch_queue.gd`
  (transport), and the `/telemetry` page in `dashboard/app.py`.
- Implementation slices: [Slice 159](slices/159-telemetry-envelope-validation.md)
  (envelope shape, per-event `schema_version`, size cap, and mechanical
  privacy denylist), [Slice 160](slices/160-telemetry-sink-database.md)
  (dedicated `telemetry.db` sink, schema, retention, and row-ceiling
  enforcement), [Slice 161](slices/161-telemetry-transport-contracts.md)
  (client batching queue + server per-peer rate limiter contracts),
  [Slice 162](slices/162-telemetry-rpc-wiring.md) (live RPC wiring: the send
  path, the RPC itself, boot-wired sink/limiter, and the server-side
  untrusted-input-safe ingest orchestration), [Slice 163](slices/163-connection-lifecycle-telemetry.md)
  (the 6-event connection-lifecycle family live in `server_main.gd`),
  [Slice 164](slices/164-combat-outcome-telemetry.md) (the 6-event
  combat-outcome family live in `server_main.gd`), [Slice 165](slices/165-dashboard-telemetry-page.md)
  (the `/telemetry` dashboard page, closing out the original route).
- Related work: planning charted via the telemetry wayfinder map
  ([#282](https://github.com/vnvalentin/project0/issues/282), decisions
  [#283](https://github.com/vnvalentin/project0/issues/283)-[#290](https://github.com/vnvalentin/project0/issues/290)),
  [Project Tracker](PROJECT-TRACKER.md#phase-work-index).
- Change history:
  - Date: 2026-09-19
    What changed: Delivered Slice 159 — `shared/telemetry_event.gd` provides
    `TelemetryEvent.build()` (fixed envelope: `event_type`, per-event
    `schema_version`, `emitted_at_unix`, `server_tick`, `peer_id`, nullable
    `account_id`/`character_id`/`session_id`, bounded `payload`) and
    `validate()` (structural checks, a ~2KB size cap, and a mechanical
    privacy denylist on payload keys/free-text-length values). An unrecognized
    `schema_version` is never rejected by `validate()` — it is the future
    sink's "store raw" concern, matching `EmbodimentTuning.resolve()`'s
    fail-closed-but-non-blocking precedent elsewhere in this codebase.
    Why: The telemetry map (#282) requires a shared emission contract before
    any transport, storage, or emission-site work can begin.
    Validation evidence: `godot --headless -s addons/gut/gut_cmdln.gd
    -gselect=test_telemetry_event -gdisable_colors -gexit` — 11/11 tests
    passed on Windows. Full suite on the Linux host: `bash
    scripts/run_gut_validation.sh` — 107 scripts, 785/785 tests passing, exit
    0. `bash scripts/check_record_sync.sh` — 0 errors (6 pre-existing
    unrelated warnings for Slices 002/003/009/010/038/041).
  - Date: 2026-09-19
    What changed: Delivered Slice 160 — `server/telemetry_sink.gd` provides
    `TelemetrySink.ensure_schema()` (a wide `events` table plus
    `(event_type, emitted_at_unix)` and `(account_id/peer_id,
    emitted_at_unix)` indexes over a dedicated `telemetry.db`, opened through
    the existing `SqliteStore` engine, distinct from Canon) and `emit()`
    (validates via Slice 159's `TelemetryEvent.validate()` before any write,
    then opportunistically enforces a 30-day retention window and a
    2,000,000-row hard ceiling on every call).
    Why: The telemetry map (#282) decided storage engine, schema, and
    retention shape (#287, #288) before any emission call site can exist.
    Validation evidence: this slice depends on the `SQLite` GDExtension
    (no Windows native library in this checkout), so validation ran only on
    a fresh Linux-host clone with the compiled `godot-sqlite`/`wgnetstack`
    binaries copied in: `bash scripts/run_gut_validation.sh` — 108 scripts,
    791/791 tests passing, exit 0. `bash scripts/check_record_sync.sh` — 0
    errors (6 pre-existing unrelated warnings). Root-cause learning recorded
    in the slice record for two test-fixture bugs (stale hardcoded
    timestamps colliding with the real-time retention sweep) found and fixed
    during validation.
  - Date: 2026-09-19
    What changed: Delivered Slice 161 — `client/telemetry_batch_queue.gd`
    (a ~250ms client-side flush cadence: accumulate, report should_flush(),
    drain via take_batch()) and `server/telemetry_rate_limiter.gd` (a
    per-peer token-bucket rate limiter: try_consume() admits or rejects a
    whole batch atomically, refills over real elapsed time capped at
    capacity, and forget_peer() resets state on disconnect). Both are pure
    contracts with no RPC or scene-tree wiring yet, mirroring the
    version-handshake contract-then-enforcement precedent (Slices
    145/146), and deliberately avoid touching
    `client/network_client.gd`/`server/server_main.gd` since those carry
    unrelated in-progress work.
    Why: The telemetry map (#282) decided the transport shape (#284) before
    any live RPC wiring can exist; keeping the contract and its wiring in
    separate slices follows this repo's established pattern and avoids a
    shared-hot-spot-file conflict with unrelated concurrent work.
    Validation evidence: neither new file depends on the `SQLite`
    GDExtension, so both were fully validated on Windows (6/6 and 8/8
    focused tests). Full suite on the Linux host: `bash
    scripts/run_gut_validation.sh` — 110 scripts, 805/805 tests passing,
    exit 0. `bash scripts/check_record_sync.sh` — 0 errors (6 pre-existing
    unrelated warnings).
  - Date: 2026-09-19
    What changed: Delivered Slice 162 — the live client-to-server telemetry
    RPC. `client/network_client.gd` gains `queue_telemetry_event()`, a
    per-frame flush loop draining `TelemetryBatchQueue`, and the
    `receive_client_telemetry_batch_on_server` RPC (unreliable, any_peer).
    `server/server_main.gd` boot-wires a `TelemetrySink` (best-effort,
    non-fatal on open failure) and a `TelemetryRateLimiter`, and forwards
    accepted batches to a new `server/telemetry_ingest_service.gd`, which
    owns rate limiting, envelope construction, and the write. Every
    trust-sensitive field (peer_id, character_id, emitted_at_unix,
    server_tick) is resolved server-side; a client that stuffs those key
    names into its raw event payload is ignored.
    Why: The transport contracts from Slice 161 needed a live RPC to be
    useful; keeping the orchestration in its own class (rather than inline
    in server_main.gd) keeps the untrusted-input boundary directly testable,
    matching server/character_service.gd's established pattern.
    Validation evidence: depends on the `SQLite` GDExtension (via
    TelemetrySink), so full validation ran on a fresh Linux-host clone with
    compiled native binaries copied in: `bash scripts/run_gut_validation.sh`
    — 111 scripts, 811/811 tests passing, exit 0 (includes the existing e2e
    harnesses booting a real server with this slice's boot wiring live).
    `bash scripts/check_record_sync.sh` — 0 errors (6 pre-existing unrelated
    warnings). `client/network_client.gd` and
    `server/telemetry_ingest_service.gd` additionally parse-checked cleanly
    on Windows.
  - Date: 2026-09-19
    What changed: Delivered Slice 163 — the connection-lifecycle event
    family lives. `server/server_main.gd` gains
    `_emit_connection_telemetry()` and emits `connection.peer_connected`,
    `connection.version_gate_rejected`/`passed`,
    `connection.house_assigned`/`house_unavailable`, and
    `connection.peer_disconnected` at their exact decided points, superseding
    the 6 matching `print()` call sites (touched-code-only, no broader
    retrofit, per #285).
    Why: The taxonomy (#285) and the sink/transport (#287/#284) needed a real
    emission site to prove the pipeline end-to-end; connection lifecycle was
    the first fully-specified family.
    Validation evidence: full suite on the Linux host — 111 scripts,
    811/811 tests passing, exit 0; record-sync 0 errors (6 pre-existing
    unrelated warnings). A manual end-to-end check (real server + real
    client connect/disconnect) confirmed the exact 4 expected rows and
    payload shapes land in `telemetry.db` in order.
  - Date: 2026-09-19
    What changed: Delivered Slice 164 — the combat-outcome event family
    lives. `server/server_main.gd`'s emission helper is renamed
    `_emit_server_telemetry` (generic across families) and now emits
    `combat.melee_swing_started`, `combat.hit`, `combat.monster_defeated`,
    `combat.monster_hit_player`, `combat.player_defeated`, and
    `combat.monster_respawned` at their decided points, superseding the
    matching `print()` sites.
    Why: Combat outcomes were the second fully-specified taxonomy family
    (#286), needed to prove the pipeline works across more than one event
    family.
    Validation evidence: full suite on the Linux host — 111 scripts,
    811/811 tests passing, exit 0; record-sync 0 errors (6 pre-existing
    unrelated warnings). A root-cause-learning fix during implementation
    (caught before any test run) removed a would-be duplicate
    `combat.monster_defeated` emission from `_on_monster_died`, which is a
    pure downstream consequence of the same event `_on_player_state_combat_
    event_emitted` already emits from with richer (attacker-attributed)
    data. A manual dump of the suite run's own `telemetry.db` confirmed
    real `combat.melee_swing_started`/`combat.hit` rows with correct
    peer_id and payload shape.
  - Date: 2026-09-19
    What changed: Delivered Slice 165 — the dashboard `/telemetry` page,
    closing out the telemetry pipeline's original route. `dashboard/app.py`
    gains `telemetry_model()` (read-only query layer: total/per-type counts,
    row-ceiling percentage, a filterable raw-event page) and
    `render_telemetry()`, wired to a new `GET /telemetry` route with
    `event_type`/`account_id`/`peer_id` filters. `event_type` options are
    discovered via `SELECT DISTINCT`, never hardcoded. `deploy/compose.yml`'s
    dashboard service gains a new read-only mount of the game server's data
    directory so the container can reach `telemetry.db`.
    Why: The taxonomy, sink, and emission slices (159-164) needed a
    consumption surface to be useful for either engineering diagnosis or
    player-behavior understanding.
    Validation evidence: `python -m py_compile dashboard/app.py` — no syntax
    errors. Manual end-to-end check: ran the dashboard locally against a real
    sample `telemetry.db` (same schema as `server/telemetry_sink.gd`) and
    fetched both the unfiltered and `event_type`-filtered page over real
    HTTP — correct counters, per-type pills, and exact single-row filter
    result. `bash scripts/check_record_sync.sh` — 0 errors (6 pre-existing
    unrelated warnings).

### F-037: Windows client delivery — version identity, mandatory gate, and signed patching

- Status: `In Progress`
- Feature: A packaged Windows client carries a server-comparable build version,
  is refused before authentication when out of date, and updates itself through
  an offline-signed, integrity-verified, atomically applied, rollback-safe full
  `Project0.pck` replacement served over HTTPS.
- Problem solved: Testers currently update by hand and the server cannot tell
  which client build connected, so a stale client can reach authentication and
  fail in undefined ways — while any self-update path is remote code delivery
  that must never execute unverified bytes.
- Phase: 16. Client delivery experience
- Public seam: The generated in-pack `ClientBuildVersion` contract, the pre-auth
  version-handshake contract enforced by the server, and the launcher/updater's
  signed-manifest verification, atomic swap, and rollback boundary.
- Implementation slices: [Slice 144](slices/144-client-build-version-stamp.md)
  (version identity + export-time stamp),
  [Slice 145](slices/145-version-handshake-contract.md) (pre-auth version
  handshake contract + server-owned required-version resolution),
  [Slice 146](slices/146-version-gate-enforcement.md) (live version-gate
  enforcement: deferred peer admission, client handshake/rejection),
  [Slice 147](slices/147-signed-update-manifest.md) (signed update-manifest
  verifier + patch hash/size verification),
  [Slice 148](slices/148-https-update-staging.md) (HTTPS update staging; verified
  patch staged under `user://`, staging destroyed on any failure),
  [Slice 149](slices/149-updater-transaction.md) (updater transaction: atomic
  pack swap, interrupted-swap recovery, rollback, bounded retries),
  [Slice 150](slices/150-trusted-signing-key.md) (embedded trusted release key +
  one-command release signing),
  [Slice 151](slices/151-client-export-metadata-exclusion.md) (DT-015: exclude
  editor/import metadata from the packaged client),
  [Slice 152](slices/152-enrollment-patch-hosting.md) (public HTTPS `/patches`
  hosting with a read-only release volume),
  [Slice 153](slices/153-launcher-updater-orchestration.md) (persistent launcher
  payload, detached apply helper, startup recovery, and relaunch hook),
  [Slice 154](slices/154-launcher-signed-update-download.md) (native Go signed
  update download and staging integration),
  [Slice 155](slices/155-outdated-client-launcher-handoff.md) (live
  `CLIENT_OUTDATED` handoff from packaged client to launcher update loop).
- Validation: Each slice must add public-seam GUT coverage and full-suite
  telemetry; the update and rollback behavior additionally requires executable
  packaged-client runtime evidence before this feature can become `Implemented`.
  No update or rollback claim is accepted without that runtime evidence.
- Related work: [Windows client delivery contract](../.scratch/client-auto-update/spec.md),
  [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md),
  [#100](https://github.com/vnvalentin/project0/issues/100),
  [#182](https://github.com/vnvalentin/project0/issues/182)
- Change history:
  - Date: 2026-09-18
    What changed: Delivered the eleventh F-037 slice (Slice 155) — the live
    `CLIENT_OUTDATED` handoff. A packaged client with
    `PROJECT0_UPDATE_REJECTION_PATH` writes the bounded server rejection and
    exits code 20; the Go launcher reads/removes it, validates the outcome,
    downloads/stages through Slice 154, and invokes Slice 153's helper with the
    existing tunnel environment.
    Why: The client cannot own the process that replaces its pack; the launcher
    must receive the server-supplied HTTPS pointer without trusting the handoff
    file itself.
    Related work: [Slice 155](slices/155-outdated-client-launcher-handoff.md),
    [Slice 154](slices/154-launcher-signed-update-download.md), #100, #182.
    Validation: Go vet/test passed; full GUT 106 scripts / 774 tests / 774
    passing, 2451 asserts, exit 0; record-sync exit 0. Packaged Windows
    end-to-end evidence remains the final proof.
  - Date: 2026-09-18
    What changed: Delivered the eleventh F-037 slice (Slice 155) — live outdated
    client handoff. A packaged client with `PROJECT0_UPDATE_REJECTION_PATH` now
    writes the bounded server rejection and exits with code 20; the Go launcher
    reads and removes that transient file, validates the `CLIENT_OUTDATED`
    fields, downloads/stages through Slice 154, and invokes Slice 153's helper
    with the existing tunnel environment.
    Why: The client cannot own the process that replaces its pack; the launcher
    must receive the server-supplied HTTPS pointer without trusting the handoff
    file itself.
    Related work: [Slice 155](slices/155-outdated-client-launcher-handoff.md),
    [Slice 154](slices/154-launcher-signed-update-download.md), #100, #182.
    Validation: Go vet clean and `go test ./...` passed; full GUT regression
    required because the client rejection path changed; record-sync exit 0.
    Packaged Windows end-to-end evidence remains the final proof.
  - Date: 2026-09-18
    What changed: Delivered the tenth F-037 slice (Slice 154) — the native Go
    launcher download boundary. `update_download.go` fetches manifest bytes and
    detached signature over HTTPS, verifies the raw bytes with the embedded
    RSA-3072 public key, follows only the signed pack URL, checks size and
    SHA-256, and stages the pack for the Slice 153 helper. Temporary artifacts
    are removed on failure.
    Why: The launcher cannot reuse the GDScript verifier inside the pack it may
    need to replace; it needs a native verifier that remains alive while the
    client artifact is corrupt or being updated.
    Related work: [Slice 154](slices/154-launcher-signed-update-download.md),
    [Slice 153](slices/153-launcher-updater-orchestration.md), #100, #182.
    Validation: `go vet ./...` clean and `go test ./...` passed with real HTTPS
    fixture coverage for valid staging, tampered manifest, plaintext URL,
    up-to-date manifest, and cleanup/refusal paths. Full GUT remains unchanged;
    record-sync exit 0. Live `CLIENT_OUTDATED` wiring remains the next slice.
  - Date: 2026-09-18
    What changed: Delivered the ninth F-037 slice (Slice 153) — launcher updater
    orchestration. The Go launcher now owns a persistent AppData payload instead
    of extracting to a disposable temp directory, runs `RecoverInterrupted` before
    launch, exposes a detached `--project0-update-helper` mode that applies a
    staged pack through Slice 149's transaction, and relaunches the client so its
    next pre-auth version handshake is the readiness check.
    Why: The previous temp extraction made `.bak` and the transaction marker
    impossible to recover across launcher runs; persistent AppData ownership is
    the rollback boundary.
    Related work: [Slice 153](slices/153-launcher-updater-orchestration.md),
    [Slice 149](slices/149-updater-transaction.md), #100, #182.
    Validation: Go vet clean and `go test ./...` passed in
    `native/windows_launcher`; full GUT remains unchanged because no GDScript
    behavior changed. record-sync exit 0. Packaged Windows end-to-end evidence
    remains a follow-on.
  - Date: 2026-09-18
    What changed: Delivered the eighth F-037 slice (Slice 152) — public HTTPS
    patch hosting on the existing FastAPI enrollment service. `/patches` serves
    operator-published `manifest.json`, `manifest.sig`, and versioned
    `Project0.pck` files without authentication, while `deploy/compose.yml`
    mounts the host release directory read-only at `/var/lib/project0/patches`.
    Why: An outdated client must retrieve its patch before authentication; the
    RSA signature, not the URL or TLS alone, remains the trust anchor.
    Related work: [Slice 152](slices/152-enrollment-patch-hosting.md),
    [Slice 150](slices/150-trusted-signing-key.md), #100, #182.
    Validation: enrollment pytest **122/122 passed**; compose config validated
    on okami with exit 0; record-sync exit 0. Local Docker was unavailable,
    so compose validation used the Linux host.
  - Date: 2026-09-18
    What changed: Delivered Slice 151, closing DT-015. The Windows preset already
    excluded the server-only `addons/godot-sqlite/**`, but `all_resources` still
    carried `.godot/extension_list.cfg`, which referenced the intentionally
    absent SQLite GDExtension and produced three false-alarm errors at every
    packaged-client boot. Adding `.godot/**` to the export exclusion removes the
    stale editor declaration without shipping SQLite or changing server exports.
    Why: Update and rollback testing depends on a trustworthy packaged-client
    log; expected extension errors would mask a real startup failure.
    Related work: [Slice 151](slices/151-client-export-metadata-exclusion.md),
    [DT-015](TECHNICAL-DEBT-TRACKER.md#dt-015-the-packaged-windows-client-logs-gdextension-load-errors-at-boot),
    #100.
    Validation: pre-fix fresh export proved `.godot/extension_list.cfg` was in
    the pack save list; fixed fresh export contains no `gdsqlite` /
    `godot-sqlite` references, and a fresh packaged `Project0.exe --headless`
    boot produced zero SQLite log lines. The export also exposed a separate
    Windows ZIP fallback issue (Python unavailable when `zip` was absent),
    retained as a follow-on rather than mixed into DT-015.
  - Date: 2026-09-18
    What changed: Delivered the seventh F-037 slice (Slice 150) — the **trusted
    release key and one-command signing**, closing the hole Slice 147 left open
    deliberately. `shared/client_signing_key.gd` embeds the RSA-3072 public key
    (fingerprint `69db4c67…77a232`) with an `is_configured()` check so a keyless
    build fails closed instead of trusting its download, and
    `scripts/sign_release.sh` produces a signed `manifest.json` + `manifest.sig`
    from a pack. The private key was generated on the operator workstation and
    stays offline — deliberately not on `okami`, which serves the very downloads
    the signature must be able to outlive.
    Why: The verifier from Slice 147 had nothing to verify against; without an
    embedded key the feature could not be trusted at all.
    Related work: [Slice 150](slices/150-trusted-signing-key.md),
    [Slice 147](slices/147-signed-update-manifest.md),
    [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), #100.
    Validation: the **full trust chain executed with the real offline key and the
    real script** — signed on the workstation, verified by the shipped verifier
    and embedded key on the Linux host (`verify_and_parse: ok`,
    `verify_patch_file: ok`, tampered pack → `hash_mismatch`); all four
    `sign_release.sh` refusal paths exit non-zero; full GUT suite 106 scripts /
    774 tests / 774 passing, exit 0; new `test_client_signing_key` 4/4.
    record-sync exit 0.
  - Date: 2026-09-18
    What changed: Delivered the sixth F-037 slice (Slice 149) — the **updater
    transaction**. `native/windows_launcher/updater.go` installs a verified staged
    pack through an ordering where every interruption point is recoverable (copy
    to the install volume → verify digest → mark `swap_started` → rename current to
    `.bak` → rename incoming into place → close the transaction), recovers on
    startup from an interrupted swap, rolls back on a failed readiness check, and
    stops retrying a version after two attempts.
    Why: The updater must not depend on the artifact it replaces — a Godot-hosted
    updater would ship inside `Project0.pck` and could be broken by the very patch
    it is applying, which is exactly the situation recovery exists for. Hence the
    Go launcher, a separate binary that still runs when the pack is corrupt.
    Related work: [Slice 149](slices/149-updater-transaction.md),
    [Slice 148](slices/148-https-update-staging.md), #100, #182.
    Validation: `go vet ./...` clean and `go test ./...` ok in
    `native/windows_launcher`; 11/11 new updater tests pass individually, with
    interruptions simulated against real on-disk states rather than mocks. Full
    GUT suite unchanged (no GDScript touched). record-sync exit 0. **No claim is
    made that end-to-end self-update works**: the process orchestration (launch
    detached, quit, relaunch, readiness check) and the embedded production key
    land next, with packaged-Windows runtime evidence.
  - Date: 2026-09-18
    What changed: Delivered the fifth F-037 slice (Slice 148) — **HTTPS update
    staging**. `client/update_stager.gd` derives the manifest/signature URLs from
    an HTTPS base (a plaintext base cannot even be addressed), fetches the
    manifest, its detached signature, and the patch over bounded HTTPS, and stages
    the patch under `user://` only after it verifies through `UpdateManifest`.
    Every failure path destroys the staging directory, so a refused or interrupted
    download cannot leave a half-written pack for the updater to find.
    Why: The staging directory is the handoff to the updater, so anything left in
    it is something the updater might later treat as ready.
    Related work: [Slice 148](slices/148-https-update-staging.md),
    [Slice 147](slices/147-signed-update-manifest.md), #100.
    Validation: full GUT suite on the Linux host — 105 scripts / 770 tests / 770
    passing, exit 0; new `test_update_stager` 8/8 with real RSA-3072 keys and real
    files, asserting the staging directory is absent after every refusal.
    **Known coverage gap (recorded, not papered over):** the HTTPS transport
    itself is not automatically tested — the suite has no HTTPS fixture — which is
    precisely why packaged-client runtime evidence remains required before F-037
    can become `Implemented`. record-sync exit 0.
  - Date: 2026-09-18
    What changed: Delivered the fourth F-037 slice (Slice 147) — the **signed
    update-manifest verifier**, the trust anchor for remote code delivery.
    `shared/update_manifest.gd` verifies a detached RSA signature over the raw
    manifest bytes **before parsing them**, validates the fields fail-closed, and
    verifies a downloaded patch against the signed size and streamed SHA-256.
    Outcomes are bounded (`unverified`, `malformed`, `unsupported_version`,
    `key_unusable`, `hash_mismatch`, `size_mismatch`, `unreadable`) and the
    manifest is `null` on every non-ok result.
    Why: Verifying a re-serialized copy is a classic signature bypass — two byte
    strings can parse to the same object, so the bytes actually read must be the
    bytes verified. Deliberately not wired to a trusted key yet: a placeholder key
    would look functional while trusting nothing real.
    Related work: [Slice 147](slices/147-signed-update-manifest.md),
    [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), #100.
    Validation: full GUT suite on the Linux host — 104 scripts / 762 tests / 762
    passing, exit 0; new `test_update_manifest` 11/11 using **real RSA-3072
    keypairs generated in-test**, covering genuine tampered-document and
    foreign-key refusals plus equal-length/wrong-content patch rejection.
    record-sync exit 0.
  - Date: 2026-09-18
    What changed: Delivered the third F-037 slice (Slice 146) — **the mandatory
    version gate is now live**. The client sends `VersionHandshake.request()` as
    its first post-connect message; `server_main.gd` defers *all* peer admission
    (town replication, Player spawn, house allocation, and peer
    cross-replication moved into a new `_admit_peer`) until it accepts a
    handshake, refuses a mismatched client with its required version and manifest
    URL before a graceful disconnect, and refuses to start at all when
    `PROJECT0_REQUIRED_CLIENT_VERSION` is unusable.
    Why: A gate that filtered after handing out the world would leak exactly what
    it exists to withhold, so admission itself had to move behind the gate.
    Related work: [Slice 146](slices/146-version-gate-enforcement.md),
    [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), #100.
    Validation: full GUT suite on the Linux host — 103 scripts / 751 tests / 751
    passing, exit 0; the socket E2E harnesses pass unchanged. Runtime evidence in
    both directions: the real multi-peer orchestrator exits 0 with "passed the
    version gate" + ALL PASS against a matching server, and exits 1 with
    "Refusing peer …: CLIENT_OUTDATED" and no Player spawned against a server
    requiring 9.9.9; a malformed requirement exits 1 without ever binding.
    record-sync exit 0.
  - Date: 2026-09-18
    What changed: Delivered the second F-037 slice (Slice 145) — the **pre-auth
    version handshake contract**. `shared/version_handshake.gd`
    (`VersionHandshake`) defines the request a client sends first, resolves the
    server-owned required version from `PROJECT0_REQUIRED_CLIENT_VERSION`
    (defaulting to this build's own version) and the HTTPS-only manifest base URL
    from `PROJECT0_UPDATE_MANIFEST_BASE_URL`, and evaluates one against the other
    into `ACCEPTED` / `CLIENT_OUTDATED` / `MALFORMED` / `SERVER_MISCONFIGURED`
    (plus the reserved `UNSUPPORTED`). Comparison is exact equality, and a
    rejected client is handed the required version and where to patch. Pure and
    fully tested; live enforcement is deliberately the next slice, because the
    connect lifecycle in `server_main.gd` / `network_client.gd` is a declared
    shared hot-spot.
    Why: This is the decision the mandatory gate enforces, and proving it in
    isolation keeps the hot-spot edit small and reviewable.
    Related work: [Slice 145](slices/145-version-handshake-contract.md),
    [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), #100.
    Validation: full GUT suite on the Linux host (working-tree overlay) —
    102 scripts / 747 tests / 747 passing, 2387 asserts, exit 0 (+1 script,
    +13 tests); new `test_version_handshake` 13/13. record-sync exit 0.
  - Date: 2026-09-18
    What changed: Delivered the first F-037 slice (Slice 144) — the client build
    version identity. Added the checked-in, generated `shared/client_build_version.gd`
    (`ClientBuildVersion.current()` + fail-closed `is_valid()` semver validation)
    so a running client can read its own build version from inside the `.pck`,
    and `scripts/stamp_client_build_version.sh`, which `export_windows_client.sh`
    now runs before the Godot export so the packaged pack carries the exact
    released version instead of encoding it only in the ZIP name. The stamp is
    deterministic, idempotent, refuses a malformed version, and restores the
    working tree afterward.
    Why: Every later Phase 16 slice (handshake, manifest, updater) compares or
    binds this version, so it is the root dependency of the whole contract.
    Related work: [Slice 144](slices/144-client-build-version-stamp.md),
    [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), #100, #182.
    Validation: see the slice record for the executed commands and evidence.

### F-036: Phase 14 unified Character and NPC generalization

- Status: `Implemented`
- Feature: Players and NPCs share one server-authoritative Character model with
  a fixed balanced six-node baseline, uncapped organic development, shared
  techniques, equipment, movement, combat, disposition, and spawning contracts.
- Problem solved: NPC behavior and progression must not duplicate the player
  model or bypass the same authority, capability, and consequence rules.
- Phase: 14. NPC generalization and shared Character
- Public seam: Server-owned Character/progression resolution and a bounded
  replicated Character snapshot containing presentation-safe derived state.
- Implementation slices: [Slice 116](slices/116-phase14-character-foundation-handoff.md)
- Follow-on implementation: [Slice 158](slices/158-player-traversal-locomotion.md) adds the baseline Player traversal locomotion modes on the existing Character movement seam.
- Validation: Slice 116 establishes the records-first handoff. Implementation
  must add public-seam GUT coverage, full GUT telemetry, record-sync evidence,
  and authority/hidden-state review before this feature becomes Implemented.
- Related work: [Phase 14 map](../.scratch/npcs/map.md), [ADR 0007](adr/0007-unified-character-and-npc-generalization.md), [#227](https://github.com/vnvalentin/project0/issues/227), [#228](https://github.com/vnvalentin/project0/issues/228), [#229](https://github.com/vnvalentin/project0/issues/229), [#230](https://github.com/vnvalentin/project0/issues/230), [#231](https://github.com/vnvalentin/project0/issues/231), [#232](https://github.com/vnvalentin/project0/issues/232), [#233](https://github.com/vnvalentin/project0/issues/233), [#234](https://github.com/vnvalentin/project0/issues/234), [#235](https://github.com/vnvalentin/project0/issues/235)
- Change history:
  - Date: 2026-09-17
    What changed: Delivered the sixteenth F-036 slice (Slice 131) — the third of
    three live town-NPC slices, which **closes the Phase 14 exit gate**. Wired
    `ServerTownNpcManager` into the running `server_main` (fixed in-town anchors,
    driven each physics frame) and replicated town NPCs to clients
    (spawn/position/despawn RPCs + a cosmetic `client/town_npc.gd`), mirroring the
    monster channel. Town NPCs now actually appear and walk route-consistently in
    the live game. Feature status moves `In Progress` → `Implemented`.
    Why: Make the map's "What Good Looks Like" items 4 and 6 live and visible
    end-to-end, completing the unified-Character seam for Player, Monster, and
    town NPC without duplicating Monster logic.
    Related work: [Slice 131](slices/131-phase14-town-npc-live-replication.md),
    #227, #229, #232.
    Validation: full cumulative Phase 14 tree (main + this slice) on Linux host
    `okami` (consistent temp tree) — 87 scripts / 632 tests / 632 passing, exit 0,
    including the socket E2E harnesses (real `server_main` + `gameplay.tscn`) with
    the live town-NPC manager running; new `test_town_npc_replication` 7/7.
    record-sync exit 0. (Deploy-tree drift required temp-tree validation — see the
    slice's root-cause learning.)
  - Date: 2026-09-17
    What changed: Delivered the fifteenth F-036 slice (Slice 130) — the second of
    three slices bringing live town-NPC behaviour. Added `ServerTownNpcManager`:
    staffs a town's fixed anchors with live `ServerTownNpcState` NPCs and runs
    population on the `SpawnAnchor` contract — anchors start staffed, a lost
    occupant is refilled only after a pressure-scaled delay (nearby players
    shorten it; never an instant clone), sourcing a silent promotion of an
    ambient NPC or a freshly generated, uniquely-identified newcomer, never a
    resurrection.
    Why: Make the map's "What Good Looks Like" item 6 (fixed anchors, population
    pressure, delayed replacement, emergent significance) live, reusing the
    shared SpawnAnchor seam.
    Related work: [Slice 130](slices/130-phase14-town-npc-manager.md), #227, #232.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 500 tests /
    500 passing, exit 0; new `test_server_town_npc_manager` 7/7. Feature stays
    `In Progress`: the `server_main` wiring + client replication (131) remains
    before the exit gate closes.
  - Date: 2026-09-17
    What changed: Delivered the fourteenth F-036 slice (Slice 129) — the first of
    three slices bringing live town-NPC behaviour to close the exit gate. Added
    `ServerTownNpcState`: a server-owned town NPC that is a Character (shared
    `CharacterFoundation`, AI-controlled "villager") living to an
    `ActivityRoutine`, with its world position a PURE function of elapsed ticks
    (travels between activity locations, free off-screen simulation,
    route-consistent arrival), interruptible with position freezing, and a
    presentation-safe snapshot.
    Why: Make the map's "What Good Looks Like" item 4 (NPC activities, off-screen
    simulation, route-consistent arrivals) live, reusing the shared Character +
    ActivityRoutine seams.
    Related work: [Slice 129](slices/129-phase14-town-npc-state.md), #227, #229.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 502 tests /
    502 passing, exit 0; new `test_server_town_npc_state` 9/9. Feature stays
    `In Progress`: the population manager (130) and client replication (131)
    remain before the exit gate closes.
  - Date: 2026-09-17
    What changed: Delivered the thirteenth F-036 slice (Slice 128) — gave the
    monster (`ServerMonsterState`) a server-owned baseline `CharacterFoundation`
    (controller AI, kind "monster") + a presentation-safe `character_snapshot()`,
    so the NPC is literally the same unified Character the Player carries,
    differing only in controller type. No parallel monster stat model; the
    monster's combat behaviour is unchanged.
    Why: The keystone Phase 14 parity — "NPC == Player Character, without
    duplicating Monster logic" — the F-036 exit-gate evidence.
    Related work: [Slice 128](slices/128-phase14-npc-character-foundation.md), #227.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 493 tests /
    493 passing, exit 0; new `test_shared_character_player_npc_parity` 4/4 (real
    Player + monster nodes prove one shared vessel, differing only in controller)
    with the monster combat regression net unchanged (`test_server_monster_state`
    10/10, `test_server_monster_manager` 19/19). Feature stays `In Progress`
    pending the exit-gate assessment.
  - Date: 2026-09-17
    What changed: Delivered the twelfth F-036 slice (Slice 127) — wired the
    unified `CharacterFoundation` into the live server. `ServerPlayerState` now
    creates a baseline humanoid Character at world entry and exposes a
    presentation-safe `character_snapshot()` (normalized graph axes +
    controller/kind only, never raw stat numbers) via a
    `character_snapshot_ready` signal; `server_main` replicates it to the owning
    client on a new peer-scoped RPC mirroring the HP channel; `NetworkClient`
    stores it and a minimal HUD `VesselLabel` renders "Vessel: humanoid
    (balanced)".
    Why: The first replication of unified Character state to the client — the
    presentation-safe boundary the Slice 116 handoff requires, reusable for NPCs.
    Related work: [Slice 127](slices/127-phase14-character-foundation-server.md),
    #227, #230.
    Validation: full GUT suite on Linux host `okami` — 74 scripts / 502 tests /
    502 passing, exit 0; new `test_character_foundation_replication` 4/4 (real
    `ServerPlayerState` node incl. the no-raw-numbers presentation-safe
    invariant) and `test_character_vessel_label` 5/5, with the real-scene tests
    `test_identity_gate_and_movement` 4/4 and `test_melee_strike_visual_indicator`
    9/9 unchanged (the new HUD node + client signal load in `gameplay.tscn`).
    Feature stays `In Progress`: giving NPCs a `CharacterFoundation` and richer
    graph rendering remain.
  - Date: 2026-09-17
    What changed: Delivered the eleventh F-036 slice (Slice 126) — migrated the
    MONSTER's server-owned HP pool from the provisional `MonsterCombatState`
    (Slice 020) to the shared `CombatHealth` contract, seeded at
    `MonsterContracts.MAX_HP`; retired the `MonsterCombatState` class and its
    now-redundant tests. Behaviour-preserving — `ServerMonsterState`'s
    `current_hp`/`is_dead`/`receive_damage` seam and the one-death-per-transition
    + respawn semantics are unchanged. Player and monster HP now share one
    contract.
    Why: Unify both combatants on one health contract, extending the Slice 125
    pattern to the monster.
    Related work: [Slice 126](slices/126-phase14-monster-health-integration.md),
    #227, #231.
    Validation: full GUT suite on Linux host `okami` — 72 scripts / 489 tests /
    489 passing, exit 0; the unchanged regression net passed
    (`test_server_monster_state` 10/10, `test_server_monster_manager` 19/19,
    integration `test_authoritative_melee_strike` 9/9 — real-node runtime
    evidence), and the rewritten `test_monster_contracts` 2/2. Feature stays
    `In Progress`: wiring `CharacterFoundation` server-side remains.
  - Date: 2026-09-17
    What changed: Delivered the tenth F-036 slice (Slice 125) — the FIRST
    integration of a Phase 14 contract into the live server. Migrated the
    Player's server-owned HP pool in `server/server_player_state.gd` from the
    provisional `PlayerVitals` (Slice 094) to the shared `CombatHealth` contract,
    seeded at the shared `PLAYER_MAX_HP`; retired the `PlayerVitals` class and its
    now-redundant tests. Behaviour-preserving — the public seam
    (`current_hp`/`max_hp`/`receive_monster_damage`/`health_changed`) and the
    defeat-transition/respawn semantics are byte-for-byte unchanged.
    Why: Start wiring the validated Phase 14 contracts into the running server,
    beginning with the pool `CombatHealth` was designed to replace.
    Related work: [Slice 125](slices/125-phase14-player-health-integration.md),
    #227, #231.
    Validation: full GUT suite on Linux host `okami` — 72 scripts / 488 tests /
    488 passing, exit 0; the unchanged regression net passed
    (`test_server_player_state_damage` 5/5, integration
    `test_monster_damages_player` 2/2 — real node/signal runtime evidence), and
    the rewritten `test_player_combat_contracts` 2/2. Feature stays `In Progress`:
    monster-HP migration and further contract wiring remain.
  - Date: 2026-09-17
    What changed: Delivered the ninth F-036 slice (Slice 124) — the `SpawnAnchor`
    contract (`shared/spawn_anchor.gd`): fixed-anchor NPC population staffing.
    Deficit + a pressure-scaled replacement DELAY (busy places refill faster;
    never an instant clone), sourcing a silent promotion of an ambient NPC when
    available or a newly generated identity otherwise — never resurrecting the
    same individual. Fail-closed parsing. Completes the Phase 14 shared-contract
    set (Slices 116-124).
    Why: Keep settlements believably staffed under attrition without clones or
    reincarnation — the last Phase 14 combat/world primitive.
    Related work: [Slice 124](slices/124-phase14-spawn-anchor.md), #227, #232.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 508 tests /
    508 passing, exit 0; new `test_spawn_anchor.gd` ran 15/15. Feature stays
    `In Progress`: the shared contracts are complete; wiring them into the
    running server/client is the follow-on integration work.
  - Date: 2026-09-17
    What changed: Delivered the eighth F-036 slice (Slice 123) — the
    `ActivityRoutine` contract (`shared/activity_routine.gd`): activity-driven NPC
    movement where the current activity is a PURE function of elapsed ticks over
    a looping routine (free off-screen simulation, route-consistent arrival with
    no drift), with idle/patrol fallback for an empty routine and an
    interrupt/resume lifecycle that preserves the routine clock. Fail-closed
    parsing.
    Why: Give NPCs believable, cheap schedules that stay correct unobserved — the
    activity/population base the spawning slice builds on.
    Related work: [Slice 123](slices/123-phase14-activity-routine.md), #227, #229.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 509 tests /
    509 passing, exit 0; new `test_activity_routine.gd` ran 16/16. Feature stays
    `In Progress`: the NPC spawning / significance slice remains.
  - Date: 2026-09-17
    What changed: Delivered the seventh F-036 slice (Slice 122) — the
    `StatusEffect` contract (`shared/status_effect.gd`): a deliberate magical or
    impairment effect that is resistible (a resistance at or above the effect's
    potency negates it, deterministically) and removable (cleansed on demand or
    expired by duration). Ordinary damage never produces one — no injury system.
    Fail-closed parsing; pure value + lifecycle.
    Why: Complete the Phase 14 combat primitives — spells/impairments that resolve
    by one shared rule for players and NPCs, guaranteed removable.
    Related work: [Slice 122](slices/122-phase14-status-effect.md), #227, #231.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 506 tests /
    506 passing, exit 0; new `test_status_effect.gd` ran 13/13. Feature stays
    `In Progress`: activity/movement and spawning slices remain.
  - Date: 2026-09-17
    What changed: Delivered the sixth F-036 slice (Slice 121) — the
    `DamageResolution` contract (`shared/damage_resolution.gd`): the pure,
    deterministic seam that COMPOSES weapon effective magnitude, attacker
    attribute, technique reliability, and defender mitigation into one incoming
    damage amount for `CombatHealth.apply_damage`. Attribute scales relative to
    the creation baseline; mitigation is capped so a hit always stings; damage
    floors at zero. Stateless; fail-closed parsing.
    Why: Tie the item, technique, foundation, and health contracts together so a
    strike does the right damage by one shared rule for players and NPCs.
    Related work: [Slice 121](slices/121-phase14-damage-resolution.md), #227,
    #231.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 505 tests /
    505 passing, exit 0; new `test_damage_resolution.gd` ran 12/12 (including an
    end-to-end composition test). Feature stays `In Progress`: status effects,
    movement, and spawning slices remain.
  - Date: 2026-09-17
    What changed: Delivered the fifth F-036 slice (Slice 120) — the
    `CombatHealth` contract (`shared/combat_health.gd`): the shared
    health/defeat/recovery pool for players and NPCs (damage floors at zero and
    never heals; recovery caps at max and never harms; defeat at zero; a 0..1
    presentation fraction). No injury subsystem. Fail-closed parsing;
    pure/deterministic.
    Why: Give players and NPCs one identical health mechanic — the Player's first
    HP pool — before the damage-resolution and status-effect slices.
    Related work: [Slice 120](slices/120-phase14-combat-health.md), #227, #231.
    Validation: full GUT suite on Linux host `okami` — 77 scripts / 549 tests /
    549 passing, exit 0; new `test_combat_health.gd` ran 12/12. Feature stays
    `In Progress`: damage resolution, status effects, movement, and spawning
    slices remain.
  - Date: 2026-09-17
    What changed: Delivered the fourth F-036 slice (Slice 119) — the
    `TechniqueContract` (`shared/technique_contract.gd`): multidimensional
    readiness (a technique needs a COMBINATION of stats, e.g. Jump Slash wants
    STR/DEX/WIS/INT together), per-node shortfalls, proficiency-driven
    reliability, and mastery/teaching gates (teaching requires full mastery).
    Fail-closed parsing; pure/deterministic.
    Why: Give techniques a reproducible readiness/reliability seam composing the
    vessel and item models, before proficiency-state and teaching-flow slices.
    Related work: [Slice 119](slices/119-phase14-technique-contract.md), #227, #230, #234.
    Validation: full GUT suite on Linux host `okami` — 76 scripts / 537 tests /
    537 passing, exit 0; new `test_technique_contract.gd` ran 11/11. Feature
    stays `In Progress`: technique proficiency state, teaching/discovery,
    movement, combat, and spawning slices remain.
  - Date: 2026-09-17
    What changed: Delivered the third F-036 slice (Slice 118) — the
    `ItemContract` (`shared/item_contract.gd`): item metadata (14 slots,
    mundane/magical category, binding), the item/item-class proficiency
    effectiveness curve (giant-sword example: 0%→50%, 50%→100%, 100%→150%; at
    100% class, floor 100% and mastery 200%), the mastery proc, and
    binding-governed tradeability. Fail-closed parsing; pure/deterministic.
    Why: Give equipment a reproducible, tunable effectiveness seam that reshapes
    capability without replacing development, before equip/inventory wiring.
    Related work: [Slice 118](slices/118-phase14-item-equipment.md), #227, #233.
    Validation: full GUT suite on Linux host `okami` — 75 scripts / 526 tests /
    526 passing, exit 0; new `test_item_contract.gd` ran 12/12. Feature stays
    `In Progress`: equip/inventory state, techniques, movement, combat, and
    spawning slices remain.
  - Date: 2026-09-17
    What changed: Delivered the second F-036 slice (Slice 117) — the
    `CharacterAlignment` contract (`shared/character_alignment.gd`): continuous
    morality/chaos axes, deterministic D&D-style label derivation with a
    deceptive `declared_label`, relationship-driven `disposition_toward()`, and
    lawful-under-authority restraint. Fail-closed parsing; pure and
    deterministic (no RNG/clock/IO).
    Why: Give AI Characters a believable, auditable stance toward the player,
    on the shared Character seam, before combat/movement slices consume it.
    Related work: [Slice 117](slices/117-phase14-character-alignment.md), #227, #228.
    Validation: full GUT suite on Linux host `okami` — 74 scripts / 514 tests /
    514 passing, exit 0; new `test_character_alignment.gd` ran 12/12. Feature
    stays `In Progress`: equipment, techniques, movement, combat, and spawning
    slices remain.
  - Date: 2026-09-17
    What changed: Delivered the first F-036 slice (Slice 116) — the shared
    `CharacterFoundation` contract (`shared/character_foundation.gd`): one
    server-authoritative Character for players and NPCs, controller type
    separate from disposition/kind, fixed balanced six-node baseline plus a
    separate additive organic-development layer, pure deterministic effective
    derivation, fail-closed `from_wire_dict`, and a presentation snapshot that
    exposes only normalized graph proportions (no raw numeric stats).
    Why: Establish the unified Player/NPC foundation the remaining Phase 14 and
    Phase 15 subsystems build on, without duplicating player and NPC logic.
    Related work: [Slice 116](slices/116-phase14-character-foundation-handoff.md), #227.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 502 tests /
    502 passing / 1780 asserts, exit 0; new `test_character_foundation.gd` ran
    9/9. Feature stays `In Progress`: equipment, techniques, movement, combat,
    disposition, and spawning slices remain.
  - Date: 2026-09-17
    What changed: Opened F-036 and Slice 116 as the records-first Phase 14
    Character foundation handoff.
    Why: Consolidate the resolved NPC generalization decisions before code
    implementation and preserve one shared Player/NPC authority boundary.
    Related work: #227-#235, ADR 0006, Slice 116.

### P-005: Remote-SSH server workspace

- Status: `Planned`
- Feature: VS Code on Windows can operate the repository, Git state, database configuration, and Claude CLI on the Linux development server through Remote-SSH.
- Problem solved: The visual workstation and the authoritative development/runtime environment need a defined boundary.
- Phase: 13. Delivery workflow capabilities
- Public seam: Remote-SSH workspace configuration and documented server-side command path.
- Validation: A future operations slice must prove repository edits, Git inspection, and bounded command execution occur on the Linux host.

### P-006: Token-efficient asset quarantine

- Status: `Planned`
- Feature: Repository ignore rules quarantine heavy binary assets, including 3D meshes, textures, and music, from normal AI context and repository scans without adding service cost.
- Problem solved: Large binary assets consume model context and obscure the source files needed for reasoning.
- Phase: 13. Delivery workflow capabilities
- Public seam: `.gitignore`, scan configuration, and a documented asset validation command.
- Validation: A future slice must prove source scans exclude quarantined assets while the game/runtime asset path remains explicit and usable.

### P-009: Hardware-accelerated local inference

- Status: `Implemented`
- Feature: Server-side Ollama inference uses the local Tesla P100 and a configured Llama model for generation without external cloud inference costs. Configuration is environment-driven with safe defaults, and every request outcome is classified into bounded, non-sensitive telemetry.
- Problem solved: World generation needs an on-premise inference path with predictable ownership, no cloud token dependency, and observable request outcomes without leaking prompt content.
- Phase: 8. JIT world generation and local inference
- Public seam: `shared/local_llm_client.gd` (`resolve_config()`, `configure_from_env()`, `request_outcome_reported` signal, and bounded `outcome`/`duration_ms` result fields), `PROJECT0_OLLAMA_HOST`/`PROJECT0_OLLAMA_MODEL`/`PROJECT0_OLLAMA_TIMEOUT_SEC` environment configuration, and `tests/integration/test_client_never_contacts_ollama.gd`.
- Implementation slices: [Slice 051](slices/051-p009-hardware-accelerated-local-inference.md)
- Validation: Slice 051 covers configured-model success, HTTP error, malformed envelope, invalid inner JSON, and timeout outcomes against a hermetic fake Ollama harness, plus env-config resolution/precedence and a structural scan proving no `client/` file references Ollama. GUT validation passed 304/304 tests across 43/43 scripts and 1182 assertions, exit 0. Record sync passed with 0 errors. A live probe against the running Ollama instance (`llama3:latest` on the Tesla P100) returned a successful parsed JSON response, confirmed 2026-09-14.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index)
- Change history:
  - Date: 2026-09-14
    What changed: Implemented Slice 051's environment-driven `LocalLLMClient`
    configuration resolver and bounded request-outcome telemetry
    (`success`/`http_error`/`malformed_envelope`/`invalid_json`/`transport_error`/`timeout`),
    with a structural test proving the client process never references Ollama.
    Why: Close the P-009 hardware-accelerated local inference contract with
    observable, non-sensitive request telemetry before boot-wiring JIT
    generation in a later slice.
    Related work: [Slice 051](slices/051-p009-hardware-accelerated-local-inference.md)

### IP-004: Structured sector blueprint translation

- Status: `Implemented`
- Feature: LLM output is validated as strict versioned JSON describing a bounded sector coordinate and floor/wall/corridor tile blueprint before server use.
- Problem solved: Free-form model output cannot safely drive authoritative world state.
- Phase: 8. JIT world generation and local inference
- Public seam: `shared/sector_blueprint_schema.gd`, `server/sector_blueprint_service.gd`, and `tests/integration/test_sector_blueprint_contract.gd`.
- Implementation slices: [Slice 008](slices/008-sector-blueprint-contract.md)
- Validation: Slice 008 covers valid, malformed, incomplete, unsupported-kind, wrong-version, out-of-bounds, HTTP failure, timeout, non-blocking, and correlation outcomes. GUT integration validation passes with 7/7 tests and 38 assertions; geometry and persistence remain future work.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Sector blueprint contract](../.scratch/game-vision/issues/15-sector-blueprint-contract.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 008's bounded version-one blueprint
    validator and asynchronous server-side request service. Added explicit
    rejection for origin/tile coordinates beyond the contract bound, while
    preserving transport, timeout, correlation, and non-blocking behavior.
    Why: Close the structured sector blueprint translation contract before
    any geometry or persistence work.
    Related work: [Slice 008](slices/008-sector-blueprint-contract.md),
    [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut)
    (resolved by [Slice 041](slices/041-dt-006-remaining-smoke-test-gut-migration.md))
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/integration -gexit` passed 7/7 tests, 24 assertions,
    exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`)
    passed 14/14 tests, 38 assertions, exit 0.

### IP-008: Just-in-time sector generation

- Status: `Implemented`
- Feature: The authoritative server detects when a Player enters a new sector and requests an unseen sector blueprint without blocking the multiplayer loop.
- Problem solved: Provisional generation existed, but nothing connected it to authoritative world movement or prevented repeated requests for the same peer/sector.
- Phase: 8. JIT world generation and local inference
- Public seam: `server/sector_boundary_detector.gd`, `server/provisional_sector_generator.gd`, and the Canon lookup boundary.
- Implementation slices: [Slice 009](slices/009-provisional-sector-generation.md), [Slice 046](slices/046-sector-boundary-detection.md), [Slice 047](slices/047-jit-result-canonicalization-replication.md)
- Validation: Slice 046 proves floor-based X/Z sector mapping, per-peer transition detection, Canon suppression, duplicate-request suppression, and live server wiring. Slice 047 closed the remaining async follow-up: valid generation results are canonicalized and only the stored Canon blueprint is reliably replicated to connected peers.
- Change history:
  - Date: 2026-09-14
    What changed: Marked IP-008 Implemented — Slice 047 delivered the async
    canonicalization/replication follow-up that Slice 046 named as remaining,
    closing the boundary→generate→canonicalize→replicate loop.
    Why: The tracker phase-8 index already badged IP-008 done; this syncs the
    feature record to that reality and to the delivered Slice 047 evidence.
    Related work: [Slice 047](slices/047-jit-result-canonicalization-replication.md)
    Validation: Full GUT 282/282 across 39/39 scripts, 1073 assertions, exit 0;
    `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Added the authoritative sector-boundary detector that requests only unseen sectors.
    Why: Close the remaining trigger gap between validated provisional generation and live authoritative movement.
    Related work: [Slice 046](slices/046-sector-boundary-detection.md), [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: Unit GUT passed 184/184 tests across 22 scripts, exit 0; server parse check passed, exit 0; full GUT passed 278/278 tests across 38/38 scripts and 1063 assertions, exit 0.

### P-011: Canonical history archive

- Status: `Implemented`
- Feature: The headless server persists validated sector history in a server-owned SQLite database.
- Problem solved: Generated world content must survive process restarts and be shared consistently by multiplayer sessions.
- Phase: 9. Canon persistence and world mutation
- Public seam: SQLite repository, schema migrations, transaction boundary, and persistence telemetry.
- Validation: Slice 045 proves restart recovery, atomic first-write handling, duplicate-coordinate behavior, server-only database ownership, and boot-time canonicalization; mutation replay remains future work.
- Implementation slices: [Slice 045](slices/045-canon-sector-persistence.md)
- Change history:
  - Date: 2026-09-14
    What changed: Started the first Canon persistence slice on the delivered server-owned SQLite foundation.
    Why: Establish durable sector history before wiring boundary-triggered JIT generation or mutable world events.
    Related work: [Slice 045](slices/045-canon-sector-persistence.md), [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md)
    Validation: Focused integration validation passed 94/94 tests and 375 assertions, exit 0; full GUT passed 268/268 tests across 36/36 scripts, exit 0; server parse check passed, exit 0.

### P-012: One-time blueprint canonicalization

- Status: `Implemented`
- Feature: The first validated blueprint for a world coordinate is stored once and becomes immutable Canon for that coordinate.
- Problem solved: Regenerating the same coordinate could produce contradictory maps across sessions.
- Phase: 9. Canon persistence and world mutation
- Public seam: Coordinate uniqueness constraint, canonicalization transaction, and duplicate-generation outcome telemetry.
- Validation: Slice 045 proves first-write success, same-coordinate idempotency, conflicting regeneration rejection, and no partial Canon replacement.
- Implementation slices: [Slice 045](slices/045-canon-sector-persistence.md)
- Change history:
  - Date: 2026-09-14
    What changed: Started the coordinate-unique canonicalization seam.
    Why: Prevent regenerated provisional blueprints from replacing historical Canon.
    Related work: [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: Focused integration validation passed 94/94 tests and 375 assertions, exit 0; full GUT passed 268/268 tests across 36/36 scripts, exit 0; server parse check passed, exit 0.

### P-013: Dynamic world mutation tracking

- Status: `Implemented`
- Feature: Generated assets and mutable entities receive stable GUIDs, and direct player-driven changes such as looting or defeating a leader persist across sessions.
- Problem solved: Mutable world state must not reset or duplicate when a sector is revisited.
- Phase: 9. Canon persistence and world mutation
- Public seam: GUID assignment, mutation event/state store, replay/load path, and mutation telemetry.
- Validation: Proven across Slices 050/095/096/097/098 - stable SHA-256 entity identity, idempotent optimistic-revision mutation application, fail-closed rejection of forged, stale, unauthorized, and non-existent-target changes, and server-authoritative replay of the effective sector. Full GUT 493/493 across 72/72 scripts and the RPC round-trip e2e passed on the Linux host.
- Implementation slices: [Slice 050](slices/050-canon-mutation-persistence.md), [Slice 095](slices/095-canon-entity-guids.md), [Slice 096](slices/096-canon-mutation-intent-service.md), [Slice 097](slices/097-canon-mutation-rpc-transport.md), [Slice 098](slices/098-canon-sector-mutation-replay.md)
- Change history:
  - Date: 2026-09-15
    What changed: Fifth and final P-013 code slice (Slice 098) - added `shared/canon_sector_resolver.gd`, a pure deterministic replay of a sector's mutation log onto its canonical blueprint (a `destroy_structure` mutation removes the matching structure by derived GUID), and wired `server/server_main.gd` to replicate the effective blueprint at both sector-replication points via `_effective_blueprint_for`, so a loaded or revisited sector reflects durable changes with no client change.
    Why: Durable world mutations must be visible when a sector is (re)loaded; keeping replay server-side preserves authority and keeps the client a dumb renderer.
    Related work: [Slice 098](slices/098-canon-sector-mutation-replay.md), [Slice 097](slices/097-canon-mutation-rpc-transport.md), [Slice 095](slices/095-canon-entity-guids.md), [Slice 050](slices/050-canon-mutation-persistence.md)
    Validation: full `scripts/run_gut_validation.sh` on the Linux host passed 493/493 tests across 72/72 scripts, exit 0 (up from 482/70 - new resolver unit + sector-replay integration scripts); the melee e2e (`scripts/test_authoritative_melee_strike_e2e.gd`) printed ALL PASS, proving the new effective-blueprint replication path still delivers/renders the hub sector; `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings.  - Date: 2026-09-15
    What changed: Fourth P-013 slice (Slice 097) - put the mutation intent on the wire: `client/network_client.gd` gains `submit_canon_mutation_intent` plus the C->S and S->C `@rpc` relays, and `server/server_main.gd` wires a live `CanonMutationRepository`/`CanonMutationService` resolving each intent against the sender peer's authenticated Character id and returning the resolution to that peer only. Also fixed the service to echo `client_seq` on early rejections so a client can correlate responses.
    Why: World mutation needed a real over-the-wire path; the client expresses intent and the server owns the outcome, returned privately to the submitter.
    Related work: [Slice 097](slices/097-canon-mutation-rpc-transport.md), [Slice 096](slices/096-canon-mutation-intent-service.md), [Slice 050](slices/050-canon-mutation-persistence.md)
    Validation: full `scripts/run_gut_validation.sh` on the Linux host passed 482/482 tests across 70/70 scripts, exit 0; `scripts/test_canon_mutation_rpc_e2e.gd` printed ALL PASS (real ENet round-trip: client submits an intent, server resolves, resolution relayed back); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings.  - Date: 2026-09-15
    What changed: Third P-013 slice (Slice 096) - added `shared/canon_mutation_intent.gd` (the pure, bounded client->server mutation intent contract, refusing any server-owned field) and `server/canon_mutation_service.gd` (`resolve_intent` stamps the server-authenticated `actor_player_id`, a deterministic `(actor, client_seq)` `event_id`, and the authoritative `server_tick`, then applies via the Slice 050 repository and maps the outcome to an accepted/rejected resolution).
    Why: World-mutation follows the CLAUDE.md intent/resolution split - the client expresses intent, the server owns identity, actor, clock, and outcome - so a client can neither forge who acted nor replay one action into two mutations.
    Related work: [Slice 096](slices/096-canon-mutation-intent-service.md), [Slice 095](slices/095-canon-entity-guids.md), [Slice 050](slices/050-canon-mutation-persistence.md)
    Validation: full `scripts/run_gut_validation.sh` on the Linux host passed 482/482 tests across 70/70 scripts, exit 0 (up from 462/68); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings. The @rpc transport and headless round-trip e2e are Slice 097.
  - Date: 2026-09-15
    What changed: Second P-013 slice (Slice 095) - added `shared/canon_entity_guid.gd`, a pure deterministic SHA-256 identity for a canonical sector's addressable entities (structures + spawn points), and enforced the CanonMutationEvent "server MUST verify the target exists" rule: `CanonMutationRepository.apply_mutation` now rejects a mutation whose `target_guid` is not a canonical entity GUID (target_not_found) before any write.
    Why: A mutation must address stable, restart-safe identity and cannot be recorded against a forged or non-existent target; Slice 050 deferred both the identity and the existence check.
    Related work: [Slice 095](slices/095-canon-entity-guids.md), [Slice 050](slices/050-canon-mutation-persistence.md), [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: full `scripts/run_gut_validation.sh` on the Linux host passed 462/462 tests across 68/68 scripts, exit 0 (up from 453/67); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings.  - Date: 2026-09-14
    What changed: Started the first P-013 slice — a server-only append-only Canon mutation log (`server/canon_mutation_repository.gd`) on the Slice 045 immutable sectors, keyed by a server-owned `event_id`, with an optimistic per-sector revision derived from the log.
    Why: Player-driven world changes must persist idempotently across restarts and be rejected when stale, forged, or aimed at a non-canon sector, without touching immutable sector Canon.
    Related work: [Slice 050](slices/050-canon-mutation-persistence.md), [Slice 045](slices/045-canon-sector-persistence.md), [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md)
    Validation: Focused integration validation passed with the 11 new `test_canon_mutation_repository` cases (94 → 105 integration tests, all passing); full `scripts/run_gut_validation.sh` passed 293/293 tests across 40/40 scripts, exit 0 (`scripts_expected == scripts_ran`); server parse check passed, exit 0; record sync exit 0.

### P-014: Containerized fixed-tick authoritative server runtime

- Status: `Implemented`
- Feature: The authoritative Godot server runs in an isolated Docker container with a bounded 20–30 Hz simulation tick and server-owned physics/state.
- Problem solved: Multiplayer behavior needs a reproducible Linux runtime boundary and predictable simulation cadence.
- Phase: 12. Authoritative runtime and action input
- Public seam: Server container entrypoint, tick loop, health output, and runtime telemetry.
- Implementation slices: [Slice 055](slices/055-server-fixed-tick-and-health-contract.md) (fixed-tick + health contract seam), [Slice 056](slices/056-game-server-container-image.md) (game-server container image, run beside native), [Slice 057](slices/057-game-server-persistence-boundary.md) (host-persistent data boundary + SQLite backup/restore), [Slice 058](slices/058-login-gateway-seam.md) (in-process login gateway seam), [Slice 059](slices/059-session-assertions.md) (signed session assertion contract, issuer, validator), [Slice 060](slices/060-assertion-session-binding.md) (assertion-backed session establishment in the gateway), [Slice 061](slices/061-operator-status-service.md) (operator control plane: read-only status service), [Slice 062](slices/062-operator-restart-action.md) (operator control plane: job/audit model + service restart action), [Slice 063](slices/063-operator-mint-invite-action.md) (operator control plane: audited mint-invite action), [Slice 064](slices/064-operator-revoke-peer-action.md) (operator control plane: audited revoke-peer action), [Slice 065](slices/065-operator-durable-audit-sink.md) (operator control plane: durable SQLite audit sink), [Slice 066](slices/066-operator-lifecycle-actions.md) (operator control plane: audited start/stop lifecycle actions), [Slice 067](slices/067-server-health-file-healthcheck.md) (runtime health file + container HEALTHCHECK), [Slice 068](slices/068-login-runtime-and-standalone-process.md) (login runtime extraction + standalone login-server process), [Slice 069](slices/069-assertion-handoff-seams.md) (assertion handoff seams: request from login, present to game), [Slice 070](slices/070-deploy-supervise-login-server.md) (deploy + supervise the standalone login server), [Slice 071](slices/071-shared-assertion-secret.md) (shared assertion secret across the game + login units), [Slice 072](slices/072-login-endpoint-config.md) (login-endpoint config: NetworkConfig.resolve_login_port), [Slice 073](slices/073-login-game-handoff-e2e.md) (login→game handoff e2e over real ENet, two server processes), [Slice 074](slices/074-assertion-character-snapshot.md) (signed Character snapshot in the session assertion), [Slice 075](slices/075-cross-db-world-entry.md) (cross-DB world entry: bind Player from the assertion snapshot), [Slice 076](slices/076-game-assertion-only-mode.md) (game server assertion-only mode: refuse account-authority RPCs), [Slice 077](slices/077-client-login-handoff-seam.md) (client login→game handoff seam), [Slice 078](slices/078-wire-gates-to-login-process.md) (wire login-screen gates to the login process, opt-in), [Slice 079](slices/079-optional-dedicated-canon-store.md) (optional dedicated Canon store: opt-in canon/accounts DB split on the game server), [Slice 080](slices/080-canon-migration-on-split-boot.md) (one-time Canon migration into a dedicated store on first split boot), [Slice 081](slices/081-deploy-login-server-compose.md) (deploy the standalone login server via docker-compose, opt-in profile), [Slice 082](slices/082-containerized-login-split-e2e.md) (containerized login-split e2e: compose split overlay + two-container handoff proof), [Slice 083](slices/083-split-launcher-shared-secret.md) (one-command split launcher with shared-secret management), [Slice 084](slices/084-login-split-cutover.md) (login-split cutover: split on by default), [Slice 085](slices/085-remove-game-in-process-login.md) (remove in-process login from the game server: assertion-only graph, no AuthService).
- Validation: Slice 055 delivered the pure `ServerHealth` contract (bounded 20–30 Hz tick, fail-closed versioned health snapshot); authoritative Linux gate 326/326 across 45/45 scripts, exit 0. Slice 056 delivered the OCI image (pinned Godot 4.3 headless, non-root, UDP 9999, baked import cache, graceful SIGTERM) and proved build, boot (`Server listening`, SQLite+Canon ready), healthy port-bound healthcheck, ~0.39s graceful stop, and run-beside-native with the native service untouched. Slice 057 moved durable state to the host boundary `/var/lib/project0` (data survives container replacement — Canon `idempotent` on second boot) and proved consistent SQLite backup/restore. Slice 067 wired the `ServerHealth` contract into a runtime health file (`PROJECT0_HEALTH_FILE`) the server rewrites each ~0.5 s tick stride, and switched the container `HEALTHCHECK` to consume it (fresh + `healthy`); proven on Linux — the file reports `"status":"healthy"`, `healthcheck.sh` passes while running, and a stale or missing file fails closed. Slices 068-085 then delivered the standalone login authority, shared assertions, split deployment, client handoff, Canon/accounts separation, and removal of the in-process game authority. Slices 106-110 completed the container runtime cutover, fixed 30 Hz runtime, registry-driven deployment path, and Linux GDExtension packaging. P-014 remains active only for production mutation-path evidence and the independently releasable login image boundary (DT-012).
- Related work: [container-platform map](../.scratch/container-platform/map.md) and its resolved runtime, login, persistence, operator, migration, and worker decisions.
- Change history:
  - Date: 2026-09-16
    What changed: Added Slice 104's registry-driven all-server deployment.
    `deploy/services.json` declares every deployable service and its health
    contract; `scripts/deploy_all.sh` stages `git archive <commit>`, backs up
    the deploy root, rebuilds the Python venv, restarts units or compose, and
    verifies each declared health check, rolling back on failure. The
    `deploy-servers` job runs it on a self-hosted runner on the host, so no
    deploy credential is stored in GitHub. Registering a new service is one
    registry entry.
    Why: Deployment covered only the two Godot servers and required an operator
    to run PowerShell from one Windows workstation; the enrollment, operator,
    and dashboard services had no deployment path at all.
    Validation evidence: Slice 104 — `--dry-run` on okami resolved all five
    services and evaluated live health, exit 0. The mutating path is NOT yet
    exercised against production and is recorded as a known limitation.
  - Date: 2026-09-16
    What changed: Added Slice 101's opt-in server deployment path to the current
    deployment pipeline. `scripts/deploy_server.ps1` archives the committed
    source, backs up the remote checkout, validates extraction, and supports
    explicit native, Docker candidate, and Docker split modes. Ordinary client
    builds remain client-only.
    Why: Keep server deployment reproducible and auditable without making a
    client package build restart live services implicitly.
    Related work: [Slice 101](slices/101-server-deployment-pipeline.md)
    Validation: PowerShell parser checks passed for both deployment scripts;
    the dirty-worktree guard stopped deployment before SSH; `git diff --check`
    and `scripts/check_record_sync.sh` passed.
  - Date: 2026-09-15
    What changed: Delivered Slice 085 — removed the in-process login authority from the game server. The game process now builds an assertion-only login graph via `LoginRuntime.build_assertion_only_services` — a `SessionRegistry` + `CharacterService` + `LoginGateway` with **no `AuthService`**, so there is no register/login/PBKDF2 code path in the game process and it can never act as an accounts authority. `LoginGateway` now depends on a `SessionRegistry` directly for all session operations, with `AuthService` an optional collaborator (an additive third constructor argument, so the login process and every existing gateway/auth test are unchanged). `server/server_main.gd` uses the assertion-only builder, drops the `PROJECT0_GAME_ASSERTION_ONLY` opt-out and the `AuthService` handle, and clears sessions through the gateway on disconnect. Accounts live solely on the standalone login process (`build_services`, unchanged).
    Why: The 084 cutover made the game server assertion-only by default but still constructed the full account-authority graph behind a runtime opt-out; with nothing deployed and no clients, removing that graph permanently commits the game process to the split and shrinks its trusted surface.
    Related work: [Slice 085](slices/085-remove-game-in-process-login.md), [Slice 084](slices/084-login-split-cutover.md), [Slice 076](slices/076-game-assertion-only-mode.md), [Slice 068](slices/068-login-runtime-and-standalone-process.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0. The additive `LoginGateway` constructor kept every existing gateway/auth test passing; `tests/integration/test_login_runtime.gd` gained a case proving the assertion-only graph builds no `AuthService`, refuses register/Character-CRUD (`account_authority_disabled`), yet establishes a session from a token minted by the full login authority; `tests/integration/test_login_assertion_handoff.gd` now wires its game side via the assertion-only builder. Runtime on Linux — a headless boot of `server/server_main.gd` logged `assertion-only game server (accounts live on the login process)`, and `scripts/test_login_handoff_e2e.gd` printed ALL PASS with the game process building no `AuthService` (world entry as `Handoff Hero`). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 084 — the login split is now the canonical topology by default. `shared/network_config.gd` `client_login_split_enabled()` defaults **on** (the client authenticates on the login process and hands off to the game process; `PROJECT0_CLIENT_LOGIN_SPLIT=0` selects the legacy single-connection flow), and `server/server_main.gd` runs the game server **assertion-only by default** (accounts live only on the login server; `PROJECT0_GAME_ASSERTION_ONLY=0` re-enables the in-process login for a combined single-process run). `tests/unit/test_network_config_client_split.gd` was updated for the new default.
    Why: The split was proven end-to-end (074–082) and had a one-command launcher (083); with nothing deployed and no client configured, flipping the two code defaults is safe and completes the login-boundary cutover. Both flags keep an explicit `=0` escape hatch so combined single-process development is still possible.
    Related work: [Slice 084](slices/084-login-split-cutover.md), [Slice 083](slices/083-split-launcher-shared-secret.md), [Slice 076](slices/076-game-assertion-only-mode.md), [Slice 078](slices/078-wire-gates-to-login-process.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0 (the updated unit test asserts the new default: enabled when unset and for non-`0` values, disabled only for `0`). Runtime on Linux — a headless boot of `server/server_main.gd` with no env logged `assertion-only mode: true`, and with `PROJECT0_GAME_ASSERTION_ONLY=0` logged `assertion-only mode: false`; `scripts/test_login_handoff_e2e.gd` printed ALL PASS with the game server now assertion-only by default (`world_entry` ok, bound Player `Handoff Hero`). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 083 — a one-command launcher for the login-split deployment. `deploy/game-server/run-split.sh` (`up`/`down`) requires-or-generates a shared `PROJECT0_ASSERTION_SECRET` — the piece a bare `docker compose up` cannot manage safely (if the two processes do not share a non-empty secret they each use an ephemeral per-boot key and the handoff silently fails) — then brings up the base compose plus the split overlay under the `login-split` profile and waits for both containers to report healthy. It deliberately changes no code env-var default (`PROJECT0_CLIENT_LOGIN_SPLIT`, `PROJECT0_GAME_ASSERTION_ONLY` stay opt-in), so single-process source-run development and the Windows tester guide keep working; a blanket default flip would break those and is intentionally not done.
    Why: The split was deployable and container-proven, but running it correctly hinged on shared-secret management the operator had to do by hand; this makes the safe, reversible cutover a single command.
    Related work: [Slice 083](slices/083-split-launcher-shared-secret.md), [Slice 082](slices/082-containerized-login-split-e2e.md), [Slice 081](slices/081-deploy-login-server-compose.md)
    Validation: On Linux — `bash -n` clean and the script is executable; `run-split.sh up` (data dirs at temp paths) generated an ephemeral shared secret and brought both containers to Docker health `healthy` (exit 0); `scripts/login_handoff_client_harness.gd` against the published ports (login 19998, game 19999) reported `session_established: ok` and `world_entry: ok` with `world_character_name: "Handoff Hero"`; `run-split.sh down` removed the topology cleanly. `scripts/run_gut_validation.sh` — passed, 58/58 scripts, exit 0 (unaffected). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 082 — proved the login split end-to-end in containers. `deploy/game-server/docker-compose.split.yml` is a small overlay that sets `PROJECT0_GAME_ASSERTION_ONLY=1` on the game server, so `docker compose -f docker-compose.yml -f docker-compose.split.yml --profile login-split up` runs the split topology: an accounts-authority login container and an accounts-disabled game container, both sharing `PROJECT0_ASSERTION_SECRET` from the base file. The default `docker compose up` is unchanged.
    Why: The login split was proven only at the process level and the login server was compose-deployable, but nothing had exercised the full split in the target container runtime; this closes that gap and gives operators a single documented "run the split" command.
    Related work: [Slice 082](slices/082-containerized-login-split-e2e.md), [Slice 081](slices/081-deploy-login-server-compose.md), [Slice 077](slices/077-client-login-handoff-seam.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `docker compose -f docker-compose.yml -f docker-compose.split.yml --profile login-split config` on Linux renders the game server with `PROJECT0_GAME_ASSERTION_ONLY: "1"`, both services with the shared secret, and the login-server present. Container e2e on Linux — both containers came up healthy (~10 s) with a shared `openssl rand -hex 32` secret (game logged `assertion-only mode: true`), and `scripts/login_handoff_client_harness.gd` run from the host against the published ports (login 19998, game 19999) reported `session_established: ok` and `world_entry: ok` with `world_character_name: "Handoff Hero"` — register/select on the login container, world entry on the assertion-only game container. `scripts/run_gut_validation.sh` — passed, 58/58 scripts, exit 0 (unaffected). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 081 — the standalone login authority is now deployable in the container topology. `deploy/game-server/docker-compose.yml` gained a `login-server` service gated behind the `login-split` compose profile that reuses the game-server image and overrides the entrypoint to run `server/login_server_main.gd` on its own UDP port (host `19998`→`9998`), accounts DB (`login_accounts.db`), and health file (`/data/login_health.json`); both services carry a `PROJECT0_ASSERTION_SECRET` passthrough (empty by default) so a split deployment can share one secret. The default `docker compose up` still starts only the game server with its ephemeral in-process key.
    Why: The login split had a systemd unit (Slice 070) but no container deployment path; this lets an operator run both processes with `docker compose --profile login-split up` without changing the default single-service topology or any behavior default.
    Related work: [Slice 081](slices/081-deploy-login-server-compose.md), [Slice 070](slices/070-deploy-supervise-login-server.md), [Slice 068](slices/068-login-runtime-and-standalone-process.md)
    Validation: `docker compose config --services` on Linux — the default lists only `game-server`; `--profile login-split` additionally lists `login-server` (rendered with the login entrypoint, port `19998→9998`, `login_accounts.db`, `/data/login_health.json`, empty-default shared secret). Container runtime on Linux — built the candidate image and started the login container via `docker compose --profile login-split up -d login-server`; it reached Docker health `healthy` within ~10 s (`Login server listening on 0.0.0.0:9998`, health file `"status":"healthy"`), then torn down cleanly. `scripts/run_gut_validation.sh` — passed, 58/58 scripts, exit 0 (unaffected). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 080 — the opt-in canon/accounts DB split (Slice 079) is now safe for existing combined deployments. `server/canon_repository.gd` gained `list_all_records()` (verbatim rows, oldest-first) and `restore_record()` (insert preserving the original `created_at`, validating the blueprint, idempotent on identical, conflict on differing). `server/server_main.gd`, on the first boot with a dedicated (empty) Canon store, copies all Canon out of the shared accounts store before canonicalizing the town. Source rows are never deleted; a re-boot finds the dedicated store non-empty and skips; unset (shared handle) never migrates.
    Why: Slice 079 isolated Canon into its own file but a previously-combined `accounts.db` would have started the new file empty and stranded its world; this migrates it faithfully (preserving the immutable record's `created_at`) with no data loss and no destructive step.
    Related work: [Slice 080](slices/080-canon-migration-on-split-boot.md), [Slice 079](slices/079-optional-dedicated-canon-store.md), [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0 (adds migration cases to `tests/integration/test_canon_store_split.gd`: created_at preserved + source intact, idempotent restore, conflict refused). Runtime on Linux (three boots) — a shared boot seeded a combined `mig_acc.db`; a split boot into a fresh `mig_canon.db` logged `Migrated 1 Canon sector(s)` then `Starting town Canon ready: idempotent`; a second split boot logged no migration and stayed idempotent. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 079 — the game server can now give Canon its own SQLite file. `server/server_main.gd` opens a dedicated Canon `SqliteStore` at `PROJECT0_CANON_DB_PATH` (fail-closed if it cannot open) and backs `CanonRepository` with it; when the variable is unset it keeps the Slice 045 behavior where Canon shares the accounts handle. This isolates the authoritative world record from the accounts database for a split deployment (the login server already owns `login_accounts.db`) with no migration and no data movement — existing combined deployments are untouched.
    Why: A clean split deployment wants the game server to own only Canon and never touch the accounts file; making it opt-in via an env var completes the on-disk separation without risking any existing world data.
    Related work: [Slice 079](slices/079-optional-dedicated-canon-store.md), [Slice 045](slices/045-canon-sector-persistence.md), [container-platform map](../.scratch/container-platform/map.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0 (adds `tests/integration/test_canon_store_split.gd`, which proves Canon lands only in the canon store and accounts only in the accounts store, while the shared default colocates both). Runtime on Linux — `server/server_main.gd` booted headless with `PROJECT0_CANON_DB_PATH=split_canon.db` logged `Starting town Canon ready: ok (canon db: split_canon.db)` and created both `split_acc.db` and `split_canon.db`; unset it logged `(canon db: shared:shared_acc.db)`. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 078 — wired the real login-screen scenes to the login process behind an opt-in flag. `shared/network_config.gd` gained `client_login_split_enabled()` (`PROJECT0_CLIENT_LOGIN_SPLIT=1`, default off). When enabled, `client/account_gate.gd` opens the auth connection to the login endpoint (`resolve_login_port`) instead of the game port, and `client/character_gate.gd` — on a successful Character select — calls `NetworkClient.perform_login_to_game_handoff(host, game_port)` and reports handoff failures, while success continues to flow through the existing `world_entry_received` transition into gameplay. Default (flag off) preserves the current single-connection flow unchanged.
    Why: This completes the client side of the login-boundary decision: the actual UI now performs the login→game cutover using the seam proven in Slice 077, gated so nothing changes until a split deployment turns it on.
    Related work: [Slice 078](slices/078-wire-gates-to-login-process.md), [Slice 077](slices/077-client-login-handoff-seam.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 57/57 scripts, exit 0 (adds `tests/unit/test_network_config_client_split.gd`). `scripts/run_client_ui_smoke.gd` on Linux — `client-ui-summary.json` status `passed` (account/character/gameplay scenes load with all required controls). The cutover mechanism the gates call is already proven end-to-end by Slice 077. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 077 — moved the login→game handoff out of the test harness into a production client seam. `NetworkClient.perform_login_to_game_handoff(game_host, game_port)` is a poll-based, bounded coroutine that (from a login-connected session with a selected Character) requests a signed assertion, hands off to the game process (disconnect → connect → present assertion), and enters the world, emitting `login_to_game_handoff_finished(outcome, character)`. The e2e harness now drives Phase 2 through this seam.
    Why: The login-screen scenes need one reusable, tested operation to perform the cutover; factoring the proven harness sequence into `NetworkClient` gives the UI code to call (wired in a follow-up) and validates it over real ENet.
    Related work: [Slice 077](slices/077-client-login-handoff-seam.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 56/56 scripts, exit 0 (the seam is client code exercised by the e2e script, not the GUT gate). Runtime on Linux — `scripts/test_login_handoff_e2e.gd` prints `ALL PASS` including `world_entry == ok` bound as `Handoff Hero`, now via the production seam. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 076 — an opt-in assertion-only mode for the game server. `LoginGateway` gained an `account_authority_enabled` flag; when disabled it refuses `register`/`login`/Character-CRUD with a bounded `REASON_ACCOUNT_AUTHORITY_DISABLED`, while the assertion path (establish session + snapshot world entry) stays available. `LoginRuntime.build_services` flows the flag; `server_main` disables account authority when `PROJECT0_GAME_ASSERTION_ONLY=1` (off by default so the pre-cutover client whose login screen still authenticates on the game server keeps working).
    Why: The login-boundary decision makes accounts a login-service authority; this adds the enforceable switch so a split deployment stops the game server acting as an accounts authority, without breaking the pre-cutover client.
    Related work: [Slice 076](slices/076-game-assertion-only-mode.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 56/56 scripts, exit 0 (+1 new `test_login_gateway_assertion_only.gd`: register/login/CRUD refused, assertion establish + snapshot world entry still succeed). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 075 — completed the cross-DB Character-data handoff so world entry works cross-process. `SessionRegistry` stores a selected-Character snapshot; `establish_session_from_assertion` populates it from the signed claims; `issue_character_assertion` includes the login DB's `display_name`/`cosmetic`; `CharacterService.get_selected_character` returns a snapshot-backed record when present (falling back to the DB for the in-process path). A client that logged in on the separate login process now enters the world as its selected Character on the game process, which never read the accounts DB.
    Why: The game server needs the selected Character's presentation data to bind a Player at world entry; the signed snapshot (Slice 074) supplies it without a shared DB or a game→login call.
    Related work: [Slice 075](slices/075-cross-db-world-entry.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 55/55 scripts, exit 0 (the handoff integration test gains a case proving the game side resolves the selected Character from the snapshot across two DBs). Runtime on Linux — `scripts/test_login_handoff_e2e.gd` prints `ALL PASS` including `world_entry == ok` and the bound Player named `Handoff Hero` across the two real processes. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Delivered Slice 074 — the first sub-slice of the cross-DB Character-data handoff. `SessionAssertion` now carries an additive, bounded, backward-compatible Character snapshot (`cnm` display_name + `cos` cosmetic) signed alongside the identity claims; older snapshot-less tokens still parse (empty defaults). `AssertionIssuer.issue` gained optional `character_name`/`character_cosmetic` params; the validator returns the snapshot in its claims unchanged.
    Why: The game server needs the selected Character's presentation data to bind a Player at world entry, but its DB holds no such record after the assertion handoff — a signed snapshot lets it trust the data without a DB lookup or a game→login call.
    Related work: [Slice 074](slices/074-assertion-character-snapshot.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 55/55 scripts, exit 0 (+1 new `test_session_assertion_snapshot.gd`: snapshot round-trip, empty account-only snapshot, oversized name/cosmetic rejected, tampered snapshot fails signature, older snapshot-less payload parses). Note: cosmetic travels as JSON so numeric values return as floats. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 073 — the login→game handoff proven end-to-end over real ENet across TWO server processes. A multi-process e2e harness (`scripts/test_login_handoff_e2e.gd` + `scripts/login_handoff_client_harness.gd`) spawns the login server and the game server (sharing one `PROJECT0_ASSERTION_SECRET` but separate accounts DBs) and a real client that authenticates on the login process, obtains a signed assertion, disconnects, connects to the game process, and presents it — the game server establishes the session from the assertion alone (no shared DB).
    Why: This is the runtime payoff of the login split (Slices 068–072): the game server trusts a login-minted assertion across real processes.
    Related work: [Slice 073](slices/073-login-game-handoff-e2e.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: Runtime on Linux — `godot --headless --path . -s scripts/test_login_handoff_e2e.gd` prints `ALL PASS` (login+game start, both healthy, client registers/selects Character/receives assertion on login, reconnects to game, `session_established == "ok"`). GUT gate unaffected (the harness is a separate `-s` script, not part of the GUT suite): `scripts/run_gut_validation.sh` 54/54 exit 0. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 072 — the login-endpoint config foundation for the client cutover. Added `NetworkConfig.LOGIN_PORT` (default 9998) and `resolve_login_port()` (`--login-port` CLI, then `PROJECT0_LOGIN_PORT`, then default, reusing the bounded `_parse_port`), and unified `login_server_main.gd` on it (dropping its local default/resolver duplicate) so the client and login server never disagree on the port.
    Why: The client cutover needs one shared resolver for where the login process listens; the multi-process handoff e2e harness (Slice 073) builds on it.
    Related work: [Slice 072](slices/072-login-endpoint-config.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 54/54 scripts, exit 0 (+1 new `test_network_config_login_port.gd`). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 071 — the shared-assertion-secret prerequisite for the client cutover. Both systemd units now load a shared `EnvironmentFile=-/etc/project0/assertion.env` (template `scripts/assertion.env.example`), and `LoginRuntime.resolve_assertion_secret` reports its source (`configured` vs `ephemeral`) via a pure, unit-tested `resolve_assertion_secret_details` helper — so a missing shared secret is observable at boot rather than a silent handoff failure. The secret value is never logged.
    Why: The login process's issuer and the game process's validator must share one HMAC secret, or the game server silently rejects every login assertion once the client presents them (Slice 072).
    Related work: [Slice 071](slices/071-shared-assertion-secret.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 53/53 scripts, exit 0 (+1 new `test_assertion_secret_resolution.gd`). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 070 — made the standalone login server operable. Added `scripts/project0-login.service` (a systemd unit running `login_server_main.gd` with its own accounts DB, dedicated port, and health file) and registered `login-server` → `(systemd, project0-login)` in the operator control-plane allowlist so status/restart/start/stop reach it.
    Why: The runtime-boundary and operator decisions require the login process to be a supervised, operator-managed service like the game server and enrollment.
    Related work: [Slice 070](slices/070-deploy-supervise-login-server.md), [runtime-boundary decision](../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests` on Linux — 63 passed (+1 new allowlist test); the existing status/restart/start/stop suite covers the new service by construction. `scripts/check_record_sync.sh` exit 0; GUT unaffected (no `.gd` change).
  - Date: 2026-09-14
    What changed: Delivered Slice 069 — the assertion-handoff RPC seams (`client/network_client.gd`). `submit_request_assertion` asks the login process to mint a selected-Character (or account) assertion using the server's authoritative clock and a bounded TTL; `submit_present_assertion` presents it to the game process, which establishes the peer's session purely from the validated token (fail-closed). Relayed via `assertion_result_received` / `session_established_received`.
    Why: The login-boundary decision carries account-only then selected-Character signed assertions between the login and game processes; this exposes the Slice 059/060 issue/validate/establish methods over the existing RPC transport.
    Related work: [Slice 069](slices/069-assertion-handoff-seams.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 52/52 scripts, exit 0 (+1 new `test_login_assertion_handoff.gd`: two LoginRuntimes on different DBs sharing one secret — the game side establishes a session from the login side's assertion without holding the account, and rejects a wrong-secret token). `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 068 — the first out-of-process login sub-slice. Extracted the login-authority wiring into a shared `server/login_runtime.gd` (`LoginRuntime`) used by the game server (behavior-preserving refactor) and by a new standalone `server/login_server_main.gd` process that boots only the login authority against its own accounts DB on a dedicated port, hosting the existing register/login/Character RPC surface with a health file. The game server keeps its in-process login (the preserved in-process adapter).
    Why: The login-boundary decision requires a durable Account/Character authority that can run as its own process behind a stable seam — the keystone for a separate login service and future microservices.
    Related work: [Slice 068](slices/068-login-runtime-and-standalone-process.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 51/51 scripts, exit 0 (+1 new `test_login_runtime.gd` proving the full authority + cross-secret assertion trust flow; the unchanged suite proves the `server_main` refactor is behavior-preserving). Runtime on Linux: `login_server_main.gd` boots, opens its own accounts DB (`schema ensured`), prints `Login server listening`, and publishes a `healthy` health file. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 067 — wired the Slice 055 `ServerHealth` contract into a runtime health file (`HealthReporter` -> `PROJECT0_HEALTH_FILE`). The server writes `starting` at boot, `healthy` once listening, refreshes every ~0.5 s physics stride, and best-effort `stopping` on shutdown; the container `HEALTHCHECK` (`healthcheck.sh`) now checks file existence, freshness, and `status == "healthy"` instead of a bound UDP port.
    Why: The runtime-boundary decision needs a truthful liveness signal — a frozen tick loop must turn the container unhealthy even while the socket stays bound.
    Related work: [Slice 067](slices/067-server-health-file-healthcheck.md), [runtime-boundary decision](../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
    Validation: `scripts/run_gut_validation.sh` on Linux — passed, 50/50 scripts, exit 0 (+1 new `test_health_reporter.gd`). Runtime on Linux: the health file reports `"status":"healthy"` (tick_rate 30), `healthcheck.sh` returns success while the server is listening, and a stale (old-mtime) or missing file fails closed. `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 066 — the operator control plane's audited `start`/`stop` lifecycle actions. Generalized `ServiceController` to a single `run(kind, action, identifier)` verb (start/stop/restart) with a shared `OperationsService._lifecycle`, and added `POST /services/{name}/start` and `/stop`; `RealServiceController` rejects any non-lifecycle action.
    Why: The operator admin interface must control the service lifecycle, not just restart it, over the same allowlisted fixed-argument-vector seam.
    Related work: [Slice 066](slices/066-operator-lifecycle-actions.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests` — 62 passed (48 + 14 new: start/stop unit + API, action-verb call assertions, non-lifecycle-action guard); `scripts/check_record_sync.sh` exit 0; GUT unaffected.
  - Date: 2026-09-14
    What changed: Delivered Slice 065 — the operator control plane's durable SQLite audit sink (`SqliteAuditLog`), replacing the in-memory `AuditLog` so the job/audit trail survives control-plane restarts. Append-only, WAL-backed, parent-dir auto-created, secret-free (the invite code was already excluded from the `Job`); wired via `OPERATOR_AUDIT_DB_PATH` in `build_production_app`.
    Why: The operator control-plane decision requires audit records to be durable and append-only, not lost on restart.
    Related work: [Slice 065](slices/065-operator-durable-audit-sink.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests` — 48 passed (41 + 7 new: audit-store record/recent, durability across reopen, limit/order, parent-dir, OperationsService end-to-end, secret redaction, config override); `scripts/check_record_sync.sh` exit 0; GUT unaffected.
  - Date: 2026-09-14
    What changed: Delivered Slice 064 — the operator control plane's audited `POST /peers/revoke` action, reusing the enrollment `RevocationService` behind the job/audit model (idempotent `ALREADY_ABSENT`, bounded `UPSTREAM_DELETE_FAILED`), with optional OPNsense wiring.
    Why: The operator control-plane decision requires peer revocation to reuse the enrollment seam through the audited job model.
    Related work: [Slice 064](slices/064-operator-revoke-peer-action.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests` — 41 passed (32 + 9 new revoke-peer); `scripts/check_record_sync.sh` exit 0; GUT unaffected.
  - Date: 2026-09-14
    What changed: Delivered Slice 063 — the operator control plane's audited `POST /invites` mint action, reusing the enrollment store + CSPRNG code behind the job/audit model; the single-use invite code is returned in the response but never written to the audit log.
    Why: The operator control-plane decision requires invite minting to reuse the enrollment seam through the audited job model, without leaking the secret code.
    Related work: [Slice 063](slices/063-operator-mint-invite-action.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests` — 32 passed (24 + 8 new mint-invite, including the secret-redaction invariant); `scripts/check_record_sync.sh` exit 0; GUT unaffected.
  - Date: 2026-09-14
    What changed: Delivered Slice 062 — the operator control plane's first mutating action (`POST /services/{name}/restart`) behind an audited job lifecycle (`Job`/`JobState`, append-only `AuditLog`), plus `GET /jobs`; allowlisted, token-authed, fail-closed, with a fixed `systemctl`/`docker` restart controller.
    Why: The operator control-plane decision requires mutating actions to be jobs with a correlation id and audit trail; restart is the first such action.
    Related work: [Slice 062](slices/062-operator-restart-action.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests` — 24 passed (13 status + 11 new restart/job/audit); `scripts/check_record_sync.sh` exit 0; GUT unaffected.
  - Date: 2026-09-14
    What changed: Delivered Slice 061 — the operator control plane's read-only status foundation (`infra/operator/`): a private, operator-token-authed FastAPI service over an allowlisted systemd/docker inspector (fixed read-only commands, no shell, no mutation), loopback-bound and separate from the public enrollment path.
    Why: The operator control-plane decision needs a private, authenticated surface for host-service state before adding mutating actions (restart/invites/revoke/update) behind an audit/job model.
    Related work: [Slice 061](slices/061-operator-status-service.md), [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
    Validation: `pytest infra/operator/tests infra/enrollment/tests` — 68 passed (13 new operator + 55 enrollment, no regression from making `infra` a package); GUT unaffected (359/359); `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 060 — wired the Slice 059 assertion issuer/validator into `LoginGateway` (`set_assertion_seams`, `issue_account_assertion`, `issue_character_assertion`, `establish_session_from_assertion`); `server_main` constructs them from `PROJECT0_ASSERTION_SECRET`.
    Why: Make the signed assertion the gateway's session mechanism in-process, so the later out-of-process login-service split only has to move issuance across the wire.
    Related work: [Slice 060](slices/060-assertion-session-binding.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: Authoritative Linux gate 359/359 across 49/49 scripts, exit 0 (7 new tests); e2e harnesses green; `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 059 — the shared `SessionAssertion` contract and server-only HMAC-SHA256 `AssertionIssuer`/`AssertionValidator` (account-only then selected-Character signed assertions the game server validates locally).
    Why: The login-boundary decision needs a signed assertion the game server can trust without sharing a database, before the login service is split out (Slice 060).
    Related work: [Slice 059](slices/059-session-assertions.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: Authoritative Linux gate 352/352 across 48/48 scripts, exit 0 (22 new assertion tests: round trip + full rejection matrix); `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 058 — the in-process `LoginGateway` seam composing `AuthService`+`CharacterService` behind one narrow interface, with the login/character/enter-world RPC dispatch rerouted through `/root/LoginGateway`. Pure delegation, no behavior change.
    Why: Login-boundary decision step 1 — establish the single login interface a future out-of-process login service (signed assertions over private HTTPS) will satisfy, before splitting the service out.
    Related work: [Slice 058](slices/058-login-gateway-seam.md), [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
    Validation: Authoritative Linux gate 330/330 across 46/46 scripts, exit 0 (4 new `test_login_gateway` cases); real-server e2e harnesses green; `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Delivered Slice 057 — host-persistent game data under `/var/lib/project0` (Compose bind mounts) plus `sqlite3` in the image and consistent `backup.sh`/`restore.sh`.
    Why: The persistence decision requires durable state outside the image on the host boundary, with consistent backup/restore, before the login/game DB split and cutover.
    Related work: [Slice 057](slices/057-game-server-persistence-boundary.md), [persistence decision](../.scratch/container-platform/issues/03-persistence-and-data-ownership.md)
    Validation: Runtime evidence on `192.168.1.254` — DB persisted under `/var/lib/project0/game`; durability across container replacement (Canon `idempotent` on 2nd boot); backup `integrity_check` ok; restore recovered a wiped data dir (Canon `idempotent`); native `project0-server` untouched. GUT gate and record sync green (no `.gd` changes).
  - Date: 2026-09-14
    What changed: Delivered Slice 056 — the game-server OCI image (`deploy/game-server/`) and run-beside-native Compose descriptor. Built and booted on the Linux host beside the live native server on an isolated port.
    Why: The runtime-boundary decision requires the container built and proven beside the native server (rollback preserved) before any cutover.
    Related work: [Slice 056](slices/056-game-server-container-image.md), [runtime-boundary decision](../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
    Validation: Runtime evidence on `192.168.1.254` — build exit 0; `Server listening on 0.0.0.0:9999` with SQLite+Canon ready; isolated port `127.0.0.1:19999` bound; healthcheck `healthy`; graceful SIGTERM stop ~0.39s; native `project0-server` untouched (still `active` on 9999). Full GUT gate and record sync green (no `.gd` changes).
  - Date: 2026-09-14
    What changed: Moved P-014 to `In Progress` and delivered its first foundation slice — the pure, server-only `ServerHealth` fixed-tick and health-snapshot contract — as the first delivery of the container-platform wayfinder map.
    Why: The runtime boundary is now decided (OCI image, systemd supervision, `/apps/project0`, `/var/lib/project0`, UDP 9999, non-root, health/tick/shutdown), so the bounded tick and machine-readable health contract can land before the container image consumes it.
    Related work: [Slice 055](slices/055-server-fixed-tick-and-health-contract.md), [container-platform map](../.scratch/container-platform/map.md)
    Validation: Authoritative Linux gate `scripts/run_gut_validation.sh` 326/326 across 45/45 scripts, exit 0; `scripts/check_record_sync.sh` exit 0.

### P-016: Biological progression and kinetic combat systems

- Status: `Implemented`
- Feature: Players develop a fixed-budget six-attribute biological vessel,
  derived kinetic capabilities, permanent Meridian pathways, temporary
  Burnout, and equilibrium-bound magic through server-validated play.
- Problem solved: Combat and progression need one coherent opportunity-cost
  model that rewards embodied play without stat-gating player reasoning.
- Phase: 15. Biological progression and kinetic systems (also constrains Phase 12)
- Public seam: Future versioned shared contracts, server-owned progression and
  action-resolution services, replicated effective state, and client
  presentation/prediction adapters defined by `CLAUDE.md` and ADR 0002.
- Validation: Future slices must prove fixed-budget redistribution, trusted
  progression evidence, friction penalties, Meridian idempotency, Burnout
  expiry without base-state mutation, magic equilibrium rejection, and client
  reconciliation at public server seams.
- Related work: [Slice 010](slices/010-core-mechanics-architecture.md),
  [Slice 011](slices/011-mind-tool-architecture-refinement.md),
  [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)
- Implementation slices: [Slice 132](slices/132-phase15-embodiment-tuning.md)
  (P-016-A foundation, part 1), [Slice 133](slices/133-phase15-vessel-progression.md)
  (P-016-A foundation, part 2), [Slice 134](slices/134-phase15-effective-mechanics-snapshot.md)
  (P-016-A foundation, part 3), [Slice 135](slices/135-phase15-friction-modifier.md)
  (P-016-B inverse friction), [Slice 136](slices/136-phase15-kinetic-flow.md)
  (P-016-C Kinetic Flow), [Slice 137](slices/137-phase15-meridian-pathways.md)
  (P-016-D Meridian pathways), [Slice 138](slices/138-phase15-biological-burnout.md)
  (P-016-E Biological Burnout), [Slice 139](slices/139-phase15-magic-equilibrium.md)
  (P-016-F Magic equilibrium), [Slice 140](slices/140-phase15-embodiment-progression-service.md)
  (P-016-A/G server progression service; closes the exit gate),
  [Slice 142](slices/142-effective-mechanics-replication.md) (post-exit-gate
  follow-on: live RPC replication of the EffectiveMechanicsSnapshot to the owning
  client at world entry),
  [Slice 143](slices/143-vessel-persistence.md) (post-exit-gate follow-on:
  durable vessel persistence — `VesselRepository` over `SqliteStore` + serializer).
- Change history:
  - Date: 2026-09-18
    What changed: Delivered the second and last of Slice 140's documented
    follow-ons (Slice 143) — **durable vessel persistence**. Added
    `VesselProgressionState.to_wire_dict()` (the inverse of the existing
    `from_wire_dict`) and a server-only `server/vessel_repository.gd`
    (`VesselRepository`) over the shared `SqliteStore` engine seam, mirroring
    `CanonRepository`: `ensure_schema`, an idempotent `save_vessel` upsert by
    `character_id`, and a `load_vessel` that revalidates the stored row fail-closed
    against the current tuning (schema/structure/bounds/budget) or returns
    not-found. A Character's earned vessel now survives a server restart. Feature
    stays `Implemented`.
    Why: Close the last Phase 15 persistence follow-on — earned progression must
    not vanish on process stop.
    Related work: [Slice 143](slices/143-vessel-persistence.md),
    [Slice 140](slices/140-phase15-embodiment-progression-service.md), #219, #223.
    Validation: full GUT suite on Linux host `okami` (working-tree overlay) —
    100 scripts / 729 tests / 729 passing, 2325 asserts, exit 0 (+1 script, +6
    tests over the prior follow-on); new `test_vessel_repository` 6/6 over a real
    temporary `user://` SQLite database (save→restart→identical recovery, trained
    round-trip, upsert, corrupt-row fail-closed, empty-id refusal). Live wiring
    into the world-entry/progression-service path remains (gated on the
    shared-vs-per-Player service-ownership decision noted in the slice record).
  - Date: 2026-09-18
    What changed: Delivered the post-exit-gate follow-on (Slice 142) that Slice
    140 explicitly deferred — the **live RPC replication of the
    `EffectiveMechanicsSnapshot` to the owning client at world entry**, over the
    same peer-scoped channel proven for the Character snapshot in Phase 14.
    `server/server_player_state.gd` now creates a durable vessel (via its own
    `EmbodimentProgressionService` + resolved default tuning) and emits
    `effective_mechanics_ready`; `server/server_main.gd` replicates it peer-scoped;
    `client/network_client.gd` validates the untrusted wire fail-closed, retains
    it, and re-emits it; `client/effective_mechanics_label.gd` renders a HUD
    readout. Presentation-safe only — raw effective/base numbers and tuning tables
    never cross. Feature stays `Implemented` (this is wiring on top of the closed
    gate).
    Why: Make the Phase 15 server-authoritative embodiment actually observable on
    the client, closing the first of Slice 140's two documented follow-ons.
    Related work: [Slice 142](slices/142-effective-mechanics-replication.md),
    [Slice 140](slices/140-phase15-embodiment-progression-service.md), #219, #224.
    Validation: full GUT suite on Linux host `okami` (working-tree overlay) —
    99 scripts / 723 tests / 723 passing, 2304 asserts, exit 0 (+2 scripts, +11
    tests over main); new `test_effective_mechanics_replication` 7/7 and
    `test_effective_mechanics_label` 5/5, Phase 14 Character-snapshot channel
    unchanged. Vessel persistence to SQLite remains the outstanding Slice 140
    follow-on.
  - Date: 2026-09-17
    What changed: Delivered the ninth P-016 slice (Slice 140) — the
    server-authoritative `EmbodimentProgressionService`, which **closes the Phase
    15 exit gate**. It owns the vessels/Meridians/Burnouts, accepts deduplicated
    training/cross-training evidence, resolves magic, and composes the vessel +
    all five subsystems (friction, kinetic, meridian, burnout, magic) into one
    deterministic, presentation-safe `EffectiveMechanicsSnapshot` — hidden numeric
    state stays server-side. Feature status moves `In Progress` → `Implemented`.
    Why: Prove the whole Phase 15 layer works end-to-end under server authority —
    the ADR-0006 P-016-A acceptance/derivation payoff.
    Related work: [Slice 140](slices/140-phase15-embodiment-progression-service.md),
    #219, #224.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 503 tests /
    503 passing, exit 0; new `test_embodiment_progression_service` 10/10 (the
    end-to-end exit-gate assertion). The live RPC replication (the proven Phase 14
    channel pattern) and vessel persistence are explicit follow-on wiring, not
    gate blockers.
  - Date: 2026-09-17
    What changed: Delivered the eighth P-016 slice (Slice 139, P-016-F) — Magic
    equilibrium, the last embodiment subsystem. Added the magic tuning namespace
    on `server/embodiment_tuning.gd` + `shared/magic_equilibrium.gd`: physical
    bulk (STR + CON) insulates and grounds magic, so `resolve(effective_nodes,
    spell_tier, tuning)` yields CHANNELED / FIZZLE / BACKLASH / REJECTED with a
    bounded reason — higher tiers demand a leaner vessel, and every attempt has an
    explicit outcome (never a client success, never silently consumed). All five
    Phase 15 subsystems (friction, kinetic, meridian, burnout, magic) are now
    delivered on the P-016-A read-model.
    Why: Magic's embodied opportunity cost — lean out or ground the current.
    Related work: [Slice 139](slices/139-phase15-magic-equilibrium.md), #219.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 501 tests /
    501 passing, exit 0; new `test_magic_equilibrium` 8/8. Feature stays
    `In Progress`: the server progression service that wires the vessel +
    subsystems into live replication remains.
  - Date: 2026-09-17
    What changed: Delivered the seventh P-016 slice (Slice 138, P-016-E) —
    Biological Burnout. Added the burnout tuning namespace on
    `server/embodiment_tuning.gd` + `shared/burnout_instance.gd`: a temporary
    modifier (authoritative start/end tick, pathway, source action, tuning
    version) that flattens the affected pathway's effective Control to zero while
    active and restores at its end tick without touching base state, plus the
    normative lifecycle transition validator (READY→SURGE_VALIDATING→ACTIVE_SURGE
    →BURNED_OUT→RECOVERED→READY, REJECTED branch).
    Why: An Overload Surge has a real, temporary cost that never erases earned
    state and survives reconnects (server-owned clock).
    Related work: [Slice 138](slices/138-phase15-biological-burnout.md), #219.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 500 tests /
    500 passing, exit 0; new `test_burnout_instance` 7/7. Feature stays
    `In Progress`: magic (P-016-F) and the server progression service remain.
  - Date: 2026-09-17
    What changed: Delivered the sixth P-016 slice (Slice 137, P-016-D) — Meridian
    pathways. Added the meridian tuning namespace on `server/embodiment_tuning.gd`
    + `shared/meridian_state.gd`: per-pathway (Impact STR+CON / Flow DEX+WIS /
    Spark STR+DEX) progress driven by DEDUPLICATED cross-training evidence, with a
    deterministic, idempotent, durable threshold unlock — a replayed evidence id
    can neither progress nor re-unlock, per the spec.
    Why: Permanent earned pathways that cannot be farmed or double-counted across
    reconnects/replays.
    Related work: [Slice 137](slices/137-phase15-meridian-pathways.md), #219.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 501 tests /
    501 passing, exit 0; new `test_meridian_state` 8/8. Feature stays
    `In Progress`: burnout/magic (P-016-E…F) and the server progression service
    remain.
  - Date: 2026-09-17
    What changed: Delivered the fifth P-016 slice (Slice 136, P-016-C) — the
    Kinetic Flow layer. Added the kinetic tuning namespace on
    `server/embodiment_tuning.gd` + `shared/kinetic_flow.gd`: the pure derivation
    of Volume (←CON), Control (←DEX), and Output (←STR), where low Control
    relative to Volume sloshes energy and inflates action cost, per the spec's
    Kinetic Flow Layer.
    Why: Turn raw attributes into kinetic capability with an opportunity cost for
    reservoir-without-finesse builds, on the P-016-A seam.
    Related work: [Slice 136](slices/136-phase15-kinetic-flow.md), #219.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 499 tests /
    499 passing, exit 0; new `test_kinetic_flow` 6/6. Feature stays `In Progress`:
    meridian/burnout/magic (P-016-D…F) and the server progression service remain.
  - Date: 2026-09-17
    What changed: Delivered the fourth P-016 slice (Slice 135, P-016-B) — the
    first subsystem atop the read-model. Added the friction tuning namespace on
    `server/embodiment_tuning.gd` + `shared/friction_modifier.gd`: the pure
    derivation of Massive Bulk (high STR + CON → shorter dodge, longer recovery,
    sinks) or Fragile Agility (high DEX + low CON → fast stamina regen, ~zero
    stagger resistance, water-skip) from the effective nodes, per the spec's
    Inverse Biological Friction.
    Why: The first embodiment cost derived on the P-016-A seam — pushing a body
    to an extreme has organic consequences.
    Related work: [Slice 135](slices/135-phase15-friction-modifier.md), #219.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 500 tests /
    500 passing, exit 0; new `test_friction_modifier` 7/7. Feature stays
    `In Progress`: kinetic/meridian/burnout/magic (P-016-C…F) and the server
    progression service remain.
  - Date: 2026-09-17
    What changed: Delivered the third P-016 slice (Slice 134, P-016-A part 3) —
    `shared/effective_mechanics_snapshot.gd` (`EffectiveMechanicsSnapshot`): the
    derived, replicated read-model. The server derives effective node values from
    the durable vessel under the CURRENT tuning (foundation: effective = earned
    base, no modifiers yet) and replicates only a presentation-safe view
    (normalized graph proportions + tuning provenance + a `derived` map), never
    raw numbers. Deterministic derivation; fail-closed `from_presentation_wire`.
    Why: The presentation-safe read-model the whole progression layer replicates
    through — balance is transparent and universal, never a raw-stat leak.
    Related work: [Slice 134](slices/134-phase15-effective-mechanics-snapshot.md),
    #219, #224.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 501 tests /
    501 passing, exit 0; new `test_effective_mechanics_snapshot` 8/8. Feature
    stays `In Progress`: the server progression service + headless assertion and
    P-016-B…F remain.
  - Date: 2026-09-17
    What changed: Delivered the second P-016 slice (Slice 133, P-016-A part 2) —
    `shared/vessel_progression_state.gd` (`VesselProgressionState`): the durable
    earned six-node vessel pinned to a `tuning_version`, plus the ADR-0006
    fixed-budget redistribution on `train` (weighted opposition compression,
    floor clamp + deterministic re-spread, atomic reject-at-capacity). Every gain
    preserves the budget; no node drops below its floor; a rejected/mismatched
    train changes nothing.
    Why: The core progression mechanic — you keep exactly the graph you earn, and
    a gain that would breach the body's floors is refused cleanly.
    Related work: [Slice 133](slices/133-phase15-vessel-progression.md), #219, #223.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 504 tests /
    504 passing, exit 0; new `test_vessel_progression_state` 11/11. Feature stays
    `In Progress`: effective snapshot (134) and P-016-B…F remain.
  - Date: 2026-09-17
    What changed: Started Phase 15 (P-016). Delivered the first slice (Slice 132,
    P-016-A part 1) — the versioned, server-owned embodiment tuning resolve seam:
    `shared/embodiment_tuning_schema.gd` (shape/bounds/helpers) +
    `server/embodiment_tuning.gd` (frozen `const` tables behind the sole,
    fail-closed `resolve(tuning_version)`). Subsystems never read tables directly;
    unknown versions fail closed with no fallback.
    Why: The reproducible tuning foundation all six embodiment subsystems build
    on, per ADR 0006.
    Related work: [Slice 132](slices/132-phase15-embodiment-tuning.md), #219, #220.
    Validation: full GUT suite on Linux host `okami` — 73 scripts / 501 tests /
    501 passing, exit 0; new `test_embodiment_tuning` 8/8. Feature stays
    `In Progress`: vessel state (133), effective snapshot (134), and the
    friction/kinetic/meridian/burnout/magic subsystems (P-016-B…F) remain.

The remaining scope of server-authoritative networked
multiplayer (movement synchronization, prediction, and world-state
replication) is completed in Slices 002, 004, 005, and 007.

## Ready Features

Design-complete capabilities whose originating issues are all `resolved`, ready
for a developer to pick up. No implementation has started.

## In Progress Features

### F-033: Character world entry (server binding)

- Status: `Implemented`
- Feature: An authenticated peer that has selected a Character can enter the
  world as that Character. The server resolves the selection from the session
  (the client names neither the account nor the character) and binds the
  Character's identity/cosmetic to the peer's authoritative Player, fail-closed.
- Problem solved: [F-032](#f-032-character-crud-over-the-wire-server) lets a peer
  select a Character, but nothing instantiated the in-world Player *as* that
  Character — selection had no in-world effect.
- How it solves the problem: Slice 043 adds
  `server/character_service.gd::get_selected_character(peer_id)` (derives the
  account + `selected_character_id` from the session and returns the live
  `CharacterRecord`, else `NOT_AUTHENTICATED`/`NO_CHARACTER_SELECTED`/
  `NO_SUCH_CHARACTER`), `server/server_player_state.gd::bind_character()`
  (identity/cosmetic only — position/combat authority unchanged), and additive
  `submit_enter_world`/`receive_enter_world_request_on_server`/
  `receive_enter_world_result`/`world_entry_received` on
  `client/network_client.gd`, following the Slice 040/042 forwarding pattern.
  The RPC receiver resolves the Character via `CharacterService` and binds it to
  the peer's `ServerPlayerState` (both `/root` nodes). Additive: the connect-time
  anonymous spawn is unchanged, so the real-server e2e harnesses stay green.
  **Slice 044 adds client login/register and character select/create UI screens**
  (account_gate.tscn, character_gate.tscn, updated project.godot main_scene).
  The server portion of F-033 is complete; GUI confirmation on Windows pending.
- Phase: 10. Player accounts and characters
- Implementation slices: [Slice 043](slices/043-character-world-entry.md),
  [Slice 044](slices/044-client-login-character-ui.md) (GUI scaffolding, Windows verification pending).
- Public seam: `server/character_service.gd` (`get_selected_character`);
  `server/server_player_state.gd` (`bind_character`, `character_id`,
  `character_display_name`, `character_cosmetic`); `client/network_client.gd`
  (`submit_enter_world`, `world_entry_received`); `client/player_identity.gd`
  (account_id, username, selected_character_id, selected_character, display_name,
  target_host); `account_gate.tscn`/`account_gate.gd` (login/register UI);
  `character_gate.tscn`/`character_gate.gd` (character select/create UI).
- Validation: `tests/integration/test_character_crud_rpc.gd`'s world-entry
  scenario (unauthenticated / unselected refused; selected resolves). Linux
  validation on the authoritative server passed the full GUT suite at 315/315
  tests across 44/44 scripts and 1224 assertions, exit 0; enrollment tests
  passed 55/55; `scripts/check_record_sync.sh` exited 0. The client GUI flow
  remains owned by F-034/Slice 044.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [F-032](#f-032-character-crud-over-the-wire-server) (the consumed CRUD/session seam),
  [Slice 044 SDD](slices/044-client-login-character-ui.md).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-033 via Slice 043 — added `get_selected_character`,
    `bind_character`, and the additive `enter_world` RPCs; validated at 268/268.
    Client screens (spec slice 5) scaffolded in Slice 044; GUI verification pending.
  - Date: 2026-09-13
    What changed: Slice 044 scaffolding complete — client login/register
    (account_gate) and character select/create (character_gate) UI scenes and
    controllers added; project.godot main_scene updated to account_gate.tscn;
    all 268/268 tests still passing.
    Why: Prepare client UI for Windows GUI verification before full Phase 14
    completion.
    Related work: [Slice 044](slices/044-client-login-character-ui.md)
    Validation: `scripts/run_gut_validation.sh` 268/268, exit 0.

### F-034: Client login and character selection screens

- Status: `Implemented`
- Feature: Client-side UI for account login/registration and character
  selection/creation, wired to Phase 40-43 server-side authentication, character
  CRUD, and world-entry machinery.
- Problem solved: Phase 40-43 delivers server-side identity binding and
  character management, but has no client GUI — all RPC testing occurs in
  headless integration harnesses. End-to-end gameplay requires visual login and
  character screens.
- How it solves the problem: Slice 044 scaffolds two scenes:
  - `account_gate.tscn`/`account_gate.gd`: username/password/host inputs,
    login/register buttons, status display. Validates input (username 4-20 chars,
    password 6+ chars), opens connection, submits auth RPC, listens to
    `auth_result_received` signal, stores account_id/username in `PlayerIdentity`,
    transitions to character_gate.tscn on success.
  - `character_gate.tscn`/`character_gate.gd`: character roster ItemList,
    select/create/delete buttons, status display. On ready: fetches character
    list via `submit_list_characters()`. Select/create/delete operations dispatch
    appropriate RPC and listen to `character_result_received`. On select success:
    calls `submit_enter_world()` (Slice 043 seam). On world-entry success:
    stores selected_character_id/display_name/selected_character in PlayerIdentity,
    transitions to gameplay.tscn.
  - `project.godot`: main_scene changed from `identity_gate.tscn` (old placeholder)
    to `account_gate.tscn`.
  - `connection_status.gd`: updated to call `connect_to_server()` safely
    (no second peer if already connected; intended pattern is login manages the
    connection, gameplay inherits it).
  - `player_identity.gd`: restructured to hold account_id, username,
    selected_character_id, selected_character dict, display_name, target_host
    (was: only display_name + target_host).
- Phase: 10. Player accounts and characters
- Implementation slices: [Slice 044](slices/044-client-login-character-ui.md)
- Public seam: `account_gate.tscn`/`account_gate.gd`;
  `character_gate.tscn`/`character_gate.gd`; `player_identity.gd` new fields;
  `project.godot` run/main_scene.
- Validation: Authoritative Linux validation passed 315/315 tests across 44/44
  scripts and 1224 assertions, exit 0. Windows GUI acceptance was confirmed:
  login/register, Character roster, create/select/delete, world entry, town
  and monster rendering, WASD movement, monster interaction, Character Select
  return, replacement Character world entry, and authoritative Player replay.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [F-033](#f-033-character-world-entry-server-binding) (consumed server seams),
  [Slice 044 SDD](slices/044-client-login-character-ui.md).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-034 via Slice 044 — scaffolded account_gate and
    character_gate UI scenes + controllers, updated project.godot main_scene,
    restructured PlayerIdentity, refined connect_to_server() documentation.
    Why: Enable Windows GUI verification of login → character select → world-entry
    flow before Phase 14 completion.
    Validation: `scripts/run_gut_validation.sh` 268/268, exit 0.
    Known limitation: spawn-deferral abandoned after e2e harness brittleness;
    login scene persists until world-entry succeeds, then transitions to
    gameplay — intended pattern to avoid misrouted Player spawns.
  - Date: 2026-09-14
    What changed: Closed F-034 after user-confirmed Windows GUI acceptance of
    the complete login → Character → world → gameplay lifecycle, including
    repeated Character replacement and return to Character Select.
    Validation: Native UI smoke passed all 3 scene contracts; authoritative
    Linux GUT passed 315/315; Windows GUI flow confirmed by the user.
  - Date: 2026-09-15
    What changed: Fixed the in-world logout/return button for the login split
    (default ON since the Slice 084 cutover). `client/gameplay_logout.gd` now
    returns to `account_gate.tscn` and drops the game connection when the split
    is enabled (it returned to `character_gate.tscn` on the game connection),
    and the button label is set from `_logout_label()` at `_ready` — "Logout"
    under the split, "Character Select" in combined mode.
    Why: Root-cause learning — during the Windows GUI confirmation of the split
    flow, logging out showed `Failed to load characters (account_authority_disabled)`.
    Symptom: the Character screen's `list_characters` was refused. Public seam:
    `client/gameplay_logout.gd` scene transition. Confirmed cause: the world
    handoff (Slice 077) disconnects from the login process before connecting to
    the assertion-only game process, so returning to `character_gate.tscn` listed
    Characters against the game server, which has no account authority. The
    Slice 044 GUI acceptance predated the split, so the combined-mode return path
    was never exercised against an assertion-only server. Countermeasure: a
    split-aware return path + label, covered by
    `tests/unit/test_gameplay_logout_target.gd`. Remaining limitation: split
    logout requires re-authenticating on the login screen (the client caches no
    credentials); returning to the Character list without re-login would need a
    login-session-resume seam (possible follow-up).
    Validation: `scripts/run_gut_validation.sh` on Linux passed 405/405 tests
    across 60 scripts, exit 0 (adds `tests/unit/test_gameplay_logout_target.gd`;
    one real-process multi-peer e2e flake cleared on re-run). Windows GUI:
    logout now returns to the login screen cleanly (no `account_authority_disabled`).
  - Date: 2026-09-15
    What changed: Delivered Slice 087 — the in-world "Character Select" button
    now returns to the Character roster without re-typing the password under the
    split. The login→game handoff also fetches a longer-lived account resume
    token (server-owned TTL from `PROJECT0_RESUME_TTL_SECONDS`, default 1 hour,
    clamped) while still on the login process; `NetworkClient.perform_return_to_character_select`
    drops the game link, reconnects to the login process, and re-establishes a
    session from that token so `list_characters` works. `client/gameplay_logout.gd`
    routes to the Character list on success and falls back to the login screen
    when the token is missing or expired; the button reads "Character Select"
    again. Supersedes the interim Slice-084-fix "Logout → login screen" behavior.
    Why: the split cutover left "return to Character Select" requiring a full
    re-login (the account session lives on the login process the handoff left);
    a bounded client-held resume token restores the original UX.
    Security note: the resume token is a bearer credential for account/Character
    management held in client memory for its TTL, at the home-hosted trust level;
    it is minted with the server's clock and a clamped bound, never client-set.
    Validation: `scripts/run_gut_validation.sh` on Linux passed 407/407 tests
    across 60 scripts, exit 0 (adds resume-flow + TTL cases to
    `tests/unit/test_gameplay_logout_target.gd`); `scripts/test_login_handoff_e2e.gd`
    ALL PASS (the added resume step does not disturb the forward handoff);
    Windows GUI confirmation of the return path.


### F-032: Character CRUD over the wire (server)

- Status: `Implemented`
- Feature: An authenticated peer can list, create, select, and soft-delete its
  own Characters over the ENet link. The server scopes every operation to the
  peer's session account — the client never supplies an `account_id` — and
  enforces the 5-Character cap, global live-name uniqueness, and ownership,
  returning typed `CharacterRecord` DTOs or a bounded rejection, session-gated
  and fail-closed.
- Problem solved: [F-030](#f-030-accounts-and-characters-persistence-repository)'s
  repository can create/select/delete Characters and
  [F-031](#f-031-account-authentication-and-session-server) can authenticate a
  peer, but nothing connected the two over the wire: a logged-in peer had no
  way to manage its roster, and no seam enforced that a peer can only touch its
  own account's Characters.
- How it solves the problem: Slice 042 adds `server/character_service.gd`
  (`class_name CharacterService`, a `/root` Node like `AuthService`) with
  session-gated `list_characters`/`create_character`/`select_character`/
  `delete_character`. Each method requires an authenticated session (else a
  bounded `NOT_AUTHENTICATED` with no side effect) and derives `account_id`
  from the caller's `SessionRegistry` session — never from the client — so a
  peer authenticated as account A cannot list/select/delete account B's
  Character even when it knows B's `character_id`. `shared/character_record.gd`
  gains additive pure `to_wire_dict()`/`from_wire_dict()` so a `CharacterRecord`
  crosses the RPC boundary as a client-safe DTO (fail-closed parse; no
  credential material). `client/network_client.gd` gains four additive C→S
  character request RPCs, matching `submit_*` helpers, and a
  `receive_character_result` S→C RPC (bounded outcome + wire dicts only — never
  the `detail` string), following the Slice 040 auth-RPC pattern.
  `server/session_registry.gd` gains an additive `selected_character_id` (set
  by `select`, for the future world-entry slice), and
  `server/auth_service.gd` gains a `get_session_registry()` getter so
  `server_main.gd` shares one `SessionRegistry` instance between auth and
  character CRUD.
- Phase: 10. Player accounts and characters
- Implementation slices: [Slice 042](slices/042-character-crud-rpc.md)
- Public seam: `server/character_service.gd` (`CharacterService.list_characters`,
  `create_character`, `select_character`, `delete_character`);
  `shared/character_record.gd` (`to_wire_dict`, `from_wire_dict`);
  `server/session_registry.gd` (`set_selected_character`,
  `get_selected_character`); `client/network_client.gd`
  (`submit_list_characters`, `submit_create_character`, `submit_select_character`,
  `submit_delete_character`, `character_result_received`).
- Validation: `tests/integration/test_character_crud_rpc.gd` (session-gating,
  the account-scoping authorization proof, cap/name-taken/name-invalid, select
  records the selection + refreshes `last_played_at`, soft-delete) and the
  extended `tests/unit/test_character_record.gd` wire round-trip. Full suite
  `scripts/run_gut_validation.sh` 267/267 across 36 scripts, exit 0
  (`scripts_expected == scripts_ran == 44`); Linux authoritative-server GUT
  validation passed 315/315 tests and 1224 assertions, enrollment tests passed
  55/55, and `scripts/check_record_sync.sh` exited 0.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [F-031](#f-031-account-authentication-and-session-server) (the consumed
  auth/session seam), [F-030](#f-030-accounts-and-characters-persistence-repository)
  (the consumed repository).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-032 via Slice 042 — added `CharacterService`, the
    additive `CharacterRecord` wire serialization, the session
    `selected_character_id`, the `AuthService` session-registry getter, and the
    four character CRUD RPCs; validated at 267/267.

### F-031: Account authentication and session (server)

- Status: `Implemented`
- Feature: A connected peer can register a new Account or log in to an
  existing one over the ENet link; the server verifies credentials with
  PBKDF2-HMAC-SHA256 off the main thread, binds an opaque in-memory session to
  the peer on success, and returns an `AccountHandle` or a bounded rejection —
  all server-authoritative and fail-closed. Auth is additive: the existing
  connect → (blueprint, spawn, house, replication) lifecycle is unchanged and
  the world stays always-playable with no login required yet.
- Problem solved: [F-030](#f-030-accounts-and-characters-persistence-repository)'s
  repository can durably store credential bytes but has no RPC, no hashing,
  and no session concept — nothing in the running server actually computes or
  verifies a PBKDF2 hash, and no peer can be told "you are Account X" for the
  lifetime of a connection.
- How it solves the problem: Slice 040 adds `server/password_hasher.gd`
  (`class_name PasswordHasher`) — a from-scratch RFC 8018 PBKDF2-HMAC-SHA256
  block construction on top of Godot `Crypto.hmac_digest` (Godot has no native
  PBKDF2), 16-byte CSPRNG salt, 32-byte key, `constant_time_compare`
  verification — and `server/session_registry.gd` (`class_name
  SessionRegistry`), an in-memory `peer_id -> session` binding that is never
  persisted and is cleared on disconnect. `server/auth_service.gd`
  (`class_name AuthService`) wires both to the F-030 repository: `register`
  auto-authenticates on success; `login` verifies and binds a session;
  unknown-username and wrong-password both reject with the identical
  `BAD_CREDENTIALS` reason (no user enumeration), and the unknown-username
  path still pays the full hashing cost so the timing is indistinguishable
  too. `client/network_client.gd` gains additive
  `receive_register_request_on_server`/`receive_login_request_on_server`
  C→S RPCs and a `receive_auth_result` S→C RPC (`AccountHandle` fields only —
  never salt/hash), following the existing
  `receive_input_intent_on_server`/`receive_authoritative_position` pattern.
  `server/server_main.gd` now opens a real `SqliteStore` and calls
  `AccountCharacterRepository.ensure_schema()` at boot — the first runtime
  consumer of the F-029/F-030 persistence stack — and fails closed (refuses to
  start) if either step fails, matching the existing hub-fixture check.
- Threading: PBKDF2 at a real iteration count is deliberately slow (~1s CPU on
  this host at 100000 iterations). `AuthService.register`/`login` dispatch the
  hash/verify call to a `WorkerThreadPool` task and `await` a
  `process_frame` poll loop for its completion, so the authoritative
  simulation tick and every other connected peer's movement/combat processing
  never stall while a hash runs — see
  [Slice 040](slices/040-account-auth-session.md#threading) for detail.
- Phase: 10. Player accounts and characters
- Implementation slices: [Slice 040](slices/040-account-auth-session.md)
- Public seam: `server/password_hasher.gd` (`PasswordHasher.hash_password`,
  `verify_password`); `server/session_registry.gd` (`SessionRegistry.bind`,
  `is_authenticated`, `get_session`, `clear`); `server/auth_service.gd`
  (`AuthService.register`, `login`, `is_authenticated`, `clear_session`);
  `client/network_client.gd` (`submit_register`, `submit_login`,
  `auth_result_received`).
- Validation: Focused `tests/unit/test_password_hasher.gd` 7/7 (including a
  published PBKDF2-HMAC-SHA256 known-answer vector) and
  `tests/integration/test_account_auth_session.gd` 8/8. Full suite
  `scripts/run_gut_validation.sh` 248/248 across 32 scripts, exit 0
  (`scripts_expected == scripts_ran == 32`). The authoritative Linux run then
  passed 315/315 tests across 44/44 scripts and 1224 assertions, exit 0.
  Manual runtime boot smoke confirmed the accounts DB opens/ensures schema and
  the server still reaches `Server listening` with the existing connect
  lifecycle unchanged.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [F-030](#f-030-accounts-and-characters-persistence-repository) (the
  consumed repository), [F-029](#f-029-shared-server-owned-sqlite-persistence-foundation)
  (the consumed SQLite engine foundation).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-031 via Slice 040 — added `PasswordHasher`,
    `SessionRegistry`, `AuthService`, the additive register/login/auth_result
    RPC seam, and `server_main.gd` boot wiring that opens the accounts SQLite
    store and ensures its schema for the first time at runtime.
    Why: Phase 14's spec needs real credential verification and a session
    concept before Character CRUD (slice 4) or client screens (slice 5) can be
    built; this is the next unblocked slice now that F-030's repository is
    delivered.
    Validation: Focused suites 7/7 and 8/8; full GUT suite 248/248 across 32
    scripts, exit 0.

### F-035: Secure Windows tunnel enrollment and credential storage

- Status: `Implemented`
- Feature: A Windows client provisions its own WireGuard peer through
  self-service HTTPS login or an explicit single-use invite fallback, stores the
  private key with Windows DPAPI, starts the in-process tunnel without a batch
  file, and supports operator revocation without distributing a shared tester
  key.
- Problem solved: The current WAN verifier embeds a disposable private key in
  a one-click executable. That is convenient for validation but recoverable by
  anyone who receives the executable and cannot scale to multiple testers.
- How it solves the problem: Slice 054 generates the client keypair
  locally, redeem the existing enrollment service using only the public key,
  protect the private key with a user-scoped Windows DPAPI wrapper, and load
  the resulting peer configuration at application startup. The existing
  `wgnetstack` tunnel seam remains the transport adapter; the key never enters
  Git, telemetry, HTTP requests, or a distributable binary.
- Deployment boundary: the Linux host builds and runs the independent
  `infra/enrollment` FastAPI service behind `enroll.valentin.vip`; the Windows
  client only calls its `/redeem` endpoint and never owns the enrollment
  service, OPNsense credentials, or allocation database.
- Phase: 11. Public game access
- Implementation slices: [Slice 054](slices/054-secure-windows-tunnel-enrollment.md),
  [Slice 092](slices/092-launcher-login-redeem-assertion.md)
- Public seam: Windows bootstrapper/enrollment client, `POST /redeem`, DPAPI
  credential store, and the existing `NetworkClient` tunnel startup seam.
- Validation: The enrollment service is deployed live and the user confirmed
  all six real-WAN Windows checks on 2026-09-16: fresh enrollment, persisted
  restart, malformed/expired invite rejection, DPAPI access scoping,
  revoked-peer rejection, and one-launch off-LAN gameplay. See
  [docs/f035-secure-launcher-validation-runbook.md](f035-secure-launcher-validation-runbook.md)
  for the recorded checklist. No credentials or private artifacts were retained.
- Deferred improvement: replace manual `--invite-code`/environment provisioning
  with a trusted automatic device-enrollment or approval flow. The client must
  still generate its key locally, transmit only the public key, retain DPAPI
  protection, and keep manual single-use invites as a fallback. This is a
  future F-035 follow-up, not a relaxation of the current security boundary.
- Related work: [P-024](#p-024-public-game-access-via-opnsense-native-wireguard),
  [Slice 048](slices/048-wireguard-enrollment-service.md),
  [Slice 049](slices/049-wireguard-revocation-lifecycle.md),
  [Slice 054](slices/054-secure-windows-tunnel-enrollment.md).
- Change history:
  - Date: 2026-09-16
    What changed: Completed the six-check real-WAN validation for the secure
    Windows launcher and moved F-035 to Implemented.
    Why: Confirm the complete user path against the live enrollment service and
    home-hosted server, not only unit tests and Linux service checks.
    Related work: [Slice 054](slices/054-secure-windows-tunnel-enrollment.md),
    [F-035 runbook](f035-secure-launcher-validation-runbook.md).
    Validation: User-confirmed fresh enrollment, restart persistence,
    malformed/expired rejection, DPAPI scoping, revoked-peer rejection, and
    one-launch off-LAN gameplay all passed on 2026-09-16.
  - Date: 2026-09-16
    What changed: Reconciled the feature plan after the auth-gated onboarding
    delivery. Slice 092 adds self-service launcher login and assertion-gated
    redeem while retaining the explicit invite fallback; the remaining feature
    evidence is the real-WAN runbook, not implementation of a second launcher.
    Why: Keep the feature record aligned with the delivered launcher seam and
    prevent the pending runtime evidence from being mistaken for an unbuilt path.
    Related work: [Slice 092](slices/092-launcher-login-redeem-assertion.md),
    [Slice 093](slices/093-client-https-login-wiring.md),
    [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration),
    [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client).
  - Date: 2026-09-14
    What changed: Deployed the enrollment service live and publicly reachable
    (operational deployment by Copilot): systemd unit `project0-enrollment.service`
    running uvicorn on the okami Linux host bound to `192.168.1.254:8095`,
    config at `/etc/project0/enrollment.env` (mode 600), the WireGuard endpoint
    configured to the static WAN IP `192.69.180.236:51900` (no `game` DNS
    dependency), an OPNsense nginx TLS vhost publishing only `GET /healthz` and
    `POST /redeem` (all else 403), an OPNsense Unbound host override for LAN
    split-horizon, and a Cloudflare-proxied CNAME for the public path.
    Why: Move the enrollment service from service-logic-only (Slices 048/049)
    to a live, publicly reachable endpoint so the Windows launcher's
    `PROJECT0_ENROLLMENT_URL` default can actually be exercised.
    Related work: [Slice 054](slices/054-secure-windows-tunnel-enrollment.md)
    Validation: `.venv-enrollment/bin/python -m pytest infra/enrollment/tests`
    passed 55/55; `https://enroll.valentin.vip/healthz` through Cloudflare
    returned HTTP/2 200 `{"status":"ok"}`; `POST /redeem` through the
    Cloudflare edge returned a real OPNsense peer registration
    (`assigned_address 10.77.0.2/32`, `endpoint 192.69.180.236:51900`),
    followed by a successful `revoke-peer` releasing the allocation; method
    guard confirmed (`GET /redeem` → 403, `GET /` → 403); no private key was
    ever transmitted. The Windows-launcher live tunnel validation remains a
    separate, still-open item.
  - Date: 2026-09-14
    What changed: Started Slice 054 implementation with a Windows one-click
    launcher that generates an X25519 keypair, redeems only the public key,
    protects the private key with DPAPI, and reuses the protected peer state.
    Validation: Windows launcher tests and release build pass; live enrollment
    service deployment and fresh-invite WAN proof remain pending.
  - Date: 2026-09-14
    What changed: Queued F-035 after user-confirmed WAN connectivity using the
    temporary embedded-key launcher.
    Why: Replace recoverable shared tester credentials with per-client
    enrollment and OS-protected private-key storage without interrupting the
    verified WAN path.

### P-024: Public game access via OPNsense-native WireGuard

- Status: `Implemented`
- Feature: Remote players reach the home-hosted authoritative server over a
  split-tunnel WireGuard connection — an in-process userspace netstack
  GDExtension in the Godot client, an invite-code enrollment service, and
  OPNsense-managed peers — without a VPS, OS admin rights, or exposing the LAN.
- Problem solved: The server is only reachable on the LAN today; public play
  needs secure remote access that neither routes through a cloud relay nor
  grants tunnel clients broader reach than the single game host.
- How it solves the problem so far: Slice 028 opens the first implementation
  slice against the design-complete basis — a dedicated, isolated OPNsense
  WireGuard instance (`wg0`, UDP 51900, `10.77.0.0/24`) split-tunneled to
  `192.168.1.254:9999` only, server-side firewall isolation
  (pass WG→game-host, default-deny WG→LAN), a host-side firewall lockdown on
  `192.168.1.254` (accept UDP 9999 only from `10.77.0.0/24`), and one
  hand-enrolled Windows tester peer. This is a records-first handoff: the SDD/
  BDD/validation plan is recorded now; `infra/opnsense/setup_wireguard_game_tunnel.py`,
  `ci/host-firewall-helper.sh`, and live execution evidence are owned by
  Copilot in a follow-up. The existing admin WireGuard server (UDP 51820 /
  `10.14.0.0/24`) is untouched. [Slice 032](slices/032-wgnetstack-netstack-bridge-linux-prototype.md)
  then proves the S2 in-client `wgnetstack` bridge itself: a `native/wgnetstack/`
  Go module embeds `wireguard-go` netstack (real loopback UDP socket, real
  WireGuard handshake against the live OPNsense endpoint, real netstack UDP
  dial to the live game host) with no OS TUN device and no admin rights. The
  existing Godot client's ENet connection was proven to complete through the
  bridge on Linux and reach the full `connected: player spawned` state against
  the live, restarted game server. An earlier run had shown `status: connected`
  without the player-spawned transition and a `receive_monster_position`
  convert error; re-running against a freshly restarted server (and an
  identical direct, no-bridge run against that same server) reproduced neither
  symptom, confirming the gap was a stale server process still executing
  pre-Slice-033 `network_client.gd` (an RPC method-table mismatch), not a
  bridge defect or a genuine type bug in Slice 033's monster-replication code.
  [Slice 034](slices/034-wgnetstack-godot-gdextension-tunnel-integration-linux.md)
  delivers S3a: `native/wgnetstack/gdext/`, a godot-cpp GDExtension that
  registers a `WgNetstack` class (`start(config: Dictionary) -> int`,
  `stop() -> void`) linking a new `cmd/cgoarchive` static build of the same
  bridge logic, plus a `client/network_client.gd` tunnel-mode code path
  (`PROJECT0_TUNNEL`, default off) so the client opens the tunnel in-process
  with no separate probe process.
  [Slice 035](slices/035-wgnetstack-windows-dll-client-repackage.md) delivers
  S3b: the GDExtension cross-compiled to a PE32+ Windows DLL (mingw) and bundled
  in the portable Windows client (`dist/Project0-client-windows-x64-0.7.0-tunnel.zip`),
  so a tester runs one executable with the tunnel available. Slice 035's
  Windows *runtime* spawn-through-tunnel proof is now user-confirmed
  (2026-09-14): a remote Windows tester ran the packaged in-process tunnel
  client and reached the in-world state against the home-hosted authoritative
  server over the public WAN split-tunnel.
  [Slice 048](slices/048-wireguard-enrollment-service.md) delivers the
  invite-code enrollment service's logic (issue 04): a FastAPI service under
  `infra/enrollment/` with single-use CSPRNG invite codes, strict
  client-public-key validation (the private key is never transmitted), `/32`
  allocation from `10.77.0.0/24`, and OPNsense `client/addClient` +
  `service/reconfigure` registration behind an injectable client interface so
  tests never make a live call — fail-closed, so an upstream OPNsense failure
  rolls back with no local allocation and no invite marked redeemed.
  [Slice 049](slices/049-wireguard-revocation-lifecycle.md) delivers the
  revocation/ban lifecycle's logic (issue 06): `RevocationService.revoke()`
  looks up a peer by its public key, calls OPNsense `client/delClient/<uuid>`
  then `service/reconfigure` through the same injectable client interface,
  and only then releases the local `/32` allocation so it re-enters the free
  pool — fail-closed, so an upstream delete/reconfigure failure leaves the
  peer's allocation and OPNsense registration untouched for an operator
  retry, and revoking an unknown or already-revoked key is an idempotent
  no-op. Both slices are service logic proven by automated tests; live
  deployment behind `enroll.valentin.vip`, the real ~25s tunnel-teardown
  timing, and idempotent re-enrollment (reusing an existing peer UUID) remain
  open.
  [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md) delivers
  the first slice of [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md)'s
  auth-gated onboarding follow-up: a loopback-only HTTP endpoint on the login
  authority process (`server/login_loopback_http_endpoint.gd`, `POST
  /internal/verify-and-mint`, bound hard-coded to `127.0.0.1` and never a
  configurable override) that delegates to the existing `LoginGateway`
  (`login()` + `issue_account_assertion()`, no new credential/signing logic),
  synthesizing a per-request negative `peer_id` disjoint from any real ENet
  peer and unconditionally clearing that synthetic session before responding;
  and a new public `POST /login` on the enrollment service
  (`infra/enrollment/app.py`) that calls it through an injectable
  `LoginAuthorityClient` seam (`infra/enrollment/login_client.py`), gaining no
  accounts-DB access or PBKDF2 code of its own. Public `/login`
  rate-limiting/lockout/anti-enumeration is a named, tracked liability
  ([DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)),
  not silently deferred. Slice 088 is delivered and validated on the Linux
  host (see the 2026-09-15 delivery change history entry below).
- Ready basis: all six `.scratch/wan-wireguard/` issues are `resolved`
  (SDD-GAME-WG-001).
- Exit-gate outcome: DT-009 and DT-010 are resolved, and the six real-WAN checks
  in [the F-035 runbook](f035-secure-launcher-validation-runbook.md) passed on
  2026-09-16. P-024 is implemented and safe to advertise; future enrollment
  changes must preserve the existing abuse controls, fail-closed peer lifecycle,
  and no-private-key-transmission invariants.
- Phase: 11. Public game access
- Public seam: `infra/opnsense/setup_wireguard_game_tunnel.py` and
  `ci/host-firewall-helper.sh` (Slice 028); `native/wgnetstack/` producing
  `libwgnetstack.so`/`wgnetstack.dll` with C-exported `wgnetstack_start`/
  `wgnetstack_stop` (Slice 032); `infra/enrollment/service.py`'s
  `EnrollmentService.redeem()`, exposed over HTTP as `POST /redeem` by
  `infra/enrollment/app.py` and over a CLI by `infra/enrollment/cli.py`
  (Slice 048); `infra/enrollment/service.py`'s `RevocationService.revoke()`,
  exposed only over the operator CLI as
  `infra/enrollment/cli.py revoke-peer <public_key>`, deliberately with no
  HTTP admin route (Slice 049); `server/login_loopback_http_endpoint.gd`'s
  `LoginLoopbackHttpEndpoint` (loopback-only `POST /internal/verify-and-mint`)
  and `infra/enrollment/app.py`'s `POST /login`, delegating through
  `infra/enrollment/login_client.py`'s `LoginAuthorityClient` (Slice 088). The
  Godot `.gdextension` binding is separately scoped; the enrollment service's
  nginx/TLS deployment is live. Its public authentication routes remain subject
  to the DT-009 safety gate before self-service onboarding is advertised.
- Validation: Slice 028's acceptance evidence is an external WireGuard peer
  handshake, split-tunnel isolation proof (game host reachable, LAN
  default-denied) from inside the tunnel, the host firewall dropping
  untunneled direct hits to 9999, and one Windows peer connecting the Godot
  client. Slice 032's acceptance evidence is the same Godot client connecting
  through the in-process `wgnetstack` loopback bridge instead; the ENet
  connection handshake through the tunnel is proven on Linux, and the full
  `connected: player spawned` string is observed end to end against the live,
  restarted game server, with an identical direct (no-bridge) run against the
  same server confirming the earlier gap was a stale-server RPC method-table
  mismatch rather than a bridge or monster-replication defect. The Windows DLL
  cross-compile and `.gdextension` packaging (Slice 035) are delivered, and the
  remote-Windows WAN runtime is now user-confirmed (2026-09-14). Slice 048's
  acceptance evidence is `python3 -m pytest infra/enrollment/tests -q`, 39
  passed, exit 0, covering normal redemption, single-use re-redeem rejection,
  pool exhaustion, invalid/expired codes, malformed public keys, and an
  OPNsense-failure rollback that leaves no partial durable state — all against
  a fake OPNsense client and a temp sqlite DB, never a live call. Slice 049's
  acceptance evidence is `python3 -m pytest infra/enrollment/tests -q`, 54
  passed, exit 0 (39 pre-existing plus 15 new), covering revoking an active
  peer (frees its `/32` for reuse), an idempotent no-op on an unknown/already-
  revoked key, and fail-closed rejection on both `delClient` and
  `reconfigure` upstream failures (no local release, retry succeeds once
  healthy) — again all against a fake OPNsense client and a temp sqlite DB.
  The live enrollment deployment, invite-path OPNsense proof, and F-035
  real-WAN runbook are recorded; real tunnel-teardown timing within one
  keepalive interval remains operational follow-up. Slice 088's acceptance evidence is
  `GODOT_BIN=godot bash scripts/run_gut_validation.sh` on the Linux host
  (`validation-summary.json` status `passed`, exit 0, 62/62 scripts, 415/415
  tests, 1511 asserts) and `.venv-enrollment/bin/python -m pytest
  infra/enrollment/tests -q` (70/70, exit 0 on Linux, also reproduced 70/70 on
  Windows) — run in an isolated git worktree of commit d732ff6, since Windows
  cannot run GUT for this repository (the `addons/godot-sqlite` and
  `native/wgnetstack` extensions have no `windows.x86_64` binaries).
- Change history:
  - Date: 2026-09-15
    What changed: Implemented and delivered [Slice 092](slices/092-launcher-login-redeem-assertion.md)
    
—
 the Windows launcher (native/windows_launcher/) now provisions its
    WireGuard peer via self-service login instead of requiring a one-time
    invite from a third device: it prompts for username/password, calls the
    enrollment service POST /login for a signed account assertion, and redeems
    the peer with {assertion, public_key} (the /redeem assertion path from
    Slice 089) before bringing up the tunnel. An explicit --invite-code= /
    PROJECT0_INVITE_CODE remains a fallback. The interactive credential prompt
    is an injectable credentialPrompter seam so tests never block on the
    Windows credential dialog. Validated on Windows via
    go test ./native/windows_launcher/ (12/12, up from 6). Live WAN tunnel
    bring-up is a user-pending real-Windows run. Implemented directly by
    Copilot with explicit user authorization.
    Why: Remove the "obtain an invite from another device" dead-end so a new
    player can go from download to in-world with only their credentials.
    Related work: [Slice 092](slices/092-launcher-login-redeem-assertion.md),
    [Slice 089](slices/089-auth-gated-onboarding-peer-provisioning.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md),
    [F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage)
  - Date: 2026-09-15
    What changed: Implemented and delivered [Slice 093](slices/093-client-https-login-wiring.md)
    — wired `client/account_gate.gd` and `client/character_gate.gd` to the
    HTTPS enrollment flow (Slice 091 `EnrollmentHttpClient`) behind a new
    `NetworkConfig.client_https_login_enabled()` gate
    (`PROJECT0_CLIENT_HTTPS_LOGIN`, defaults on under `PROJECT0_TUNNEL`), and
    added `NetworkClient.perform_https_world_entry()` which connects through the
    tunnel, presents the signed character assertion via the existing
    `establish_session_from_assertion` path, and enters the world. The ENet LAN
    path is unchanged (opt-in gate). This fixes the diagnosed WAN-client
    `Login failed (account_authority_disabled)` defect — the reused pre-split
    client authenticated with ENet register/login RPCs against the
    assertion-only game server (no `AuthService` since Slice 085); the WAN
    client now authenticates over HTTPS before the tunnel. Registration has no
    public HTTPS surface, so it is disabled in WAN mode and filed as
    [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client).
    Validated on the Linux host (commit `230cd06`): GUT 436/436 across 64/64
    scripts, exit 0 (+4 `test_network_config_https_login.gd` cases). Live WAN
    client runtime run is user-pending. Implemented directly by Copilot with
    the user's explicit authorization (Claude CLI rate-limited).
    Why: Make a remote (WAN/tunnel) player able to log in, select a character,
    and enter the world from the packaged Windows client instead of hitting
    `account_authority_disabled`.
    Related work: [Slice 093](slices/093-client-https-login-wiring.md),
    [Slice 091](slices/091-client-https-auth-character-seam.md),
    [ADR 0005](adr/0005-character-selection-over-https.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md),
    [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client)
  - Date: 2026-09-15
    What changed: Implemented and delivered [Slice 091](slices/091-client-https-auth-character-seam.md)
    — `client/enrollment_http_client.gd` (`EnrollmentHttpClient`), the Godot
    client's HTTPS seam consuming the Slice 088 `/login` and Slice 090
    `/characters/*` routes (login + character list/create/select/delete),
    with bounded fail-closed outcomes and a static `resolve_base_url()`.
    Validated on the Linux host (commit `52c78ff`): GUT 432/432 across 63/63
    scripts, exit 0, confirmed across two consecutive runs. Root-cause
    learning recorded: the first draft's real-socket test crashed the suite
    nondeterministically (SIGSEGV, "object freed while a signal is being
    emitted" — an HTTPRequest/Node teardown race); rewritten to test the
    bounded parse/outcome logic purely (synthetic response arrays, no socket),
    which is deterministic. Implemented directly by Copilot with the user's
    explicit authorization. The UI-scene rewiring + live tunnel handoff that
    consumes this seam is the runtime-validated follow-up (Slice 093).
    Why: Give the Godot client a bounded, tested consumer of the HTTPS
    account-and-character surface so the tunnelled flow can obtain a character
    assertion without ENet reach to the login server (9998).
    Related work: [Slice 091](slices/091-client-https-auth-character-seam.md),
    [Slice 090](slices/090-https-character-endpoints.md),
    [ADR 0005](adr/0005-character-selection-over-https.md)
  - Date: 2026-09-15
    What changed: Implemented and delivered [Slice 090](slices/090-https-character-endpoints.md)
    — the server half of ADR 0005 (Option A): character selection over HTTPS.
    `server/login_loopback_http_endpoint.gd` gained four account-scoped
    loopback paths (`/internal/characters/{list,create,delete,select}`) that
    validate a presented account assertion, bind a synthetic negative-peer-id
    session via `establish_session_from_assertion`, run the existing
    `LoginGateway` character ops, and — for select — `issue_character_assertion`,
    then clear the session (no new login-authority character code). The
    enrollment service gained `RealCharacterClient` and `POST /characters/*`
    routes with bounded reason→status mapping. Validated on the Linux host
    (worktree `362387f`): GUT 423/423 across 62/62 scripts (1595 asserts),
    exit 0; enrollment pytest 112/112, exit 0 (also Windows). Implemented
    directly by Copilot with the user's explicit authorization.
    Why: Give the tunnelled auth-gated flow a way to select a character and
    obtain the character assertion world entry needs, without ENet reach to
    the login server (9998).
    Related work: [Slice 090](slices/090-https-character-endpoints.md),
    [ADR 0005](adr/0005-character-selection-over-https.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md),
    [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
  - Date: 2026-09-15
    What changed: Implemented and delivered [Slice 089](slices/089-auth-gated-onboarding-peer-provisioning.md)
    — the assertion-gated `/redeem` path and idempotent per-account peer
    lifecycle (ADR 0004 follow-up B, sub-decision 3). Added a loopback
    `POST /internal/validate-assertion` to `server/login_loopback_http_endpoint.gd`
    (dispatched alongside the Slice 088 verify-and-mint path) backed by a new
    pure `LoginGateway.validate_assertion` (no session bind); the enrollment
    service gained `RealAssertionValidationClient`, an assertion-gated
    `EnrollmentService.redeem_with_assertion` keyed idempotently on `account_id`
    (same key → touch + return the same peer, different key →
    `ACCOUNT_PEER_KEY_MISMATCH`), a nullable-`invite_code` store migration with
    a partial unique index, and an operator `deprovision-stale` CLI reusing
    `RevocationService`. Validated on the Linux host in an isolated worktree of
    commit `65ccc54`: GUT 420/420 across 62/62 scripts (1553 asserts), exit 0;
    enrollment pytest 96/96, exit 0 (also reproduced on Windows). Implemented
    directly by Copilot with the user's explicit authorization while Claude CLI
    was at its session limit.
    Why: Advance the ADR 0004 self-service onboarding chain so a player with a
    signed login assertion can provision a WireGuard peer without an
    operator-minted invite code.
    Related work: [Slice 089](slices/089-auth-gated-onboarding-peer-provisioning.md),
    [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md),
    [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
  - Date: 2026-09-15
    What changed: Validated and delivered [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md)
    on the canonical Linux host (`192.168.1.254`), in an isolated git worktree
    of commit `d732ff6`. `GODOT_BIN=godot bash scripts/run_gut_validation.sh`
    passed — `validation-summary.json` status `passed`, exit 0, 62/62 scripts,
    Run Summary 415 tests, 415 passing, 1511 asserts, 0 failing (includes the
    new `tests/integration/test_login_loopback_http_endpoint.gd`).
    `.venv-enrollment/bin/python -m pytest infra/enrollment/tests -q` passed
    70/70, exit 0 on the Linux host, and was also reproduced on Windows (fresh
    venv, `requirements.txt` + `pytest`) at 70/70, exit 0. Two defects were
    caught and fixed before merge, per `AGENTS.md`'s root-cause gate: (a) a
    non-constant `PackedByteArray` `const` initializer in
    `server/login_loopback_http_endpoint.gd` failed to parse under GDScript
    2.0 (caught by `godot --headless --check-only`, masked on Windows by the
    unrelated environmental native-lib failure) — fixed by changing it to an
    instance `var`; (b) the same file `preload`ed `client/network_client.gd`
    solely to read a TTL constant, a server→client dependency inversion
    against `CLAUDE.md`'s boundary rule — caught in Copilot review and fixed
    by adding a local server-owned constant.
    Why: Close out Slice 088 with real validation evidence rather than the
    pending placeholders the implementation handoff left, per this record's
    mandatory implementation-sync rule.
    Related work: [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md),
    [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
    Validation: See above — GUT 415/415 (62/62 scripts, 1511 asserts), exit 0;
    enrollment pytest 70/70, exit 0 (Linux and Windows).
  - Date: 2026-09-14
    What changed: Delivered Slice 048, the invite-code enrollment service's
    logic and full automated test coverage (39/39 passing), against issue 04's
    resolved design. Single-use invites, strict public-key validation, `/32`
    pool allocation, and an injectable OPNsense client keep every rejection
    path (bad/expired/redeemed code, malformed key, exhausted pool, upstream
    failure) side-effect-free.
    Why: Growing Phase 13 beyond the single hand-enrolled Slice 028 tester
    peer requires a self-serve, single-use, auditable enrollment path with no
    partial state on failure, per issue 04's resolved design.
    Related work: [Slice 048](slices/048-wireguard-enrollment-service.md)
    Validation: `python3 -m pytest infra/enrollment/tests -q` passed 39/39,
    exit 0; `scripts/check_record_sync.sh` passed with 0 errors and 6
    pre-existing warnings, exit 0. No `.gd` files changed, so the GUT suite
    was not run.
  - Date: 2026-09-14
    What changed: Recorded the user-confirmed WAN runtime proof — a remote
    Windows tester ran the packaged in-process tunnel client and reached the
    in-world state over the public WAN split-tunnel, closing Slice 035's
    tester-owned open item.
    Why: WAN connectivity is the core Phase 13 milestone; the record must
    reflect the confirmed runtime evidence (same basis as DT-003/DT-004
    user-confirmed GUI/LAN runs). Invite enrollment (issue 04) and revocation
    (issue 06) remain the open Phase 13 gate items.
    Related work: [Slice 035](slices/035-wgnetstack-windows-dll-client-repackage.md)
    Validation: User-confirmed remote-Windows WAN run (2026-09-14); no automated
    GUT seam covers a live WAN hop.
  - Date: 2026-09-14
    What changed: Delivered Slice 049, the peer revocation/ban lifecycle's
    logic and full automated test coverage, against issue 06's resolved
    design. `RevocationService.revoke()` deletes the peer on OPNsense
    (`delClient` + `reconfigure`) before releasing its local `/32`
    allocation, keyed on the peer's public key; every rejection path
    (`UPSTREAM_DELETE_FAILED`) is fail-closed with no local mutation, and
    revoking an unknown or already-revoked key is an idempotent
    `ALREADY_ABSENT` no-op. Revocation is CLI/operator-only
    (`infra/enrollment/cli.py revoke-peer`); no HTTP admin route was added.
    Idempotent re-enrollment (reusing an existing peer UUID) was deliberately
    deferred as a documented follow-up.
    Why: A ban must actually revoke tunnel access — an enrollment path with
    no matching revocation path lets a banned player keep working WireGuard
    access and leaks `/32` addresses forever, per issue 06's resolved design.
    Related work: [Slice 049](slices/049-wireguard-revocation-lifecycle.md)
    Validation: `python3 -m pytest infra/enrollment/tests -q` passed 54/54
    (39 pre-existing, 15 new), exit 0; `scripts/check_record_sync.sh` passed
    with 0 errors and 6 pre-existing warnings, exit 0. No `.gd` files
    changed, so the GUT suite was not run.
  - Date: 2026-09-15
    What changed: Recorded [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md),
    a records-first SDD/BDD/TDD plan for [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md)'s
    first onboarding follow-up: a loopback-only (`127.0.0.1`) HTTP/JSON seam on
    the login process (`POST /internal/verify-and-mint`, reusing
    `LoginGateway.login`/`issue_account_assertion` verbatim, no new credential
    or signing logic) plus a public `POST /login` on the enrollment service
    that delegates to it via a new injectable `LoginAuthorityClient` seam
    mirroring the existing `OpnsenseWireguardClient` pattern. No code was
    written — this is planning only, pending Copilot design review.
    Why: ADR 0004 moves authentication in front of the tunnel so self-service
    login (no invite-code delivery) can provision a peer and hand the same
    signed assertion to the assertion-only game server; the login authority
    must stay the sole credential/signing owner while the enrollment service
    gains a public auth surface it did not have before.
    Related work: [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md)
    Validation: None yet — records-first handoff. No build/test command was
    run. The slice record names the exact focused/full validation commands
    (`scripts/run_gut_validation.sh`, `python3 -m pytest infra/enrollment/tests -q`)
    the implementation handoff must run and report against.
  - Date: 2026-09-15
    What changed: Implemented [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md)
    per its records-first plan: `server/login_loopback_http_endpoint.gd`
    (`LoginLoopbackHttpEndpoint`, a strict bounded HTTP/1.1 parser over
    `TCPServer`/`StreamPeerTCP`, hard-coded to `127.0.0.1`, delegating to the
    existing `LoginGateway.login()`/`issue_account_assertion()` with a
    synthetic negative `peer_id` and an unconditional `clear_session`), wired
    from `server/login_server_main.gd`; `shared/network_config.gd`'s
    `resolve_login_http_port()` (default `9997`); and on the enrollment side,
    `infra/enrollment/login_client.py`'s `LoginAuthorityClient`/
    `RealLoginAuthorityClient`/`LoginAuthorityError`, new `EnrollmentConfig`
    fields, and `infra/enrollment/app.py`'s `POST /login`. Filed
    [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
    for the deferred public-`/login` rate-limiting/lockout/anti-enumeration
    liability named in the plan. No git operations and no build/test/validation
    command were run by this handoff; Copilot runs GUT + pytest next.
    Why: Completes the code side of the plan's SDD/BDD/TDD scope so the next
    handoff only has to run and report validation evidence, keeping the
    records-first plan and its implementation as two separately reviewable
    steps per the repository's delivery workflow.
    Related work: [Slice 088](slices/088-auth-gated-onboarding-login-delegation.md),
    [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md),
    [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
    Validation: Not run by this handoff (see the slice record's Validation
    evidence section for the exact pending commands and placeholders).
- Related work: [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md),
  [ENet netstack bridging](../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md),
  [GDExtension netstack prototype](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md),
  [OPNsense infra automation](../.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md),
  [enrollment invite service](../.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md),
  [host firewall lockdown](../.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md),
  [revocation and ban lifecycle](../.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md),
  [Slice 028](slices/028-wireguard-remote-access-infrastructure-foundation.md)

### IP-023: Basic monster combat

- Status: `Implemented`
- Feature: Server-authoritative "basic monsters" the player can fight — a flat
  HP/damage/death model now, with a detect/chase/attack AI and spawning to
  follow.
- Problem solved: The world has a stationary target dummy but no actual enemy
  with health that can be defeated; the starting area needs something to fight.
- How it solves the problem so far: Slice 020 adds `shared/monster_contracts.gd`
  (`MonsterContracts`) — a provisional flat `MonsterCombatState`
  (`current_hp`/`max_hp`/`target_id`, `apply_damage` clamped at 0 and reporting
  the death transition exactly once, `is_dead`) with fixed `MAX_HP`/`DAMAGE_PER_HIT`
  constants (a deterministic 3 hits to defeat) — and a new `COMBAT_EVENT_DEATH`
  kind on `shared/combat_contracts.gd` reusing the existing `CombatEvent` shape.
  Slice 021 adds `server/server_monster_state.gd`, the authoritative
  detect → chase → windup → attack → recovery state machine with a dodge-able
  telegraph, reuse of the shared reach/arc hit test, and per-transition/attack/
  death telemetry. Slice 022 adds `server/server_monster_manager.gd`, which
  spawns one monster per town spawn point (authored outside the town wall),
  drives them each server frame against the nearest player, and respawns
  defeated monsters after a cooldown at a position clamped to stay outside the
  town. Slice 029 wires a player's already-accepted authoritative melee hit to
  monster damage and death: `ServerPlayerState`'s ACTIVE-phase hit test is
  generalized to also check every currently-living monster (injected via
  `set_monster_manager`, duck-typed on `.position` alongside the existing
  target dummies) and still only emits the existing `COMBAT_EVENT_HIT`;
  `ServerMonsterManager.receive_player_hit` is the sole seam that applies
  `DAMAGE_PER_HIT` and reports a defeat, and `server_main.gd` routes that HIT
  to it and broadcasts an attacker-attributed `COMBAT_EVENT_DEATH` over the
  same existing channel when it lands the killing blow. Monsters are now fully
  fightable and defeatable server-side. Slice 033 closes the remaining
  implementation gap: `client/monster.gd`/`client/monster.tscn` is a purely
  cosmetic per-living-monster node — spawned, positioned, and despawned only in
  reaction to server broadcasts, and reacting visually to the existing
  `COMBAT_EVENT_HIT`/`COMBAT_EVENT_DEATH` events — so monsters are now visible
  to and fightable by players, not just authoritatively simulated. It decides
  nothing itself: no damage, hit, death, or respawn logic runs on the client.
  With Slice 033 in place the feature is complete: headless GUT coverage and a
  headless `connected: player spawned` connect proof pass, and interactive GUI
  visual/fight confirmation was obtained on 2026-09-13 — a human ran the
  graphical client against the live server and saw the monster render, chase,
  flash on each hit, die on the third hit, and respawn. IP-023 is
  `Implemented`.
- Phase: 12. Authoritative runtime and action input
- Implementation slices: [Slice 020](slices/020-monster-hp-damage-death.md), [Slice 021](slices/021-monster-ai-state-machine.md), [Slice 022](slices/022-monster-spawning-and-respawn.md), [Slice 029](slices/029-authoritative-monster-melee-damage.md), [Slice 033](slices/033-client-monster-replication-and-rendering.md)
- Public seam: `shared/monster_contracts.gd`
  (`MAX_HP`, `DAMAGE_PER_HIT`, `WINDUP_TICKS`, `ATTACK_ACTIVE_TICKS`,
  `RECOVERY_TICKS`, `DETECTION_RADIUS_YARDS`, `CHASE_SPEED_YARDS_PER_SEC`,
  `MONSTER_REACH_YARDS`, `MONSTER_ARC_DEGREES`, `PHASE_*`, `MonsterCombatState`,
  `default_monster`, `monster_attack_archetype`), `shared/combat_contracts.gd`
  (`COMBAT_EVENT_DEATH`), `server/server_monster_state.gd`
  (`advance`, `receive_damage`, `phase_changed`, `attack_resolved`, `died`),
  `server/server_monster_manager.gd` (`advance_all`, `monster_at`,
  `monster_count`, `living_count`, `living_targets`, `receive_player_hit`,
  `monster_died`, `monster_respawned`),
  `server/server_player_state.gd` (`set_monster_manager`, its generalized
  `_perform_hit_test`), `server/starting_town_hub_fixture.gd` (spawn points
  outside the town wall), `client/monster.gd`/`client/monster.tscn`
  (`spawn_monster_representation`, `receive_monster_position`,
  `despawn_monster_representation`, hit/death reaction), `client/network_client.gd`
  (monster replication RPCs), `server/server_main.gd` (monster broadcast
  wiring).
- Validation: See [Slice 020](slices/020-monster-hp-damage-death.md),
  [Slice 021](slices/021-monster-ai-state-machine.md),
  [Slice 022](slices/022-monster-spawning-and-respawn.md),
  [Slice 029](slices/029-authoritative-monster-melee-damage.md), and
  [Slice 033](slices/033-client-monster-replication-and-rendering.md) for exact
  commands and results (Slice 029: 11/11 manager + 9/9 authoritative-melee
  focused tests, 177/177 full suite, exit 0; Slice 033: 4/4 unit +
  7/7 integration focused tests, full gate `scripts/run_gut_validation.sh`
  26/26 scripts, 199/199 tests, 793 asserts, exit 0, plus a headless
  `connected: player spawned` connect proof and a clean monster-broadcast
  runtime run with zero RPC errors; interactive GUI visual/fight confirmation
  was obtained 2026-09-13, human-confirmed).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Basic Monsters map](../.scratch/basic-monsters/map.md),
  [issue 01](../.scratch/basic-monsters/issues/01-hp-damage-death-model.md),
  [issue 02](../.scratch/basic-monsters/issues/02-monster-state-machine-with-telegraph.md),
  [issue 03](../.scratch/basic-monsters/issues/03-monster-spawn-points-from-town-schema.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 020 — the provisional flat monster
    HP/damage/death contract and the shared `COMBAT_EVENT_DEATH` kind, the first
    Basic Monsters slice.
    Why: Give the detect/chase/attack monster AI (next slice) a validated,
    bounded combat contract to build on before any runtime or spawning.
    Related work: [Slice 020](slices/020-monster-hp-damage-death.md)
    Validation: See Slice 020 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 021 — the authoritative detect → chase →
    windup → attack → recovery state machine (`server/server_monster_state.gd`)
    with a dodge-able attack telegraph, reuse of the shared reach/arc hit test,
    per-transition/attack/death telemetry signals, and a binding
    `WINDUP_TICKS >= player windup` fairness regression test.
    Why: Give the monster real, readable authoritative behavior before wiring
    spawning and the server tick loop.
    Related work: [Slice 021](slices/021-monster-ai-state-machine.md)
    Validation: See Slice 021 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 022 — `server/server_monster_manager.gd`,
    which spawns one monster per town spawn point (authored outside the town
    wall in the hub fixture), drives their AI each server frame against the
    nearest player, and respawns defeated monsters after a cooldown at a
    position clamped to stay outside the town, wired into the server's
    `physics_frame` loop with death/respawn telemetry.
    Why: Complete the Basic Monsters map's spawning/respawn ticket server-side,
    honoring the caveat that monsters spawn outside the town boundary.
    Related work: [Slice 022](slices/022-monster-spawning-and-respawn.md)
    Validation: See Slice 022 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 029 — wired a player's accepted
    authoritative melee hit to monster damage and death. Generalized
    `ServerPlayerState`'s ACTIVE-phase hit test to also check every
    currently-living monster (via a new `ServerMonsterManager.living_targets()`
    snapshot, duck-typed on `.position` alongside the existing target dummies),
    added `ServerMonsterManager.receive_player_hit` as the sole seam that
    applies `DAMAGE_PER_HIT` and reports a defeat, and extended
    `server_main.gd`'s existing HIT-broadcast routing to also broadcast an
    attacker-attributed `COMBAT_EVENT_DEATH` over the same channel when a hit
    lands the killing blow. Monster mutation stays single-owned by
    `ServerMonsterManager`; `ServerPlayerState` still only resolves geometry.
    Why: Complete the server-authoritative half of the "make monsters visible
    to and fightable by players" boundary recorded in Slice 022's next
    boundary, so monsters are now genuinely damageable and defeatable in the
    live server loop; client rendering follows as a later slice.
    Related work: [Slice 029](slices/029-authoritative-monster-melee-damage.md)
    Validation: See Slice 029 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 033 — client-side monster replication and
    rendering. Added `client/monster.gd`/`client/monster.tscn`, a purely
    cosmetic node per living monster, spawned/positioned/despawned only by
    server broadcasts and reacting visually to the existing
    `COMBAT_EVENT_HIT`/`COMBAT_EVENT_DEATH` events, plus the corresponding
    monster-replication RPCs on `client/network_client.gd` and broadcast wiring
    on `server/server_main.gd`. The client decides nothing: no damage, hit,
    death, or respawn logic runs outside the server.
    Why: Close the "make monsters visible to and fightable by players" boundary
    left open by Slice 029, so the server-authoritative monster lifecycle
    (Slices 020-022, 029) finally has a visible, fightable client presentation.
    Related work: [Slice 033](slices/033-client-monster-replication-and-rendering.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
    -gselect=test_monster_node -gexit` passed 4/4 tests, 4 asserts, exit 0;
    `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
    -gselect=test_monster_replication -gexit` passed 7/7 tests, 12 asserts,
    exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`)
    passed 26/26 scripts, 199/199 tests, 793 asserts, exit 0. Separately, a
    headless client run reached `connected: player spawned` and observed 4
    spawned monsters with zero `Cannot convert argument .. int to String`
    monster-position RPC errors against a freshly restarted server on current
    code. Interactive GUI visual/fight confirmation (a human seeing the
    monster render, hitting it three times to kill it, and watching it
    respawn) was obtained on 2026-09-13 (human-confirmed), completing the
    slice's runtime evidence.
  - Date: 2026-09-13
    What changed: IP-023 moved to `Implemented`. The Slice 033 interactive GUI
    visual/fight confirmation was obtained — a human ran the graphical client
    against the live server and saw the dark-red monster render, chase, flash
    on each melee hit, die on the third hit, and respawn — completing the
    "visible to and fightable by players" boundary on top of the green headless
    suite (26/26 scripts, 199/199 tests, 793 asserts, exit 0).
    Why: Final acceptance evidence for the feature was captured, so its status
    reflects delivered reality.
    Related work: [Slice 033](slices/033-client-monster-replication-and-rendering.md)
    Validation: Full gate green (199/199) plus the human GUI confirmation above.

### IP-008: Just-in-time sector generation

- Status: `Implemented`
- Feature: When a player reaches an ungenerated sector boundary, the server requests sector content asynchronously without blocking the live multiplayer loop.
- Problem solved: The game needs expandable world content without a synchronous generation pause.
- How it solves the problem: Slice 009 adds `server/provisional_sector_generator.gd`, Slice 046 connects authoritative sector transitions to that non-blocking request seam, and Slice 047 canonicalizes successful results before reliable replication. World mutation is a separate P-013 capability.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 009](slices/009-provisional-sector-generation.md), [Slice 046](slices/046-sector-boundary-detection.md), [Slice 047](slices/047-jit-result-canonicalization-replication.md)
- Public seam: `server/provisional_sector_generator.gd` (`request_provisional_sector`, `get_status`, `get_correlation_id`, `get_provisional_result`, `provisional_sector_ready`).
- Validation: Slices 046-047 focused validation passed; the full configured GUT suite passed 282/282 tests across 39/39 scripts and 1073 assertions, exit 0.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Provisional sector generation](../.scratch/game-vision/issues/16-provisional-sector-generation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 009 — a request-acceptance and in-memory
    provisional-outcome seam in front of the unchanged Slice 008
    `SectorBlueprintService`. Renamed from `P-008` to `IP-008` because a live,
    validated public seam now exists, even though boundary detection remains
    unbuilt.
    Why: Close the non-blocking request-orchestration half of just-in-time
    sector generation before boundary detection or Canon persistence work.
    Related work: [Slice 009](slices/009-provisional-sector-generation.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/integration -gselect=test_provisional_sector_generation
    -gexit` passed 9/9 tests, 32 assertions, exit 0; the full configured GUT
    suite (`scripts/run_gut_validation.sh`) passed 23/23 tests, 70 assertions,
    exit 0.
  - Date: 2026-09-14
    What changed: Added the finalization boundary that canonicalizes successful
    provisional results and replicates only stored Canon to connected clients.
    Why: Prevent provisional or conflicting LLM output from becoming visible
    world state.
    Related work: [Slice 047](slices/047-jit-result-canonicalization-replication.md), [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: Coordinator test ran after forced import; unit suite passed 188/188 tests, exit 0; server check-only passed, exit 0; full GUT telemetry passed 282/282 tests across 39/39 scripts and 1073 assertions, exit 0.

### IP-015: Authoritative action input

- Status: `In Progress`
- Feature: Client action input, including sword slashing, is validated and resolved by the authoritative server while the client presents responsive feedback.
- Problem solved: Action gameplay must remain responsive without allowing clients to decide combat outcomes.
- How it solves the problem so far: Slice 012 adds the first authoritative action: a bounded melee `ActionIntent`/`ActionResolution`/`CombatEvent` contract (`shared/combat_contracts.gd`), a per-peer fixed-60Hz-tick `WINDUP -> ACTIVE -> RECOVERY -> IDLE` state machine with monotonic sequence validation, idempotent replay, and bounded rejection codes (`server/server_player_state.gd`), authoritative locomotion throttling during WINDUP/RECOVERY, and a deterministic vector reach/arc hit test against a server-owned stationary `TargetDummy` that broadcasts a replicated `CombatEvent.HIT` (`server/server_main.gd`). The client captures attack input, predicts the disposable windup/recovery locomotion slowdown, and reconciles on rejection (`client/player.gd`); a client-side target dummy renders a flash/wobble reaction to the authoritative hit (`client/target_dummy.gd`). Slice 013 adds a purely cosmetic strike-line telegraph (`client/melee_strike_visual.gd`): the attacker's own client shows it during its disposable predicted `ACTIVE` window (hiding immediately on rejection), and a new server-broadcast `melee_swing_started` signal (`server/server_player_state.gd`, relayed by `server/server_main.gd`) lets every other connected peer's `RemotePlayer` mirror an equivalent timed line, all without any client asserting a hit or altering reach/arc truth. Only melee strikes against one stationary dummy exist so far — no damage/HP, other action kinds, moving targets, or PvP — so the feature remains `In Progress` rather than `Implemented`.
- Phase: 12. Authoritative runtime and action input
- Implementation slices: [Slice 012](slices/012-authoritative-melee-strike.md), [Slice 013](slices/013-melee-strike-visual-indicator.md), [Slice 141](slices/141-heavy-strike-action.md)
- Public seam: `shared/combat_contracts.gd`, `server/server_player_state.gd` (`apply_action_intent`, `set_target_dummies`, `action_resolved`, `combat_event_emitted`, `melee_swing_started`), `server/server_main.gd` (target dummy spawn and RPC relay, `melee_swing_started` relay), `client/network_client.gd` (`submit_action_intent`, `receive_action_resolution`, `receive_combat_event`, `receive_melee_swing_started`), `client/player.gd`, `client/target_dummy.gd`, `client/remote_player.gd`, `client/melee_strike_visual.gd`.
- Validation: See [Slice 012](slices/012-authoritative-melee-strike.md) and [Slice 013](slices/013-melee-strike-visual-indicator.md) for exact commands and results (Slice 012: 21/21 focused unit tests, 4/4 focused integration tests, a real two-process ENet smoke test, and 48/48 full suite, exit 0; Slice 013: 9/9 focused unit tests, 23 assertions, and 57/57 full suite, 161 assertions, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [melee-combat map](../.scratch/melee-combat/map.md), [issue 01](../.scratch/melee-combat/issues/01-define-first-melee-exchange.md), [issue 02](../.scratch/melee-combat/issues/02-set-melee-action-authority-and-lifetime.md), [issue 03](../.scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md), [issue 04](../.scratch/melee-combat/issues/04-choose-first-target-and-hit-rule.md), [issue 05](../.scratch/melee-combat/issues/05-set-first-melee-slice-boundary-and-evidence.md)
- Change history:
  - Date: 2026-09-18
    What changed: Delivered Slice 141 — a SECOND authoritative action kind,
    `HEAVY_STRIKE`, advancing the Phase 12 exit gate's "server resolves a bounded
    action set beyond the first melee seam". `shared/combat_contracts.gd` adds the
    kind, a data-driven `HEAVY_GREATSWORD` archetype (windup 12, reach 3.0 yd, arc
    120°, heavier locomotion, 3 targets), and `is_supported_action_kind` /
    `archetype_for_action`; `server/server_player_state.gd` accepts any supported
    kind and selects its archetype per swing, so the whole existing machine +
    reach/arc test resolves both kinds. Melee behaviour is unchanged.
    Why: Prove the action-resolution seam generalizes beyond one kind, via the
    charted data-driven-archetype extension (melee issue 03).
    Related work: [Slice 141](slices/141-heavy-strike-action.md), melee-combat map.
    Validation: full cumulative GUT tree on Linux host `okami` (temp-tree) — 97
    scripts / 712 tests / 712 passing, exit 0; new `test_heavy_strike_action` 7/7
    with the melee regression unchanged (`test_melee_combat_contracts` 21/21,
    integration `test_authoritative_melee_strike` 9/9). IP-015 stays `In Progress`:
    client input binding, damage differentiation, and PvP remain.
  - Date: 2026-09-12
    What changed: Implemented Slice 012 — the first authoritative melee-strike action, its shared contracts, server state machine, client prediction/reconciliation, and target dummy. Renamed from `P-015` to `IP-015` because a live, validated public seam now exists, even though only one action kind and one stationary target exist so far.
    Why: Close the melee-combat decision map's (`.scratch/melee-combat/`) first implementation slice before any damage, progression, or additional action kinds.
    Related work: [Slice 012](slices/012-authoritative-melee-strike.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_melee_combat_contracts -gexit` passed 21/21 tests, 54 assertions, exit 0; `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_authoritative_melee_strike -gexit` passed 4/4 tests, 14 assertions, exit 0; `godot --headless -s scripts/test_authoritative_melee_strike_e2e.gd` (real two-process ENet) printed `ALL PASS`, exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`) passed 48/48 tests, 138 assertions, exit 0.
  - Date: 2026-09-12
    What changed: Implemented Slice 013 — a purely cosmetic melee strike-line visual indicator for both the attacking client (timed from its existing disposable predicted phase) and every remote observer (timed from a new server-broadcast `melee_swing_started` signal). Added no new authoritative state, `ActionIntent`/`ActionResolution` fields, or hit-test logic.
    Why: Slice 012 proved authoritative hit registration but gave neither the attacker nor observers any visible read on the swing window; this closes that presentation gap without touching combat authority.
    Related work: [Slice 013](slices/013-melee-strike-visual-indicator.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_melee_strike_visual_indicator -gexit` passed 9/9 tests, 23 assertions, exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`) passed 57/57 tests, 161 assertions, exit 0.

### IP-001: Server-authoritative networked multiplayer

- Status: `Implemented`
- Feature: Multiple players see and affect each other's Player nodes in the
  same world in real time.
- Problem solved: The first playable slice is single-player/local only, but
  the product goal is a networked multiplayer game.
- How it solves the problem: Adopt Godot 4's High-Level Multiplayer API with
  the server as the authority for Player position and world state; client
  sends input, server simulates and reconciles prediction.
- Phase: 2. Network connection proof (also advances Phase 4, Phase 5, and Phase 7)
- Implementation slices: [Slice 002](slices/002-client-connects-to-server.md),
  [Slice 004](slices/004-authoritative-player-movement.md),
  [Slice 005](slices/005-prediction-reconciliation.md),
  [Slice 007](slices/007-multi-peer-player-replication.md)
- Public seam: `server/server_main.gd` (`_start_server`,
  `_on_peer_connected`), `server/server_player_state.gd`
  (`start_for_peer`, `apply_input_intent`), `client/network_client.gd`
  (`connect_to_server`, `status`, `spawn_local_player_representation`,
  `submit_input_intent`, `receive_authoritative_position`), and (Slice 005)
  `client/player.gd` (`_on_authoritative_position_received`) and
  `client/networked_player_input.gd` (`_on_authoritative_position_received`).
- Validation: See [Slice 002](slices/002-client-connects-to-server.md),
  [Slice 004](slices/004-authoritative-player-movement.md), and
  [Slice 005](slices/005-prediction-reconciliation.md) for the exact headless
  commands and results.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [game-vision issue 03](../.scratch/game-vision/issues/03-define-authority-model.md),
  [game-vision issue 07](../.scratch/game-vision/issues/07-connect-client-to-server.md),
  [game-vision issue 09](../.scratch/game-vision/issues/09-authoritative-player-movement.md),
  [game-vision issue 11](../.scratch/game-vision/issues/11-prediction-reconciliation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 005 — the red local Player now tags each
    locally sent input intent with a monotonically increasing sequence
    number while still moving immediately from local input every tick with
    no wait on the network; the server acknowledges the latest processed
    sequence in its authoritative snapshots; the red Player reconciles by
    discarding acknowledged pending inputs, snapping to the authoritative
    position, and replaying only the still-unacknowledged inputs; and the
    blue NetworkedPlayer now smooths toward each authoritative snapshot at a
    bounded speed instead of snapping to it, only snapping directly for an
    extreme (post-spawn-scale) delta. Server authority over the resulting
    position is unchanged.
    Why: User-directed Phase 5 prediction/reconciliation proof, recorded in
    `.scratch/game-vision/issues/11-prediction-reconciliation.md`.
    Related work: [Slice 005](slices/005-prediction-reconciliation.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
    [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result),
    [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
    Validation: See Slice 005 validation section.
  - Date: 2026-09-11
    What changed: Implemented Slice 004 — the client's blue `NetworkedPlayer`
    now reports directional WASD input intent to the server every physics
    tick; the server owns a `ServerPlayerState` node per connected Player,
    integrates its position at a fixed speed on its own tick, and RPCs the
    resulting authoritative position back to the owning client, which
    applies it directly with no prediction or interpolation. The existing
    red local Player and its client-side movement are unchanged.
    Why: User-directed Phase 4 authoritative movement proof, recorded in
    `.scratch/game-vision/issues/09-authoritative-player-movement.md`.
    Related work: [Slice 004](slices/004-authoritative-player-movement.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
    [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result),
    [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
    Validation: See Slice 004 validation section.
  - Date: 2026-09-11
    What changed: Implemented Slice 002 — a headless ENet server entry path,
    a client connection path with visible status, and a visible networked
    Player representation spawned on successful connection. Status moved
    from `Planned` (P-001) to `In Progress` (IP-001) because the connection
    seam is now live and validated, but movement synchronization and
    authority handoff are still unbuilt.
    Why: User-directed Phase 2 network connection proof, recorded in
    `.scratch/game-vision/issues/07-connect-client-to-server.md`.
    Related work: [Slice 002](slices/002-client-connects-to-server.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
    [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result)
    Validation: See Slice 002 validation section.

## Implemented Features

### F-026: Organic districted starting city

- Status: `Implemented`
- Feature: The starting town is a large, organic, districted, walled city (on
  the scale/feel of EverQuest's Qeynos or FF7's Midgar) whose layout is
  ultimately LLM-generated but always validated so the required structures
  (10-house pool, Smithy, Armor Shop, Inn) exist — replacing the small Slice 016
  square hub.
- Problem solved: The Slice 016 hub is far too small and too square to feel like
  a town; the world needs a believably large, non-grid starting city with
  gates, districts, and roads, while still guaranteeing the fixed set of
  buildings every run.
- How it solves the problem: Slice 023 enlarges the hand-authored hub
  fixture into an organic octagon town (a ±16 square with corners clipped along
  `|x| + |y| <= 22`) enclosed by a wall with a southern gate, radial corridor
  avenues, and a central plaza, with the 13 structures re-placed into a northern
  residential district and a southern trade quarter. It renders through the
  existing per-tile geometry pipeline (`MAX_TILE_COUNT` raised to 2048 to fit
  the ~869-tile town), and the monster exclusion + ground plane grow with it so
  monsters stay in the fields outside the bigger walls. Slice 024 then replaced
  the per-tile geometry with a merged scalable pass (one merged `ArrayMesh` per
  ground kind, one merged `Walls` body) so town size is no longer bounded by the
  physics body count (resolving DT-008). Slice 025 added the schema-v3 organic
  vocabulary (gate/plaza/path/grass/water tiles + church/tavern/item_shop/well)
  and enriched the hub to use it, and Slice 026 added the `TownLayoutProvider`
  guarantee — the LLM proposes a town, the server validates it and requires the
  fixed structures, else falls back to the fixture (never an unusable town).
  Slice 031 grew the village to ~3x area (radius 30) and added 10 villager
  homes (`npc_house`) plus the village leader's hall (`village_hall`) for a
  rural-village feel. Slice 052 wired LLM generation on at boot behind a
  default-off `PROJECT0_LLM_TOWN_AT_BOOT` flag — when set, the server awaits
  `TownLayoutProvider.request_town()` before opening its socket and falls back
  to the fixture on any failure; unset boots exactly as before. Slice 053
  replaced the hard-coded monster exclusion constant with
  `ServerMonsterManager.town_exclusion_half_extent()`, a pure derivation from
  the validated blueprint's actual tile bounds (plus a fixed margin), wired at
  boot in `server_main.gd` — so any town size keeps monsters just outside its
  walls automatically. No items remain; the feature is fully `Implemented`.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 023](slices/023-organic-districted-town.md), [Slice 024](slices/024-scalable-geometry-pass.md), [Slice 025](slices/025-organic-vocabulary.md), [Slice 026](slices/026-llm-town-generation.md), [Slice 031](slices/031-bigger-village-npc-leader-housing.md), [Slice 052](slices/052-f026-llm-town-at-boot.md), [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md)
- Public seam: `server/starting_town_hub_fixture.gd`
  (`blueprint()` generating the radius-30 organic octagon via `_in_town`/`_tile_kind`
  with main + secondary streets, 28 `_STRUCTURES` incl. `npc_house`/`village_hall`,
  ±38 `_SPAWN_POINTS`),
  `shared/sector_blueprint_schema.gd` (`MAX_TILE_COUNT` 4096, `MAX_COORDINATE_ABS` 48,
  `npc_house`/`village_hall` in the v3 vocabulary),
  `server/town_layout_provider.gd` (`resolve`, `meets_required_structures`,
  `request_town`, `default_town_prompt`, `llm_at_boot_enabled`,
  `resolve_boot_town`),
  `server/server_monster_manager.gd` (`town_exclusion_half_extent()` derived
  exclusion, `TOWN_EXCLUSION_MARGIN_YARDS` 2.0, `TOWN_EXCLUSION_HALF_EXTENT` 32.0
  fallback/default),
  `client/gameplay.tscn` (100×100 `FlatPlane`),
  `server/server_main.gd` (`_start_server()` boot wiring behind
  `PROJECT0_LLM_TOWN_AT_BOOT`, and deriving/logging the monster exclusion
  half-extent from the validated town blueprint).
- Validation: See [Slice 023](slices/023-organic-districted-town.md) for exact
  commands and results (8/8 fixture + 7/7 manager + 4/4 replication focused
  tests, 140/140 full suite, exit 0), and [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md)
  for the final item's validation (16/16 focused, 315/315 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Organic LLM Village map](../.scratch/organic-village/map.md),
  supersedes [F-019](#f-019-starting-town-hub-fixture),
  [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size) (resolved by Slice 024)
- Change history:
  - Date: 2026-09-14
    What changed: Implemented Slice 053 — replaced the hard-coded
    `TOWN_EXCLUSION_HALF_EXTENT = 32.0` constant with
    `ServerMonsterManager.town_exclusion_half_extent(blueprint)`, a pure
    derivation (`max over tiles of max(|x|, |y|)` plus a
    `TOWN_EXCLUSION_MARGIN_YARDS` margin) from the validated town blueprint's
    actual tile bounds, wired at boot in `server_main.gd`. The constant remains
    only as the documented fallback/default. F-026 moved `In Progress` ->
    `Implemented`; no items remain.
    Why: F-026's last remaining item — any town size (not just the current
    fixture) should keep monsters just outside its walls automatically, rather
    than relying on a hand-tuned constant that must be manually updated for
    every future town size.
    Related work: [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md)
    Validation: See Slice 053 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 023 — enlarged the hub fixture into an
    organic octagon districted town (gate, radial avenues, central plaza,
    residential + trade districts), raised `MAX_TILE_COUNT` to 2048, grew the
    monster exclusion to 18.0 and the ground plane to 60×60, and updated the
    fixture spawn-outside test to the new town outline. Renders through the
    existing per-tile pipeline.
    Why: Deliver an immediately visible, substantially larger, non-square
    starting town (the first Organic Village slice) and the reliable fallback
    base for later LLM generation.
    Related work: [Slice 023](slices/023-organic-districted-town.md)
    Validation: See Slice 023 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 024 — the scalable geometry pass. Ground
    tiles now render as one merged `ArrayMesh` per kind (body-free), walls as
    greedy row-merged colliders under one shared `Walls` body, so the town
    renders with a single physics body regardless of tile count.
    Why: Resolve DT-008 and decouple rendered city size from the physics body
    count, unblocking the schema-v3 vocabulary/scale and LLM-generation slices.
    Related work: [Slice 024](slices/024-scalable-geometry-pass.md)
    Validation: See Slice 024 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 025 — enriched the hub to the schema-v3
    organic vocabulary: a gated wall, central plaza, path avenues, a grass ring,
    an ornamental pond, and four flavor buildings (church, tavern, item shop,
    well), 17 structures total.
    Why: Make the starting town read like an organic town, the visible payoff of
    the Organic Village effort.
    Related work: [Slice 025](slices/025-organic-vocabulary.md)
    Validation: See Slice 025 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 026 — `server/town_layout_provider.gd`, the
    LLM town-layout guarantee: the model proposes a town, the server validates
    it via the schema and requires the fixed structures (10 houses + smithy +
    armor shop + inn), else falls back to the hub fixture so the town is never
    unusable. Pure `resolve`/`meets_required_structures` plus a non-blocking
    `request_town` coroutine over an injected LLM client.
    Why: Deliver the "LLM proposes, server guarantees, fixture fallback" hybrid
    (map Q2) as a tested seam, the last piece before the town can be safely
    LLM-generated.
    Related work: [Slice 026](slices/026-llm-town-generation.md)
    Validation: See Slice 026 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 031 — grew the village to radius 30 (~3.5x
    area, secondary streets, bigger plaza/pond), added 10 villager homes
    (`npc_house`) and the village leader's hall (`village_hall`) for 28
    structures, raised `MAX_TILE_COUNT` to 4096 and `MAX_COORDINATE_ABS` to 48,
    grew the monster exclusion to 32 and the ground plane to 100×100, and added
    the two new v3 structure kinds + prefabs.
    Why: User request — a bigger rural village (Qeynos/Elliot feel) with NPC and
    leader housing, not just player houses.
    Related work: [Slice 031](slices/031-bigger-village-npc-leader-housing.md)
    Validation: See Slice 031 validation section.
  - Date: 2026-09-14
    What changed: Implemented Slice 052 — wired `TownLayoutProvider`'s LLM
    generation on at server boot behind a default-off
    `PROJECT0_LLM_TOWN_AT_BOOT` flag (`llm_at_boot_enabled()` /
    `resolve_boot_town()`). When set, `server_main.gd`'s `_start_server()`
    awaits `request_town()` against a `LocalLLMClient` configured from
    environment (Slice 051) before opening its socket; on any failure it falls
    back to the fixture. Unset boots exactly as before.
    Why: Close the last "wire it on" item from the Slice 026 guarantee seam so
    an operator can opt into LLM-generated starting towns without risking an
    unusable boot.
    Related work: [Slice 052](slices/052-f026-llm-town-at-boot.md)
    Validation: See Slice 052 validation section.

### F-030: Accounts and characters persistence repository

- Status: `Implemented`
- Feature: The server durably creates, reads, selects, and soft-deletes
  Accounts and their Characters through one server-only repository on the
  shared SQLite engine — enforcing username uniqueness, global live
  Character-name uniqueness, the 5-Character cap, and ownership, with every
  mutation atomic and fail-closed. Slice 040 boot-wires this repository into
  the running server for the first time (`server_main.gd` now opens the store
  and calls `ensure_schema()` at startup); RPC/client/world-entry consumption
  of Characters specifically remains later player-accounts slices (4-6).
- Problem solved: Phase 14's spec (self-serve registration, up to 5 durable
  Characters per Account, global live name uniqueness) had no data layer;
  the Wave 4 shared SQLite engine ([F-029](#f-029-shared-server-owned-sqlite-persistence-foundation))
  was inert until a consumer created domain tables and a repository seam on
  it, and nothing in the running server opened that store until Slice 040.
- How it solves the problem: Slice 039 adds the pure, versioned
  `shared/character_record.gd` (`CharacterRecord`) and
  `shared/account_handle.gd` (`AccountHandle`) value contracts plus bounded
  rejection enums and `display_name` validation (length 3-20, charset
  `[A-Za-z0-9 _-]`, no leading/trailing/double spaces) — no DB handle or
  secrets. `server/account_character_repository.gd`
  (`class_name AccountCharacterRepository`) wraps a `SqliteStore` and creates
  the `accounts`/`characters` tables (`ensure_schema()`, idempotent
  `CREATE TABLE IF NOT EXISTS`), including a partial unique index on
  `characters.display_name WHERE deleted = 0` and an index on `account_id`.
  Every mutating operation (`create_account`, `create_character`,
  `select_character`, `soft_delete_character`) runs inside one
  `SqliteStore.transaction()` `BEGIN`/`COMMIT`, uses only
  `query_with_bindings` (never string-concatenated SQL), and enforces name
  uniqueness and the 5-cap at both the app layer (pre-check) and the DB layer
  (partial unique index) as defense in depth, surfacing a DB-layer race loss
  as the same bounded `NAME_TAKEN`/`USERNAME_TAKEN` reason rather than a
  crash. The repository stores and returns the PBKDF2 credential bytes it is
  given verbatim; it never computes or compares them — Slice 040's
  `PasswordHasher`/`AuthService` ([F-031](#f-031-account-authentication-and-session-server))
  is the first real caller that computes those bytes.
- Name-reservation reconciliation: ticket 06's explicit partial unique index
  `WHERE deleted = 0` is authoritative over ticket 05's prose ("name stays
  reserved to the Account"). A soft-deleted Character row is retained (for
  history/possible future restore) but its `display_name` is no longer
  reserved — any Account, including a different one, may reuse it once it is
  the only claim on that name among live rows. See
  [Slice 039](slices/039-accounts-characters-repository.md#reconciliation-name-reservation-across-soft-delete)
  for the full rationale.
- Phase: 10. Player accounts and characters
- Implementation slices: [Slice 039](slices/039-accounts-characters-repository.md),
  [Slice 040](slices/040-account-auth-session.md) (boot-wires the repository
  into the running server for the first time)
- Public seam: `server/account_character_repository.gd`
  (`AccountCharacterRepository.ensure_schema`, `create_account`,
  `find_account_by_username`, `create_character`, `list_characters`,
  `select_character`, `soft_delete_character`); `shared/character_record.gd`
  (`CharacterRecord`, rejection enums, `is_valid_display_name`);
  `shared/account_handle.gd` (`AccountHandle`).
- Validation: Focused `tests/unit/test_character_record.gd` 10/10 and
  `tests/integration/test_account_character_repository.gd` 10/10 (against a
  temporary `user://` database per test). Full suite
  `scripts/run_gut_validation.sh` 248/248 across 32 scripts, exit 0
  (`scripts_expected == scripts_ran == 32`, current as of Slice 040).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [player-accounts issue 05](../.scratch/player-accounts/issues/05-character-data-model-and-lifecycle.md),
  [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md),
  [F-029](#f-029-shared-server-owned-sqlite-persistence-foundation) (the
  consumed SQLite engine foundation), [F-031](#f-031-account-authentication-and-session-server)
  (the first runtime consumer).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-030 via Slice 039 — added the shared
    `CharacterRecord`/`AccountHandle` contracts and the server-only
    `AccountCharacterRepository` with atomic, parameter-bound, fail-closed
    account/character CRUD on top of the Slice 038 `SqliteStore` engine.
    Why: Phase 14's spec needs a durable data layer before auth/RPC/client
    slices can be built on it; this is the next unblocked slice now that the
    Wave 4 shared SQLite foundation (F-029) is delivered.
    Validation: Focused suites 10/10 and 10/10; full GUT suite 233/233 across
    30 scripts, exit 0.
  - Date: 2026-09-13
    What changed: Promoted F-030 to `Implemented` via Slice 040, which
    boot-wires `server_main.gd` to open the accounts `SqliteStore` and call
    `ensure_schema()` at startup — the repository's first runtime consumer.
    Why: the handoff for Slice 040 named this promotion explicitly, since a
    repository that is only ever exercised by tests is not yet a delivered
    runtime capability; Slice 040's boot wiring closes that gap.
    Validation: full GUT suite 248/248 across 32 scripts, exit 0.

### F-029: Shared server-owned SQLite persistence foundation

- Status: `Implemented` (engine seam only; no domain tables — see Known limitations)
- Feature: One server-owned SQLite engine (`server/sqlite_store.gd`, `class_name SqliteStore`) that opens a database in `user://` (never `res://`), enables `PRAGMA journal_mode=WAL`, reads/writes `PRAGMA user_version` and fails closed on an unsupported version, exposes an atomic `BEGIN`/`COMMIT`/`ROLLBACK` transaction helper, and a parameter-bound query API (`query_with_bindings`).
- Problem solved: nothing in this repository durably persists structured records across restarts yet. Both Phase 14 (Player accounts and characters) and Phase 9 (Canon persistence) independently need a durable, atomic, fail-closed, injection-safe store; building two would diverge and duplicate risk. This is Wave 4 of the delivery roadmap — "the linchpin, build once."
- How it solves the problem: Slice 038 vendors the `godot-sqlite` GDExtension (2shady4u, MIT) pinned at release `v4.4` (built against Godot 4.3-stable, an exact engine match) into `addons/godot-sqlite/`, then wraps it in a server-only `RefCounted` seam that never leaves `server/`. Every write path goes through `transaction()` (rollback on any failure, so no partial durable record) and `query_with_bindings()` (never string-concatenated SQL). An existing database's `user_version` is checked on open and rejected outright if it doesn't match the one version this build supports — never guessed/migrated forward.
- Phase: 9 (Canon persistence and world mutation) and 10 (Player accounts and characters) — cross-cutting shared foundation, not owned by either phase's domain schema.
- Implementation slices: [Slice 038](slices/038-shared-sqlite-persistence-foundation.md)
- Public seam: `server/sqlite_store.gd` (`SqliteStore.open`, `close`, `is_open`, `get_user_version`, `transaction`, `query_with_bindings`, `query`); `addons/godot-sqlite/` (vendored, pinned).
- Validation: Headless extension-load proof (ad hoc smoke script, `godot --headless --path . --script ...`) — exit 0, `SMOKE_OK`, no load error. Focused `tests/integration/test_sqlite_store.gd` 6/6 passed, 22 asserts. Full suite `scripts/run_gut_validation.sh` 213/213 across 28 scripts, exit 0 (`scripts_expected == scripts_ran == 28`).
- Related work: [Project Tracker](PROJECT-TRACKER.md#delivery-order-and-parallelization) (Wave 4), [player-accounts spec](../.scratch/player-accounts/spec.md), [player-accounts issue 03](../.scratch/player-accounts/issues/03-research-godot-persistence-sqlite.md), [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md).
- Change history:
  - Date: 2026-09-13
    What changed: Delivered F-029 via Slice 038 — vendored the pinned `godot-sqlite` v4.4 GDExtension and added the `SqliteStore` engine seam (`user://`-only, WAL, fail-closed `user_version`, atomic transactions, parameter-bound queries only). No domain tables (Account/Character/Canon schemas remain later slices).
    Why: Phase 14 (player accounts) and Phase 9 (Canon) both require one shared, server-owned, atomic, fail-closed, injection-safe persistence mechanism per the resolved player-accounts persistence research/design (tickets 03/06); building it once now unblocks both.
    Validation: Headless load proof exit 0 (`SMOKE_OK`); focused suite 6/6; full GUT suite 213/213 across 28 scripts, exit 0.

### F-028: Imperial world-scale measurement contract

- Status: `Implemented`
- Feature: The game has one canonical, versioned world scale — the world is Imperial and one world unit is one yard, in a three-tier world unit → Tile → Sector model where a Sector is a ¼-mile (440-unit) region. A single shared contract (`WorldScale`) converts between world units, feet, and miles.
- Problem solved: Scale lived implicitly and inconsistently — the blueprint Tile was 1 unit, movement was bare "units/second", and the monster constants silently assumed meters — with no canonical source of truth and no scale term in `CONTEXT.md`.
- How it solves the problem: Slice 036 adds `shared/world_scale.gd` (`WorldScale`), a pure versioned value contract (constants `SCALE_VERSION`, `UNIT_LABEL`, `FEET_PER_YARD`, `YARDS_PER_MILE`, `TILE_EDGE_UNITS`, `SECTOR_EDGE_UNITS` plus `units_to_feet`/`units_to_miles`/`miles_to_units`), read identically by client and server with no authority. The decision is recorded in [ADR 0003](adr/0003-imperial-world-scale.md) and the [World Scale map](../.scratch/world-scale/map.md); `CONTEXT.md` gains the World unit, Tile, and Sector-span terms.
- Phase: 8. JIT world generation and local inference (cross-cutting scale contract)
- Implementation slices: [Slice 036](slices/036-world-scale-measurement-contract.md), [Slice 037](slices/037-world-scale-constant-relabel.md)
- Public seam: `shared/world_scale.gd` (`SCALE_VERSION`, `UNIT_LABEL`, `FEET_PER_YARD`, `YARDS_PER_MILE`, `TILE_EDGE_UNITS`, `SECTOR_EDGE_UNITS`, `units_to_feet`, `units_to_miles`, `miles_to_units`).
- Validation: See [Slice 036](slices/036-world-scale-measurement-contract.md) — focused `test_world_scale` 8/8 (15 asserts, exit 0); full suite `scripts/run_gut_validation.sh` 207/207 across 27 scripts, exit 0 (`scripts_expected == scripts_ran == 27`).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [World Scale map](../.scratch/world-scale/map.md), [ADR 0003](adr/0003-imperial-world-scale.md). The meters→yards relabel of existing constants (world-scale ticket 04) was completed in Slice 037.
- Change history:
  - Date: 2026-09-13
    What changed: Delivered F-028 via Slice 036 — added the versioned `WorldScale` measurement contract (1 unit = 1 yard; world unit → Tile → Sector; ¼-mile Sector), recorded [ADR 0003](adr/0003-imperial-world-scale.md), and added the `CONTEXT.md` scale terms. Planning charted via the World Scale wayfinder map (tickets 01–05).
    Why: Scale was implicit and inconsistent (1-unit tiles, bare "units/second", monster constants silently in "meters"); the user asked for a measurement system to define scale, in Imperial units.
    Validation: Focused `test_world_scale` 8/8 exit 0; full GUT suite 207/207 across 27 scripts, exit 0.
  - Date: 2026-09-13
    What changed: Completed F-028's constant adoption via Slice 037 — renamed the world-scale-bearing constants meters→yards (monster `*_YARDS`, combat `reach_yards`, `RESPAWN_AREA_RADIUS_YARDS`) and relabeled the `network_config`/`player` unit comments; magnitudes unchanged.
    Why: Adopt the Imperial vocabulary (1 unit = 1 yard) in the existing code so the "meters" labels no longer contradict ADR 0003.
    Validation: Rename-only; full GUT suite stays green 207/207 across 27 scripts, exit 0.

### F-027: Server-authoritative movement collision

- Status: `Implemented`
- Feature: The server keeps the player out of walls and buildings — authoritative movement resolves against the town's solid cells (wall tiles + building footprints) with wall-sliding, so the village is physically solid to walk around in.
- Problem solved: The server owned player position by pure integration with no collision, so the player walked straight through walls, houses, and the village hall.
- How it solves the problem: Slice 030 adds `shared/sector_collision_map.gd` (`SectorCollisionMap`), built from the validated blueprint into a blocked grid-cell set (every `wall` tile plus each structure's per-kind footprint from `SectorGeometryLookup.structure_footprint`); `resolve_move(from, to)` does axis-separated sliding so the player stops at a solid cell's face and slides along walls. `server/server_player_state.gd`'s movement integration applies `resolve_move` when a map is injected (null = free movement, backward compatible), and `server/server_main.gd` builds the map from the hub at boot and injects it into every peer. Walkable ground (floor/path/plaza/gate/grass/water) stays open; the southern gate is passable.
- Phase: 12. Authoritative runtime and action input
- Implementation slices: [Slice 030](slices/030-server-side-collision.md)
- Public seam: `shared/sector_collision_map.gd` (`is_blocked`, `resolve_move`, `blocked_count`), `shared/sector_geometry_lookup.gd` (`structure_footprint`), `server/server_player_state.gd` (`set_collision_map`), `server/server_main.gd` (`_town_collision`).
- Validation: See [Slice 030](slices/030-server-side-collision.md) — 6/6 collision-map + 4/4 player-state-collision + 10/10 lookup focused tests; full suite `scripts/run_gut_validation.sh` 188/188 across 24 scripts, exit 0. Live client-blocked confirmation is pending a server restart.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), extends [IP-001](#ip-001-server-authoritative-networked-multiplayer), makes [F-026](#f-026-organic-districted-starting-city) solid.
- Change history:
  - Date: 2026-09-13
    What changed: Implemented Slice 030 — server-side wall/building collision (`SectorCollisionMap` + per-kind footprints), applied in `ServerPlayerState` movement and injected from server boot, so the village is physically solid with wall-sliding.
    Why: The village rendered but the player walked through everything (no collision authority); a "is it walkable?" review surfaced the gap.
    Validation: See Slice 030 validation section.

### P-004: Agent-assisted delivery orchestration

- Status: `Implemented`
- Feature: Copilot in VS Code produces a bounded implementation handoff that triggers Claude Code CLI for the named multi-file changes and returns validation evidence for review, backed by a durable handoff template and a defined traceable-handoff evidence record.
- Problem solved: Planning, implementation, and review can drift when agent ownership and handoff evidence are implicit.
- How it solves the problem: Slice 027 promotes the handoff brief to a durable template (`docs/templates/claude-code-handoff-template.md`), adds an "Agent-assisted delivery orchestration" section to `DEVELOPMENT-WORKFLOW.md` defining the loop (Copilot brief → Claude Code CLI implements → returns evidence → Copilot reviews) and the five-part traceable-handoff evidence record, and demonstrates one real traceable handoff (Slice 008) whose review caught a missing-evidence gap and tracked it as DT-006 rather than accepting it. Ownership stays authoritative in `AGENTS.md` and `.github/copilot-instructions.md`.
- Phase: 13. Delivery workflow capabilities
- Implementation slices: [Slice 027](slices/027-agent-assisted-delivery-orchestration.md)
- Public seam: `docs/templates/claude-code-handoff-template.md`, the `DEVELOPMENT-WORKFLOW.md` "Agent-assisted delivery orchestration" section, and the slice records with their synchronized `FEATURE-LIST.md`/`PROJECT-TRACKER.md` entries.
- Validation: See [Slice 027](slices/027-agent-assisted-delivery-orchestration.md) — focused documentation check (required template sections present, workflow section present, no unresolved placeholders) PASS exit 0, plus `scripts/run_gut_validation.sh` 168/168 across 22 scripts, exit 0 (no regression).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [game-vision map](../.scratch/game-vision/map.md)
- Change history:
  - Date: 2026-09-13
    What changed: Delivered P-004 via Slice 027 — promoted the Claude Code handoff template into `docs/templates/`, documented the orchestration loop and traceable-handoff evidence record in `DEVELOPMENT-WORKFLOW.md`, and demonstrated one traceable handoff (Slice 008). Moved P-004 `Planned` → `Implemented`.
    Why: Make agent ownership and handoff evidence explicit and traceable so planning, implementation, and review no longer drift.
    Validation: Focused documentation check exit 0; full GUT suite 168/168, exit 0.

### F-025: Project flow visual-management dashboard

- Status: `Implemented`
- Feature: A read-only web dashboard renders the delivery flow live — per-goal
  issue vetting, a Vetting → Planned → Ready → Active → Done lifecycle strip, an
  implementation board whose feature cards are correlated to the `.scratch`
  issues they were promoted from, Andon/stop signals, and phase status.
- Problem solved: Delivery state was spread across `.scratch` maps/issues,
  `FEATURE-LIST.md`, and `PROJECT-TRACKER.md` with no single visual read on what
  is being vetted, what is ready, what is active, and what is done.
- How it solves the problem: `dashboard/app.py` (a dependency-free
  `http.server`) parses `.scratch/<goal>/map.md` + `issues/*.md`,
  `FEATURE-LIST.md`, `PROJECT-TRACKER.md`, and `TECHNICAL-DEBT-TRACKER.md` on
  each request and renders the board; it runs read-only in the
  `project0-flow-visual` container and hot-reloads on source change.
- Phase: 13. Delivery workflow capabilities
- Public seam: `dashboard/app.py` (`goal_maps`, `feature_cards`,
  `feature_stage`, `phase_rows`, `debt_cards`, `render`),
  `dashboard/Dockerfile`, `dashboard/docker-compose.yml`.
- Implementation slices: [Slice 094](slices/094-reality-dashboard-truthfulness.md) extends the Reality view's parser and provenance display; [Slice 111](slices/111-dashboard-issue-traceability-detail.md) refreshes the detail screen for GitHub Issue traceability; [Slice 112](slices/112-reality-goal-source-of-truth.md) makes the Reality view show parent Goal issues with child-issue completion; [Slice 113](slices/113-dashboard-apps-source-layout.md) standardizes the live container layout under `/apps/project0/dashboard`; [Slice 114](slices/114-goal-target-coverage-cards.md) separates Goal target-condition coverage from GitHub child issue state; [Slice 115](slices/115-goal-good-looks-like-criteria.md) makes WGL criteria the basis for Goal target coverage.
- Validation: Served live at `http://127.0.0.1:18083` (HTTP 200); the parsers
  run against the live records each request. No GUT coverage — this is Python
  delivery tooling outside the Godot suite.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [project flow dashboard](../.scratch/game-vision/issues/14-project-flow-dashboard.md)
- Change history:
  - Date: 2026-09-12
    What changed: Backfilled this F-025 record for the already-delivered flow
    dashboard (resolved planning ticket game-vision #14, which had no feature
    record), then added the goal-map vetting roadmap, the delivery-lifecycle
    flow strip, and the feature-to-issue-correlated implementation board.
    Why: Close a traceability gap — a delivered `task` issue with no feature —
    and make the delivery flow itself a first-class tracked capability.
    Validation: Dashboard serves HTTP 200 with the live board.
  - Date: 2026-09-15
    What changed: Slice 094 makes the Reality view recognize delivered slices,
    deduplicate repeated feature headings, weight overall completion by tracked
    items, show commit provenance and hidden uncommitted work, and reconciles
    stale Phase 1 and Phase 8 status badges.
    Why: The page understated shipped work and presented contradictory phase
    status without identifying the source revision.
    Validation: Focused parser model check and `scripts/check_record_sync.sh`
    passed; see [Slice 094](slices/094-reality-dashboard-truthfulness.md).
  - Date: 2026-09-16
    What changed: Slice 111 changes `/detail` from a stale roadmap-heavy screen
    into a GitHub traceability detail view. It now shows linked slice records,
    parent `.scratch` goal issues, child planning issues, and goal folders
    without `map.md` as new/unresearched.
    Why: The delivery workflow now treats GitHub Issues as the baseline source
    of work intent, so the detail screen needed to reflect that hierarchy and
    stop foregrounding obsolete hardcoded roadmap prose.
    Validation: `python -m py_compile dashboard/app.py`, focused dashboard render
    checks, and `scripts/check_record_sync.sh` passed; see [Slice 111](slices/111-dashboard-issue-traceability-detail.md).
  - Date: 2026-09-16
    What changed: Slice 112 changes the Reality page's GitHub Source of Truth
    section to show only parent Goal issues, with each card showing closed/total
    child issue counts, open child count, and a completion percentage.
    Why: A flat list of every open issue made the source-of-truth section noisy
    after the `.scratch` hierarchy was mirrored into GitHub. The Reality page
    should orient around goals and progress through their child issues.
    Validation: `python -m py_compile dashboard/app.py`, focused Reality render
    checks, and `scripts/check_record_sync.sh` passed; see [Slice 112](slices/112-reality-goal-source-of-truth.md).
  - Date: 2026-09-16
    What changed: Slice 113 moves the live dashboard deployment contract to
    `/apps/project0/dashboard`, with compose/app files at that path and a
    dedicated read-only clone at `/apps/project0/dashboard/repo` mounted as
    `/repo` in the container.
    Why: The previous `/data/code/project0` source mirror was stale and was not a
    git checkout, so restarting the container did not guarantee the dashboard
    served the merged records and issue UI.
    Validation: Local script/dashboard checks, record-sync, and host rollout
    checks passed; see [Slice 113](slices/113-dashboard-apps-source-layout.md).
  - Date: 2026-09-16
    What changed: Slice 114 adds a target-condition coverage metric to Reality
    page Goal cards, computed from resolved child planning issue status, while
    retaining separate GitHub open/closed child issue counts.
    Why: GitHub issue state alone does not tell whether the child planning set
    covers the goal's target condition. Operators need to see both planning
    coverage and issue workflow state on the Goal card.
    Validation: `python -m py_compile dashboard/app.py`, focused Reality render
    checks, and `scripts/check_record_sync.sh` passed; see [Slice 114](slices/114-goal-target-coverage-cards.md).
  - Date: 2026-09-16
    What changed: Slice 115 makes `## What Good Looks Like` the explicit Goal
    acceptance-criteria section, adds WGL checklists to researched `.scratch`
    goal maps, mirrors those sections into parent GitHub Goal issues, and makes
    dashboard target coverage parse the parent Goal criteria.
    Why: Child issues are known work and learning questions, not proof that the
    customer problem behind a Goal has been solved. Goal target coverage needed
    to measure customer-outcome criteria instead of child issue closure.
    Validation: `python -m py_compile dashboard/app.py`, focused Reality render
    checks, parent Goal issue mirror verification, and `scripts/check_record_sync.sh`
    passed; see [Slice 115](slices/115-goal-good-looks-like-criteria.md).

### F-022: Player house allocation

- Status: `Implemented`
- Feature: Each connecting peer is assigned a unique house from the starting
  town's fixed 10-house pool, server-authoritatively, freed immediately on
  disconnect; the owning client sees "Your house: <id>" in its HUD.
- Problem solved: The town has 10 houses but nothing tied a player to one; the
  original vision is that each adventurer gets their own house in town.
- How it solves the problem: Slice 019 adds `server/house_allocator.gd` (a pure,
  unit-testable allocator: first-available, idempotent per peer, fail-closed on
  exhaustion, immediate release with no reconnect reservation) built from the
  Slice 016 hub blueprint's `house` structures. `server/server_main.gd` assigns
  on connect (telemetry-logged) and notifies only the owning client via a new
  `receive_assigned_house` reliable RPC on `client/network_client.gd`, which a
  `HouseLabel` HUD element (`client/assigned_house_label.gd`) presents.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 019](slices/019-player-house-allocation.md)
- Public seam: `server/house_allocator.gd`
  (`house_ids_from_blueprint`, `assign`, `release`, `assigned_house`,
  `available_count`, `pool_size`), `server/server_main.gd`
  (`get_assigned_house`), `client/network_client.gd`
  (`receive_assigned_house`, `assigned_house_received`).
- Validation: See [Slice 019](slices/019-player-house-allocation.md) for exact
  commands and results (7/7 allocator unit tests, 1/1 HUD test, 117/117 full
  suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 05](../.scratch/starting-town/issues/05-player-house-allocation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 019 — server-authoritative unique-house
    allocation from the hub's fixed 10-house pool, freed on disconnect, surfaced
    in the owning client's HUD. Fixed an in-development headless class-cache
    parse error (a bare `HouseAllocator` type annotation) surfaced by the full
    suite before completion.
    Why: Deliver the Starting Town map's final planning ticket (player house
    allocation), realizing "each adventurer gets their own house in town".
    Related work: [Slice 019](slices/019-player-house-allocation.md)
    Validation: See Slice 019 validation section.

### F-021: Facade enter/exit proximity labels

- Status: `Implemented`
- Feature: Walking the local player up to a starting-town building (House,
  Smithy, Armor Shop, Inn) shows a cosmetic "You are at the <building>" label
  that clears when they walk away.
- Problem solved: The rendered town (Slice 017) was inert; there was no
  feedback for approaching a building, and no seam for "where the adventure
  begins" interactions.
- How it solves the problem: Slice 018 adds `client/facade_proximity.gd` (an
  `Area3D` on each structure prefab that filters to the local `Player` body and
  reports to a presenter found via the `facade_presenter` group) and
  `client/facade_presenter.gd` (a `Label` in the gameplay UI). Each of the four
  `client/structures/*.tscn` prefabs gains a `FacadeProximity` area with its
  building name; `client/gameplay.tscn` gains the presenter `FacadeLabel`. It is
  purely client-observed and cosmetic — no server authority, no exclusivity, no
  interior scene.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 018](slices/018-facade-enter-exit.md)
- Public seam: `client/facade_proximity.gd`
  (`is_local_player`, `building_display_name`),
  `client/facade_presenter.gd` (`show_facade`, `clear_facade`, `line_for`,
  `GROUP_NAME`).
- Validation: See [Slice 018](slices/018-facade-enter-exit.md) for exact
  commands and results (4/4 presenter unit tests, 5/5 proximity integration
  tests incl. a real physics-overlap test, 109/109 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 04](../.scratch/starting-town/issues/04-facade-representation-and-enter-exit.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 018 — cosmetic client-only facade proximity
    labels on the four starting-town building prefabs, plus a UI presenter.
    Fixed an in-development regression (a malformed 11-value `Transform3D` in
    the four structure prefabs) surfaced by the full suite before completion.
    Why: Make the now-visible starting town interactive (the map's facade
    enter/exit planning ticket), toward the "adventures begin in a tavern" goal.
    Related work: [Slice 018](slices/018-facade-enter-exit.md)
    Validation: See Slice 018 validation section.

### F-020: Server-to-client sector blueprint replication

- Status: `Implemented`
- Feature: On connect, the server replicates the validated starting town hub
  blueprint to each client, which re-validates it and renders it into a
  dedicated `SectorGeometry` scene node — producing a visible, end-to-end
  starting town (server hub fixture → wire → client-rendered geometry).
- Problem solved: The server held a validated hub (Slice 016) and the client
  could translate a blueprint into geometry (Slice 015), but nothing connected
  the two; a validated blueprint had no path from server to a client's scene.
- How it solves the problem: Slice 017 adds a reliable authority RPC
  `receive_sector_blueprint(blueprint)` on `client/network_client.gd`, sent by
  `server/server_main.gd._on_peer_connected` (before player-spawn RPCs) with
  the in-memory hub Dictionary. The client re-validates through
  `SectorBlueprintSchema.validate()` at the boundary and, only on success,
  runs the Slice 015 `SectorGeometryTranslator` into a dedicated
  `SectorGeometry` node, leaving `FlatPlane`/`Player`/UI untouched. An invalid
  payload renders nothing. The render logic is a static, parent-injected
  `render_sector_blueprint()` seam for testability; a `sector_blueprint_received`
  signal plus send/receive logs provide replication telemetry.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 017](slices/017-blueprint-replication.md)
- Public seam: `client/network_client.gd`
  (`receive_sector_blueprint`, `render_sector_blueprint`,
  `sector_blueprint_received`), `server/server_main.gd`
  (`_on_peer_connected` send).
- Validation: See [Slice 017](slices/017-blueprint-replication.md) for exact
  commands and results (4/4 focused tests, 100/100 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 06](../.scratch/starting-town/issues/06-blueprint-replication-contract.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 017 — reliable server→client replication of
    the validated hub blueprint, re-validated and rendered client-side into a
    dedicated `SectorGeometry` node, completing the Starting Town map
    end-to-end.
    Why: Close the map's final resolved planning ticket (blueprint replication
    contract) so the hub is actually visible in a connected client, unblocking
    facade-interaction and house-allocation slices.
    Related work: [Slice 017](slices/017-blueprint-replication.md)
    Validation: See Slice 017 validation section.

### F-019: Starting town hub fixture

- Status: `Implemented`
- Feature: The headless server materializes a hard-coded, schema-v2 starting
  town hub blueprint (reserved `sector_id` `starting_town_hub`, a bounded
  wall/corridor/floor footprint, and 13 structures — a 10-house player pool
  plus Smithy, Armor Shop, and Inn) at boot, validating it through the same
  `SectorBlueprintSchema` the LLM path uses and failing closed if it is
  invalid.
- Problem solved: The starting town must reliably contain the same buildings
  every run; live LLM generation cannot guarantee that, so the hub ships as
  static, server-owned, schema-validated data rather than a generated sector.
- How it solves the problem: Slice 016 adds
  `server/starting_town_hub_fixture.gd` (a `RefCounted` with static
  `blueprint()` and a pure fail-closed `materialize()` seam) and wires it into
  `server/server_main.gd._start_server()`, which validates the fixture before
  opening a socket, holds the validated blueprint in memory (exposed read-only
  via `get_starting_town_hub_blueprint()`), and refuses to start (`quit(1)`,
  logging the outcome/detail) if validation fails. The hub bypasses Ollama and
  `provisional_sector_generator.gd` entirely.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 016](slices/016-starting-town-hub-fixture.md)
- Public seam: `server/starting_town_hub_fixture.gd`
  (`SECTOR_ID`, `blueprint()`, `materialize()`),
  `server/server_main.gd` (`get_starting_town_hub_blueprint()`).
- Validation: See [Slice 016](slices/016-starting-town-hub-fixture.md) for
  exact commands and results (8/8 focused tests, 96/96 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 03](../.scratch/starting-town/issues/03-hub-sector-identity-and-pinning.md),
  [issue 05](../.scratch/starting-town/issues/05-player-house-allocation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 016 — a hard-coded, schema-validated
    starting town hub fixture materialized fail-closed at server boot and held
    in memory for future client replication.
    Why: Close the Starting Town map's third resolved planning ticket (hub
    sector identity and pinning) so a reliable, reproducible town exists before
    replication, facade interaction, or per-player house allocation slices.
    Related work: [Slice 016](slices/016-starting-town-hub-fixture.md)
    Validation: See Slice 016 validation section.

### F-018: Client-side sector geometry translation

- Status: `Implemented`
- Feature: A validated sector blueprint Dictionary (schema v1 or v2) is
  translated on the client into 3D scene geometry: procedural per-kind boxes
  for tiles and instanced placeholder prefab scenes for structures.
- Problem solved: A validated blueprint had no path to becoming visible scene
  geometry; CLAUDE.md previously treated geometry translation as fully
  unimplemented.
- How it solves the problem: Slice 015 adds `shared/sector_geometry_lookup.gd`
  (a pure `RefCounted` helper, no scene-tree dependency) mapping tile kind to
  mesh/collision box dimensions and structure kind to a `PackedScene` path,
  and `client/sector_geometry_translator.gd`, which takes an already-validated
  blueprint Dictionary and a parent `Node3D` and instantiates one
  `StaticBody3D`/`MeshInstance3D`/`CollisionShape3D` per tile and one
  `PackedScene.instantiate()` per structure at its `x`/`y`/`facing_degrees`.
  Four placeholder structure scenes
  (`client/structures/{house,smithy,armor_shop,inn}.tscn`) follow the existing
  `TargetDummy`-style placeholder-art convention.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 015](slices/015-sector-geometry-translation.md), [Slice 024](slices/024-scalable-geometry-pass.md), [Slice 025](slices/025-organic-vocabulary.md)
- Public seam: `shared/sector_geometry_lookup.gd` (`tile_dimensions`,
  `tile_is_solid`), `client/sector_geometry_translator.gd` (`translate`).
- Validation: See [Slice 015](slices/015-sector-geometry-translation.md) for
  exact commands and results.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 02](../.scratch/starting-town/issues/02-geometry-translation-strategy.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 015 — client-side translation of a
    validated sector blueprint into procedural tile geometry and instanced
    placeholder structure prefabs.
    Why: Close the Starting Town map's second resolved planning ticket
    (geometry translation strategy) before hub materialization, facade
    interaction, or player house allocation work.
    Related work: [Slice 015](slices/015-sector-geometry-translation.md)
    Validation: See Slice 015 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 024 — replaced the one-`StaticBody3D`-per-tile
    strategy with a merged geometry pass: non-solid ground tiles combine into one
    `ArrayMesh` per kind on a body-free `MeshInstance3D`, and wall tiles
    greedy-merge per row into box colliders under one shared `Walls`
    `StaticBody3D`. Added `SectorGeometryLookup.tile_is_solid`.
    Why: Remediate [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size)
    so rendered town size is decoupled from the physics body count, unblocking
    the F-026 city-scale destination and the later schema-v3/LLM slices.
    Related work: [Slice 024](slices/024-scalable-geometry-pass.md)
    Validation: See Slice 024 validation section.
  - Date: 2026-09-13
    What changed: Added geometry-lookup dimensions for the five organic ground
    kinds and scene paths for the four new structure prefabs
    (church/tavern/item_shop/well) (Slice 025).
    Why: Let the merged geometry pass render the schema-v3 organic vocabulary
    with no new geometry code.
    Related work: [Slice 025](slices/025-organic-vocabulary.md)
    Validation: See Slice 025 validation section.
  - Date: 2026-09-13
    What changed: Added scene paths and placeholder prefabs for the two new
    structure kinds `npc_house` (villager home) and `village_hall` (the rural
    leader's hall) (Slice 031).
    Why: Render the bigger village's NPC and leader housing.
    Related work: [Slice 031](slices/031-bigger-village-npc-leader-housing.md)
    Validation: See Slice 031 validation section.

### F-017: Sector blueprint schema v2 — structures and spawn points

- Status: `Implemented`
- Feature: The sector blueprint validator accepts an optional version-two
  shape (`structures` and `spawn_points` arrays) alongside the existing
  tiles-only version-one contract, so a future town-like hub sector can
  describe building placements and monster spawn markers without weakening
  or replacing plain version-one sectors.
- Problem solved: The Starting Town map needs a validated way to describe
  House/Smithy/Armor Shop/Inn placements and monster spawn markers before any
  geometry translation, hub materialization, or monster work can begin.
- How it solves the problem: Slice 014 changes `schema_version` validation
  from strict equality to a supported-set check (`1` or `2`), and adds two
  new optional top-level arrays validated with the same fail-closed style as
  the existing `tiles` array: `structures` (unique `structure_id`, a `kind`
  bounded by `SUPPORTED_STRUCTURE_KINDS`, bounded `x`/`y`, and
  `facing_degrees` in `[0, 360)`) and `spawn_points` (`spawn_id`, bounded
  `x`/`y`, bounded in count by `MAX_SPAWN_POINT_COUNT = 16`). Absent or empty
  arrays remain valid for both schema versions, so existing non-town v1
  sectors are unaffected. `server/sector_blueprint_service.gd` required no
  change since it already forwards whatever outcome/blueprint the validator
  returns.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md), [Slice 025](slices/025-organic-vocabulary.md)
- Public seam: `shared/sector_blueprint_schema.gd` (`SUPPORTED_SCHEMA_VERSIONS`, `SUPPORTED_TILE_KINDS`, `SUPPORTED_STRUCTURE_KINDS`, `ORGANIC_VOCABULARY_MIN_VERSION`).
- Validation: See [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md)
  for exact commands and results (16/16 focused unit tests, 20 assertions;
  77/77 full suite, 188 assertions, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 01](../.scratch/starting-town/issues/01-schema-v2-structures-and-spawn-points.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 014 — version-2-capable sector blueprint
    validation with optional `structures` and `spawn_points` arrays,
    preserving version-1 backward compatibility.
    Why: Close the Starting Town map's first resolved planning ticket (schema
    v2 shape) before any geometry translation, hub materialization, or
    monster spawning work.
    Related work: [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/unit -gselect=test_sector_blueprint_schema_v2 -gexit`
    passed 16/16 tests, 20 assertions, exit 0; the full configured GUT suite
    (`scripts/run_gut_validation.sh`) passed 77/77 tests, 188 assertions,
    exit 0.
  - Date: 2026-09-13
    What changed: Extended the schema to version 3 with the organic tile
    vocabulary (path/plaza/gate/water/grass) and structure vocabulary
    (church/item_shop/tavern/well), version-gated so v1/v2 keep their original
    vocabulary (Slice 025).
    Why: Give the starting town an organic town vocabulary while keeping
    schema_version a meaningful compatibility signal for the future LLM path.
    Related work: [Slice 025](slices/025-organic-vocabulary.md)
    Validation: See Slice 025 validation section.
  - Date: 2026-09-13
    What changed: Raised `MAX_TILE_COUNT` to 4096 and `MAX_COORDINATE_ABS` to 48
    for the ~3x-bigger village, and added `npc_house` and `village_hall` to the
    v3 organic structure vocabulary (Slice 031).
    Why: Fit the larger rural village and its NPC/leader housing within the
    validated blueprint contract.
    Related work: [Slice 031](slices/031-bigger-village-npc-leader-housing.md)
    Validation: See Slice 031 validation section.

### F-007: Living architecture anchor

- Status: `Implemented`
- Feature: Root `CLAUDE.md` records durable architecture boundaries and the
  normative combat, progression, magic, and Canon contract while pointing
  agents to authoritative project records.
- Problem solved: Agents otherwise reconstruct architecture from scattered
  files and may introduce contradictory authority or state rules.
- How it solves the problem: Slice 010 defines binding server/client ownership,
  six-node vessel and derived-state rules, Kinetic/Meridian/Burnout behavior,
  magic equilibrium, versioned contracts, intent validation, Canon boundaries,
  telemetry, implementation placement, and test seams while distinguishing the
  current implementation from future target behavior.
- Phase: 13. Delivery workflow capabilities
- Implementation slices: [Slice 010](slices/010-core-mechanics-architecture.md)
- Public seam: Root `CLAUDE.md`, linked `AGENTS.md`, `CONTEXT.md`, ADR 0002,
  and delivery records.
- Validation: Slice 010's required-term/placeholder and local-link checks passed
  with exit 0. `scripts/run_gut_validation.sh` passed 23/23 tests and 70
  assertions with exit 0; JUnit and JSON summary artifacts were verified.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)
- Change history:
  - Date: 2026-09-12
    What changed: Slice 011 made Mind versus Tool an explicit architecture
    boundary, added perceptual-cue and combat execution-profile contracts, and
    clarified `MET` as derived Metabolism distinct from Mental Focus.
    Why: Preserve player-owned observation and reasoning while allowing the
    Player body's stats to modify physical execution and authored feedback.
    Related work: [Slice 011](slices/011-mind-tool-architecture-refinement.md)
    Validation: Focused semantic checks and the 23-test GUT suite passed.
  - Date: 2026-09-12
    What changed: Replaced the thin architecture note with the unified core
    mechanics contract and recorded its authority decision.
    Why: Make the user's biological progression and combat rules a durable
    constraint before implementation decisions fragment across slices.
    Related work: [Slice 010](slices/010-core-mechanics-architecture.md)
    Validation: Focused documentation checks and the 23-test GUT suite passed.

### F-005: Automated validation gate and test telemetry

- Status: `Implemented`
- Feature: Every push and pull request runs the repository's GUT validation suite and preserves machine-readable results.
- Problem solved: Local validation can be forgotten or can pass without leaving durable evidence for regression review.
- How it solves the problem: `.github/workflows/validation.yml` runs the same `scripts/run_gut_validation.sh` delivery command in a pinned Godot 4.3 container, fails the check on a nonzero result, and uploads JUnit XML, logs, and a JSON status summary even when validation fails.
- Phase: 13. Delivery workflow capabilities
- Implementation slices: Current delivery-process slice, recorded in [Project Tracker](PROJECT-TRACKER.md#implementation-slice-index)
- Public seam: `.github/workflows/validation.yml`, `scripts/run_gut_validation.sh`, and `build/validation/validation-summary.json`.
- Validation: Local runner passes 14/14 tests and 38 assertions; forced runner failure exits nonzero and emits `status: failed`. CI configuration is syntactically reviewed and uses the same local command.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Development Workflow](DEVELOPMENT-WORKFLOW.md)
- Change history:
  - Date: 2026-09-16
    What changed: Expanded the gate from a single Godot job to five jobs — GUT suite, delivery record sync, Python enrollment/operator suites, wgnetstack build, and Windows launcher tests on a Windows runner — plus `scripts/stage_launcher_payload_placeholders.sh` so the embed-dependent launcher package compiles on a clean checkout.
    Why: Record-sync, the 183 Python service tests, and the launcher tests were only ever run by hand on one machine, so a regression in any non-Godot component could reach `main` unnoticed.
    Validation evidence: Slice 102 — GUT 493/493 on okami, record-sync 0 errors, pytest 183 passed, wgnetstack `go build` clean, and launcher `go test` passing against staged placeholders.
  - Date: 2026-09-12
    What changed: Added push/pull-request validation with retained JUnit and JSON telemetry artifacts.
    Why: Make executable validation and regression evidence part of delivery rather than an optional local habit.
    Validation evidence: Local success and failure-path runner checks passed; full local suite is 14/14.

### F-003: LAN client connection

- Status: `Implemented`
- Feature: A Windows Godot client can connect to the Linux server over the local network.
- Problem solved: Slice 002 only works when client and server share a machine because the server binds to `127.0.0.1`.
- How it solves the problem: Make the server bind address and client target host configurable while preserving localhost defaults for automated checks. Slice 003 implements the CLI-arg/env-var resolution, validated headlessly and verified in a two-machine LAN run.
- Phase: 3. LAN client connection
- Implementation slices: [Slice 003](slices/003-lan-client-connection.md)
- Public seam: `shared/network_config.gd` (`resolve_server_bind_address`, `resolve_client_target_host`), `server/server_main.gd`, `client/network_client.gd`.
- Validation: Verified headlessly via `tests/unit/test_lan_config.gd` using
  GUT (including real server/probe subprocesses) and in an interactive
  physical two-machine LAN run between Windows and Linux.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [LAN client connection](../.scratch/game-vision/issues/08-lan-client-connection.md)

### F-004: Multi-peer Player replication

- Status: `Implemented`
- Feature: Two connected clients see distinct Player representations and observe each other's server-authoritative movement.
- Problem solved: The network proof through Slice 005 models only one connected Player and does not replicate peer state to other clients.
- How it solves the problem: The server owns one `ServerPlayerState` per connected peer (keyed by peer id) and replicates each peer's authoritative position to every other connected peer; each client renders every other peer as a distinct `RemotePlayer_<peer_id>` node, spawned/despawned by explicit server RPCs. Slice 007 implements this for two concurrent peers.
- Phase: 7. Multi-peer Player replication
- Implementation slices: [Slice 007](slices/007-multi-peer-player-replication.md), [Slice 086](slices/086-multipeer-character-replication.md)
- Public seam: `server/server_main.gd`, `server/server_player_state.gd`, `client/network_client.gd`, and `client/remote_player.gd`.
- Validation: Headlessly validated via `scripts/test_multi_peer_replication.gd` and verified interactively in a physical two-machine LAN run with multiple peers.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Multi-peer Player replication](../.scratch/game-vision/issues/13-multi-peer-player-replication.md)
- Change history:
  - Date: 2026-09-15
    What changed: Delivered Slice 086 — remote Players are now labeled with their bound Character's display name. `ServerPlayerState` emits `character_bound` at world entry; `server_main.gd` broadcasts `receive_remote_player_identity` to every other peer and seeds a late-joiner with already-bound identities; `NetworkClient` caches + relays the identity; `RemotePlayer` renders a billboarded `NameLabel`. Closes the Phase 14 "multi-peer Character replication" follow-up on top of the split login/assertion architecture.
    Why: After the login split, a peer binds its selected Character at world entry, but that identity was never replicated, so other players saw anonymous remotes.
    Related work: [Slice 086](slices/086-multipeer-character-replication.md), [Slice 007](slices/007-multi-peer-player-replication.md), [Slice 043](slices/043-character-world-entry.md)
    Validation: `scripts/run_gut_validation.sh` on Linux passed 401/401 tests across 59 scripts (1430 asserts), exit 0 (adds `tests/unit/test_character_identity_replication.gd`); `scripts/test_login_handoff_e2e.gd` ALL PASS (world entry ok, bound `Handoff Hero`); `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-15
    What changed: Fixed the late-joiner remote-Player visibility bug found in the two-client split GUI confirmation. `client/network_client.gd::spawn_remote_player_representation` only guarded against a null `current_scene`, so an existing peer's spawn RPC arriving while the joining client was still on the login/character screen (mid-handoff) was added to the wrong scene and destroyed on transition — the second player to enter never saw the first. It now tracks `_latest_remote_players` and defers when `current_scene` is not the gameplay `Node3D`, replayed by `render_pending_remote_players()` (wired in `client/connection_status.gd`) alongside the existing own-player/monster/blueprint replays; despawn clears the deferred entry before any early return.
    Why: Root-cause learning — the Slice 007 spawn path never deferred like the own-player/monster paths, a latent gap exposed once the split flow made a client join the game server mid-scene-transition. Existing tests missed it because the multi-peer harness both peers were already in gameplay; the asymmetric late-joiner case was untested. Countermeasure: `tests/unit/test_remote_player_deferred_spawn.gd` covers the deferred-spawn seam, replay, and despawn-clears; user-confirmed mutual visibility in the Windows two-client run.
    Related work: [Slice 086](slices/086-multipeer-character-replication.md), [Slice 007](slices/007-multi-peer-player-replication.md)
    Validation: `scripts/run_gut_validation.sh` on Linux passed 410/410 tests across 61 scripts, exit 0 (adds `tests/unit/test_remote_player_deferred_spawn.gd`); Windows two-client GUI confirmed both players mutually visible with labels.

### F-002: Portable Windows client package

- Status: `Implemented`
- Feature: A tester receives a portable Windows 64-bit ZIP package containing
  only the exported client runtime, extracts it without the Godot editor or
  Linux source share, and launches it to the identity gate, configuring the
  server address via `--server-host=<LAN IP>` or the
  `PROJECT0_SERVER_HOST` environment variable.
- Problem solved: The project had a working LAN client but no reproducible
  distributed package boundary. Slices 003–005 proved the complete client
  behavior; this slice packages that behavior for distribution and testing.
- How it solves the problem: A Godot Windows Desktop export preset
  (`export_presets.cfg`) with an inclusion-list of client-runtime files
  (client/*.gd/client/*.tscn, shared/network_config.gd, project.godot),
  deliberately excluding server/, scripts/, and local_llm_client.gd. A build
  script (`scripts/export_windows_client.sh`) exports and zips the result.
  A tester guide documents extraction, server configuration, and expected
  outcomes.
- Phase: 6. Windows client package
- Implementation slices: [Slice 006](slices/006-windows-client-package.md)
- Public seam: `export_presets.cfg` (Windows Desktop preset with client-only
  file list), `scripts/export_windows_client.sh` (build/export script),
  `docs/windows-client-tester-guide.md` (tester documentation).
- Validation: See [Slice 006](slices/006-windows-client-package.md)
  for the exact export and LAN-test results.
- Change history:
  - Date: 2026-09-16
    What changed: Added `scripts/package_client_linux.sh` and the
    `client-package` release job, cross-building the whole deliverable (Go
    Windows c-archive, GDExtension DLL, Godot export, WAN launcher, ZIP, and
    SHA256 manifest) on a Linux runner, plus a `cgoarchive-windows` Makefile
    target. `export_presets.cfg` is now tracked; it had been gitignored, so no
    clean checkout could build the client.
    Why: The package could previously only be produced on one Windows
    workstation using a hand-built, uncommitted DLL, so releases were not
    reproducible from a commit.
    Related work: [Slice 103](slices/103-linux-client-package-build.md),
    [DT-011](TECHNICAL-DEBT-TRACKER.md#dt-011-client-export-filter-ships-the-test-framework-and-build-artifacts)
  - Date: 2026-09-12
    What changed: Implemented Slice 006 — the Windows Desktop export preset
    was created with client-only files, the build script was added, and the
    tester guide was written. The exported client was LAN-tested by the user,
    launched outside the Godot editor, and reached full connected status.
    Why: User-directed Phase 6 packaging, recorded in
    `.scratch/game-vision/issues/12-windows-client-package.md`.
    Related work: [Slice 006](slices/006-windows-client-package.md),
    [DT-005](TECHNICAL-DEBT-TRACKER.md#dt-005-windows-export-artifact-was-unavailable-in-the-original-sandbox)
    Validation: See Slice 006 validation section.

### F-001: Local identity gate, flat plane scene, and player movement

- Status: `Implemented`
- Feature: A player enters a display name at a local identity gate, is placed
  in a scene containing a flat plane under a fixed 3/4 isometric camera, and
  moves a Player node around that plane with WASD keyboard input.
- Problem solved: The project needed a minimal, always-playable vertical slice
  proving the core play loop (identity → scene → movement) before any
  networking, generation, or persistence existed.
- How it solves the problem: Slice 001 adds a local identity gate
  (`client/identity_gate.gd`) that rejects an empty name and, on submit,
  changes to the gameplay scene, plus a client-side `CharacterBody3D` Player
  (`client/player.gd`) constrained to the XZ plane and driven by the four
  directional input actions each physics tick. It is fully local: no network
  calls, no files written, and the display name is held only in memory. See
  [ADR 0001](adr/0001-client-side-authority-for-first-slice.md) for why
  movement is client-side here and what must change before networking.
- Phase: 1. First playable vertical slice
- Implementation slices: [Slice 001](slices/001-identity-gate-flat-plane-movement.md)
- Public seam: `client/identity_gate.gd` (`_on_enter_pressed`),
  `client/player.gd` (`_physics_process`, `get_planar_input`).
- Validation: See [Slice 001](slices/001-identity-gate-flat-plane-movement.md)
  for the exact headless commands and results; the identity-gate and movement
  seams are covered by `tests/unit/test_identity_gate_and_movement.gd`.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [choose first playable slice](../.scratch/game-vision/issues/02-choose-first-playable-slice.md),
  [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
- Change history:
  - Date: 2026-09-11
    What changed: Implemented Slice 001 — the local identity gate, the
    flat-plane gameplay scene under a fixed 3/4 camera, and client-side planar
    Player movement. This F-001 record was backfilled on 2026-09-12 to resolve a
    dangling Project Tracker reference: the feature was delivered in Slice 001
    but never had a feature-list section.
    Why: Establish the minimal always-playable vertical slice the rest of the
    networked product builds on.
    Related work: [Slice 001](slices/001-identity-gate-flat-plane-movement.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
    Validation: See Slice 001 validation section.