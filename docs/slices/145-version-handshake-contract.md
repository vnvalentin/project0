# Slice 145 - Phase 16 (F-037): pre-auth version handshake contract and required-version resolution

GitHub issue: #100 (Goal: client-auto-update)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Version handshake"), [ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md)
decision 2. Builds directly on [Slice 144](144-client-build-version-stamp.md),
which gave the client its own build identity.

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). **Fallback trigger:** Claude CLI
is interactive-only on this machine (`claude` and `claude -p` both open a
full-screen TUI and return no session or evidence; the `Claude:` VS Code tasks
fail on an unresolved `${relativeFile}`). The full delivery gate was applied.

## User outcome

The server can now decide, from a client's declared build version, whether that
client is allowed to proceed — and when it is not, it can say exactly which
version is required and where the update lives. This is the decision the
mandatory pre-auth gate will enforce.

## Scope and non-goals

In scope: the shared, pure, fully-tested handshake contract — the request the
client sends, the server-owned required-version and manifest-URL resolution, and
the bounded evaluation that yields `ACCEPTED` or a fail-closed rejection.

Out of scope, deliberately: **live wiring and enforcement**. Nothing in this
slice sends a message, registers an RPC, disconnects a peer, or changes
`server_main.gd` / `network_client.gd`. The connect lifecycle in those files is a
declared shared hot-spot in the Project Tracker's "Must sequence" list, so the
enforcement slice edits them on its own, against a contract that is already
proven. Also out of scope: signed manifest retrieval/verification, patch
staging, the updater, rollback, launcher, and onboarding.

## Public seam

`shared/version_handshake.gd` (`VersionHandshake`):

- `request() -> Dictionary` — what the client sends first, carrying the
  handshake `schema_version` and `ClientBuildVersion.current()`.
- `resolve_required_version() -> String` — server-owned, from
  `PROJECT0_REQUIRED_CLIENT_VERSION`, defaulting to this build's own version.
  Returns `""` when the override is set but malformed, so the caller fails
  closed instead of serving a mis-configured gate.
- `resolve_manifest_base_url() -> String` — from
  `PROJECT0_UPDATE_MANIFEST_BASE_URL`; a non-HTTPS value is treated as unset.
- `evaluate(request, required_version, manifest_base_url) -> Dictionary` —
  `{outcome, detail, required_version, manifest_base_url}`.

Outcomes: `ACCEPTED`, `CLIENT_OUTDATED`, `MALFORMED`,
`SERVER_MISCONFIGURED`, and the reserved `UNSUPPORTED`.

## Design notes

Comparison is **exact string equality**, per the accepted contract. There is no
"is newer" ordering: ordering invites a client arguing it is new enough, and the
server is the only authority on what it will serve.

`SERVER_MISCONFIGURED` exists so an operator's bad
`PROJECT0_REQUIRED_CLIENT_VERSION` cannot masquerade as `CLIENT_OUTDATED`.
Without it, an unparseable required version compares unequal to everything and
would tell every tester to update — blaming the player for an operator fault,
which the repository's Zen Validation rule forbids. It is a distinct,
operator-facing outcome.

A non-HTTPS manifest URL is treated as unset rather than passed through, so the
server can never advertise a plaintext update source. TLS is still not the trust
anchor — the signature is (ADR 0008) — but advertising `http://` would be a
downgrade the later slices should not have to defend against.

`UNSUPPORTED` is reserved and intentionally unreachable today; a structurally
wrong request is `MALFORMED`. It is kept in the enum because the accepted
contract names it for future protocol negotiation.

## BDD

1. Given a client request, then it carries the handshake schema version and the
   client's own build version.
2. Given a request whose version equals the required version, then `ACCEPTED`.
3. Given a request whose version differs, then `CLIENT_OUTDATED` carrying the
   required version and the manifest URL.
4. Given a non-Dictionary, a wrong `schema_version`, a missing version, or a
   malformed version, then `MALFORMED` — never `ACCEPTED`.
5. Given a malformed required version, then `SERVER_MISCONFIGURED`, never
   `CLIENT_OUTDATED`.
6. Given no `PROJECT0_REQUIRED_CLIENT_VERSION`, then the required version
   defaults to this build's own version (a stock server accepts its own client).
7. Given a malformed override, then resolution returns `""` so the caller fails
   closed.
8. Given a non-HTTPS manifest URL, then it is treated as unset.

## Validation

Executed on the Linux host (working-tree overlay onto the deploy tree):

- `bash scripts/run_gut_validation.sh` → **747/747 tests passing across 102/102
  scripts, 2387 asserts, exit 0** (from 734/101 on `main`: +1 script, +13 tests,
  exactly the new test file). 4 pre-existing headless warnings, unrelated.
- `bash scripts/check_record_sync.sh` → 0 errors, exit 0.

New test: `tests/unit/test_version_handshake.gd` (13 tests) covering the request
shape, acceptance, a stock server accepting its own client, mismatch carrying
patch directions, older *and* newer clients being refused identically, six
structurally wrong requests, seven malformed declared versions, the manifest URL
never leaking to accepted/malformed cases, four operator-misconfiguration cases,
the default/valid/malformed override paths, and HTTPS-only manifest URLs.

## Root-cause learning

No unexpected failure arose in this slice. The environment limitation (Claude CLI
interactive-only; local MSYS2 bash wedged by its TUI so bash validation runs on
the Linux host over SSH) is already recorded in
[Slice 144](144-client-build-version-stamp.md) and the shared agent notes.

## Follow-on

The next slice wires this contract live: the client sends `request()` as its
first post-connect message, and `server_main.gd` evaluates it before any
login/register RPC, disconnecting a rejected peer with its bounded reason and
refusing to serve at all when the gate is `SERVER_MISCONFIGURED`.
