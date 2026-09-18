# Map: Client Auto-Update

## Destination

A handoff-ready spec (SDD/BDD-shaped) describing how the packaged portable
**Windows tester client** (`Project0.exe` + `Project0.pck`) automatically checks
its **client build version** against the game server when it connects, and
patches itself up to the server-required version before entering the world. The
game server is the authoritative version source: at connect, **before
authentication**, it advertises the required client build version; an
out-of-date client is refused with a bounded reason and **must** apply the
update to proceed (a mandatory version gate).

The map is complete when the version-identity / domain model, the pre-auth
**version-handshake** contract, the **patch unit**, the patch **transport /
source**, the **integrity-and-trust** model, and the **apply / restart /
rollback** mechanism are each decided well enough to create implementation
tickets safely — with the integrity decision made explicit because auto-update
is **remote code delivery**. See [Project Tracker](../../docs/PROJECT-TRACKER.md),
[CLAUDE.md](../../CLAUDE.md), [CONTEXT.md](../../CONTEXT.md), and the sibling
[player-accounts](../player-accounts/map.md) effort whose auth handshake this
version gate must order against.

## What Good Looks Like

- [x] The packaged Windows tester client has a server-owned client build version handshake before authentication/world entry.
- [x] An out-of-date client is refused with a bounded reason and a mandatory update path.
- [x] Patch units, transport, integrity verification, apply/restart, and rollback are specified with fail-closed behavior.
- [x] The update flow is handoff-ready as bounded implementation slices with validation and telemetry expectations.

## Notes

- Domain: Godot 4.3 GDScript 2.0 strict typing, server-authoritative per
  CLAUDE.md's Runtime Ownership rules. Existing patterns to match:
  `shared/network_config.gd` (the values both sides agree on at connect),
  `client/network_client.gd` (the ENet connect lifecycle + the in-process
  wgnetstack WireGuard tunnel the version check must slot into),
  `server/server_main.gd` (accepts peers today with **no** version handshake),
  `scripts/export_windows_client.sh` + `export_presets.cfg` (the client exports
  as `Project0.exe` plus a **separate** `Project0.pck` — `embed_pck=false` — so
  the pck is a natural patch unit), and `docs/windows-client-tester-guide.md`
  (today's manual-ZIP distribution reality, which explicitly promises "no
  auto-update").
- Planning mode: this effort produces decisions and a handoff-ready spec; no
  product code while charting. Copilot owns grilling, domain decisions, scope,
  and the handoff; Claude CLI owns the subsequent code edits. **User
  authorization (2026-09-13): if Claude CLI is in a rate-limit state, Copilot
  may continue by implementing directly** (matches the sibling maps).
- Skills to consult per ticket: `domain-modeling` (this effort introduces new
  canonical terms — **client build version**, **update manifest**, **patch**,
  **version handshake** — that CONTEXT.md does not yet carry and that must stay
  distinct from the existing `schema_version` / `tuning_version` data-contract
  terms in CLAUDE.md), `codebase-design` (seam placement for the version
  handshake and the updater), `grilling`, `research`, `prototype` (the tester's
  update/relaunch flow).
- Security posture: auto-update is **remote code delivery**. Integrity and
  authenticity are a first-class decision ticket, not a detail; the design is
  **fail-closed** (an unverifiable or mismatched patch is refused and never
  applied), matching CLAUDE.md's "server owns outcomes / no client-authored
  trust" laws and the repo's OWASP posture.
- Decided while charting (round 1, user-accepted 2026-09-13):
  - **Destination artifact** = a handoff-ready spec, not code in this map.
  - **Scope** = the packaged portable **Windows tester client**
    (`Project0.exe` + `Project0.pck`); the dev/source client updates via `git`
    and is **out of scope**. Design the contract OS-agnostic where cheap; solve
    Windows-first because that is the real distribution surface.
  - **Update authority & trigger** = the **game server** advertises the
    authoritative required client build version in a **pre-auth handshake** at
    connect; the client acts on the mismatch. *Where the patch bytes are served
    from* is a downstream decision ticket, not fixed here.
  - **Update policy** = **mandatory version gate**: an out-of-date client is
    refused with a bounded reason and must patch before playing (a notify-only
    mode is a possible later refinement, not v1).
- Standing requirement (matches sibling maps): every implementation slice from
  this map follows the repo's SDD/BDD/TDD workflow (public-seam failing test
  first, unit + GUT integration tests, regression tests for the fail-closed
  safety invariants) with bounded telemetry built in from the start, reusing
  CLAUDE.md's "Telemetry And Andon Signals" seam (update-check / accepted /
  refused / patch-applied / rollback events).

## Decisions so far

> **Status: handoff-ready.** Rounds 1–6 are settled and recorded in Notes
> above. The two `research` tickets are **resolved** (findings under `research/`).
> Their answers are inputs to the decision tickets, not decisions themselves, so
> no fog has graduated. With research done, the frontier is a single takeable
> ticket — [Domain model & version identity](issues/01-domain-model-and-version-identity.md)
> — which every remaining decision ticket blocks on directly or transitively; the
> six `grilling`/`task` decisions are hand-resolved one per session.

<!-- one line per closed ticket; zoom the link for detail -->

- [Research — Godot pck apply & Windows self-replace](issues/02-research-godot-pck-and-windows-self-replace.md):
  a runtime pck-swap can't hot-reload the running scripts/scenes/autoloads, so v1
  is **full-`Project0.pck` replacement + a mandatory relaunch** via a detached
  external updater (download → verify → stage → quit → swap keeping a `.bak` →
  relaunch); `--main-pack` or the same-name-pck-next-to-exe picks the boot pack,
  and the swap must run on native paths after exit because `res://` and the
  running exe/pck are file-locked.
- [Research — Godot integrity & signing primitives](issues/03-research-godot-integrity-signing-primitives.md):
  Godot 4.3 natively (mbedTLS) has **RSA `Crypto.sign`/`verify` + streaming
  SHA-256**, and `verify()` accepts a **public-only** key — so ship only a trusted
  public key and verify an **offline-signed update manifest** (required version →
  pck SHA-256), then re-hash the pck before apply; fail-closed, and TLS
  authenticates the host not the artifact (necessary but insufficient). No native
  Ed25519 — RSA is the only practical path.

## Not yet specified

<!-- in-scope fog, too dim to ticket yet; graduates as the frontier advances -->

- Release hosting operations and launch-time repair UX remain implementation
  slices, not unresolved contract decisions.
- **Bandwidth / delta** optimization beyond whatever patch unit is chosen
  (revisit after the patch-unit decision).
- How the server operator **publishes / hosts** a new client build (the
  release-and-serve pipeline) — partly shaped by the transport decision, then a
  downstream build slice rather than a charting decision.
- Update behavior differences when connecting **through the WireGuard tunnel**
  vs a direct LAN/WAN connection (revisit after the transport decision).

## Out of scope

<!-- ruled beyond the destination; closed, never graduates -->

- Dev/source client updates (handled by `git`).
- Non-Windows packaged clients (macOS/Linux distributables).
- Public code-signing certificates, app-store / CDN distribution, matchmaking,
  and NAT-traversal auto-discovery.
- Building and operating the release-hosting infrastructure as production infra
  (the spec decides the contract; standing it up is downstream implementation).
- Silent/optional background updates while a session is running — v1 gates only
  at connect.
