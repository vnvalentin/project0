# Windows Client Delivery Contract

Status: **handoff-ready; implementation not started**

Phase: 16 — Client delivery experience

Source maps: [client auto-update](map.md), [unified launcher](../unified-launcher/map.md), [controller integration](../controller-integration/map.md)

Architecture decision: [ADR 0008](../../docs/adr/0008-windows-client-delivery-trust-and-rollback.md)

GitHub issues: [#100](https://github.com/vnvalentin/project0/issues/100) client
auto-update, [#182](https://github.com/vnvalentin/project0/issues/182) unified
launcher, [#117](https://github.com/vnvalentin/project0/issues/117) controller
integration.

## User outcome

A packaged Windows tester can select LAN or WAN mode in one launcher, complete the
right first-run onboarding, and enter the server with a client payload that meets
the server-owned version gate. Outdated payloads are mandatory-updated through a
signed, HTTPS-delivered full `.pck` replacement; failed or interrupted updates
preserve the last known-good build. Xbox-compatible controllers can use the same
named client actions as keyboard and mouse without changing server authority.

## Canonical terms

- **Client build version**: the semver identity of a packaged client build. It is
the authoritative version-comparison key and is distinct from data-contract
`schema_version` and `tuning_version` fields.
- **Update manifest**: an offline-signed record binding one required client build
version to one full `Project0.pck` URL, SHA-256, and byte size.
- **Patch**: the complete replacement `Project0.pck` for one client build version;
v1 does not use deltas.
- **Version handshake**: the first client/server message after ENet connection,
before authentication, in which the client presents its build version and the
server accepts or rejects it.

## Version identity

The packaged client contains a generated `shared/client_build_version.gd` const
written by `scripts/export_windows_client.sh`, for example
`CLIENT_BUILD_VERSION = "0.6.0"`. The `.pck` is the authoritative runtime source;
Windows executable metadata is informational only.

The server resolves `PROJECT0_REQUIRED_CLIENT_VERSION` from server-owned
configuration, with a release-matched default. The version gate requires exact
string equality. The `.pck` SHA-256 is an integrity identity, not the comparison
key. Opaque build ids are not used in v1.

## Version handshake

The client sends its build version as the first post-connect message. The server
owns the decision and must complete this gate before login or registration RPCs.
The shared contract carries:

- client build version;
- server result: `ACCEPTED` or rejection;
- rejection reason: `CLIENT_OUTDATED`, `MALFORMED`, or reserved `UNSUPPORTED`;
- required client version when relevant;
- HTTPS manifest base URL when an update is available.

The server rejects malformed or mismatched input fail-closed. A client cannot
self-certify by claiming a compatible version. The update URL is server-supplied;
its bytes are trusted only after manifest signature verification.

## Manifest, patch, and trust

V1 uses a full `Project0.pck` replacement. The canonical signed manifest contains:

```json
{
  "schema_version": 1,
  "required_client_version": "0.6.0",
  "pck_sha256": "<lowercase hex SHA-256>",
  "pck_url": "https://enrollment.example/patches/0.6.0/Project0.pck",
  "size_bytes": 12345678
}
```

The release operator signs the canonical manifest bytes offline with RSA-3072 and
publishes a detached `manifest.sig`. The client ships only the trusted public key
inside the currently trusted `.pck`; the private key never enters the repository,
CI, or enrollment host. Key rotation requires a trusted full re-release in v1.

HTTPS is required for transport but is not the artifact trust anchor. The client
must verify the RSA signature before trusting manifest fields, then stream-hash
the downloaded `.pck` and compare its size and SHA-256 to the signed manifest.
Any unverifiable, mismatched, malformed, or out-of-bounds payload is refused,
deleted from staging, and never applied.

## Apply, restart, and rollback

A detached external updater owns file replacement because a running Godot process
cannot safely replace its active `.pck` or hot-reload its scripts and autoloads.

**Corrected 2026-09-18 by measurement.** A probe against the real packaged
Windows client (Godot 4.3, `Project0.exe` + separate `Project0.pck`, confirmed
dependent on that pack) found that Windows does **not** lock the pack while the
client runs: rename, open-for-write, and even delete all succeeded against a live
client. The quit-then-swap ordering is still required, but for different reasons:
Godot cannot hot-reload the running scripts, scenes, and autoloads; resources
loaded lazily afterwards would come from the *new* pack while the *old* code is
still running; and because the OS offers no protection here, the updater's own
discipline is the only thing preventing a half-applied swap under a live client.
The flow is:

1. Fetch manifest and detached signature to a temporary directory.
2. Verify the signature and required version.
3. Download the full `.pck` to a temporary file.
4. Verify byte size and streaming SHA-256.
5. Start the updater with the verified staging path.
6. Quit the running client.
7. Atomically retain the current `.pck` as one `.bak` and move the staged file
   into place.
8. Relaunch the client and require its post-patch version handshake/readiness.

The updater retains one prior known-good build. It restores that build after a
swap/relaunch failure, startup failure, post-patch handshake failure, or an
interrupted swap detected on the next startup. A transaction marker records
`pending_version`, `previous_version`, `staged_sha256`, `swap_started`, and
`attempt_count`. One retry/rollback is allowed per version; repeated failure
enters `repair_required` and emits `rollback_exhausted` instead of looping.

The tester sees required version, download/verification progress, restarting
state, and a bounded failure or repair message. There is no bypass, silent
background update, or partial play session in v1.

## Unified launcher

The launcher owns the persisted LAN/WAN choice. First-run default is WAN;
explicit LAN host entry is required and discovery never selects a mode.

WAN mode sets `PROJECT0_TUNNEL=1` and `PROJECT0_CLIENT_HTTPS_LOGIN=1`, then uses
existing login, signed assertion, WireGuard peer redemption, and DPAPI-protected
key plumbing. LAN mode sets `PROJECT0_TUNNEL=0`,
`PROJECT0_CLIENT_HTTPS_LOGIN=0`, and launches with the remembered `--server-host`;
it uses the existing ENet login path. A selected path that is unreachable shows
a bounded error and does not silently switch modes.

The version/update gate runs before onboarding. A returning WAN user with valid
protected peer state launches directly. New WAN users follow login, assertion,
peer redemption, DPAPI protection, and launch. New LAN users enter a host and use
account selection/login without tunnel enrollment. Registration stays on the
existing HTTPS enrollment surface; `--invite-code` remains the WAN fallback.
Passwords are memory-only.

## Controller boundary

V1 targets standard Windows XInput devices, including Xbox One/Series controllers
wired or over Bluetooth and XInput-compatible third-party devices. Godot 4.3's
built-in `InputMap`/Joypad support is used; no third-party input library or server
protocol change is needed. The left stick maps to the existing movement actions,
and the south/A button maps to `attack`. Keyboard and mouse bindings remain
unchanged. DirectInput-only devices are best-effort/unsupported in v1.

Rebinding UI, menu navigation, vibration, device glyphs, extra actions, and
platform certification are out of scope.

## Telemetry

Events are bounded and non-sensitive:

`version_check_started`, `version_accepted`, `client_outdated`,
`manifest_unverified`, `pck_hash_mismatch`, `patch_staged`, `patch_applied`,
`rollback_started`, `rollback_completed`, `rollback_exhausted`, and
`repair_required`.

Fields may include `client_build_version`, `required_client_version`, `result`,
`failure_reason`, `duration_ms`, and `attempt_count`. Do not record passwords,
tokens, full URLs, raw server responses, or patch contents. Hashes are omitted by
default and may only be represented by a truncated operational identifier.

## Public seams and slices

Implementation must preserve these boundaries:

- `shared/version_handshake.gd`: typed pre-auth contract and bounded outcomes.
- `server/server_main.gd`: server-owned version gate before auth.
- `client/network_client.gd`: first-message handshake and bounded rejection path.
- `scripts/export_windows_client.sh`: generated build-version stamp.
- Windows launcher/updater: manifest retrieval, signature/hash verification,
staging, atomic swap, restart, rollback, and repair state.
- `project.godot`/Godot `InputMap`: XInput aliases for existing named actions.

Suggested implementation slices are: version identity/export stamp; handshake
contract and gate; signed manifest verifier; HTTPS patch staging; detached updater
and rollback; launcher LAN/WAN contract; onboarding integration; controller
placeholder; and end-to-end packaged-client validation. Each slice requires a
public-seam test, bounded telemetry, record synchronization, and rollback evidence.

## Required validation

- GUT unit/integration tests for handshake acceptance, outdated/malformed refusal,
manifest signature failures, hash/size mismatch, staging, idempotent re-check,
and rollback after interruption/startup failure.
- Windows launcher Go tests from `native/windows_launcher`.
- Packaged Windows smoke tests for LAN, WAN, first run, returning user, mandatory
update, failed verification, rollback, and XInput movement/attack.
- No claim of update or rollback behavior without executable packaged-client
runtime evidence.

## Non-goals

Dev/source updates via git, non-Windows packaged clients, public code-signing
certificates, CDN/app-store distribution, launcher self-update, delta patches,
silent background updates, matchmaking, NAT discovery, rebinding, vibration, and
production-wide controller certification remain out of scope.
