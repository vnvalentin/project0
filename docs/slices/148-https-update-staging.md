# Slice 148 - Phase 16 (F-037): HTTPS update staging

GitHub issue: #100 (Goal: client-auto-update)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Apply, restart, and rollback", steps 1–4),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md) decision 4.
Consumes the verifier from [Slice 147](147-signed-update-manifest.md); the
manifest URL is handed to the client by the gate in
[Slice 146](146-version-gate-enforcement.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). **Fallback trigger:** Claude CLI
is interactive-only on this machine. The full delivery gate was applied.

## User outcome

An outdated client can now fetch its update and hold it in a scratch area that
only ever contains a patch proven to be the signed one. A refused, corrupted, or
interrupted download leaves nothing behind for a later run to trip over.

## Scope and non-goals

In scope: deriving the manifest/signature URLs from an HTTPS base, bounded HTTPS
retrieval of the manifest, its detached signature, and the patch, and the staging
boundary that verifies before it keeps and destroys the scratch directory on any
failure.

Out of scope: the detached updater, quitting the client, the atomic swap,
relaunch, rollback, the transaction marker, embedding the production public key
(still a caller parameter — see Slice 147), launcher/onboarding, and the
controller placeholder.

## Public seam

`client/update_stager.gd` (`UpdateStager`, a `Node` like the repo's other
bounded HTTP clients):

- `manifest_url(base_url)` / `signature_url(base_url)` — static; return `""` for
  a non-HTTPS base.
- `stage_verified_patch(staging_dir, raw_manifest, signature, public_key_pem, patch_bytes)`
  — static; verifies then stages, or discards and refuses.
- `discard_staging(staging_dir)` — static; unconditional cleanup.
- `fetch_and_stage(base_url, public_key_pem, staging_dir)` — coroutine; the live
  HTTPS path.

Outcomes add `insecure_url`, `transport_error`, `timeout`, `http_error`, and
`staging_unavailable` on top of the verifier's own.

## Design notes

**Every failure path ends in `discard_staging`.** The staging directory is the
handoff to the updater, so anything left in it is something the updater might
later treat as ready. Refusing without cleaning would turn a rejected download
into a latent bad apply.

**The patch is verified from disk after being written, not from the buffer in
memory.** What matters is the bytes the updater will actually swap in, so the
check runs against the file that landed.

**A plaintext base URL cannot even be addressed** — the URL builders return `""`
rather than producing an `http://` address, so there is no path where a
downgrade is attempted and then caught. TLS is still not the trust anchor; the
signature is. The pack URL is followed only after the manifest proves authentic,
so the download target itself is signed data.

The staging root lives under `user://`, never `res://`: the patch is a runtime
artifact, matching the same rule `SqliteStore` follows for its database.

## BDD

1. Given an HTTPS base, then the manifest and signature URLs are derived from it.
2. Given a non-HTTPS base, then it cannot be addressed at all.
3. Given a genuine manifest, signature, and matching patch, then the patch is
   staged and its verified manifest returned.
4. Given a tampered manifest, then nothing is staged and nothing is left on disk.
5. Given a genuinely signed manifest but substituted patch bytes, then the patch
   is refused and deleted.
6. Given a foreign signing key, then nothing is staged.
7. Given a second staging of the same update, then it succeeds (idempotent).
8. Given no staged update, then discarding is a safe no-op.

## Validation

Full GUT suite on the Linux host (working-tree overlay): **770/770 tests passing
across 105/105 scripts, 2445 asserts, exit 0** (from 762/104: +1 script,
+8 tests).

New test: `tests/unit/test_update_stager.gd` (8 tests), using real RSA-3072 keys
and real files, asserting after every refusal that the staging directory does not
exist.

`bash scripts/check_record_sync.sh` → 0 errors, exit 0.

## Known coverage gap (deliberate, must not be forgotten)

`fetch_and_stage` and `_fetch` — the actual HTTPS transport — are **not covered
by automated tests**. The suite has no HTTPS fixture, and standing one up would
need a certificate authority for a path whose security does not rest on TLS
anyway. The transport is deliberately thin (one bounded `HTTPRequest`, the same
shape as `client/enrollment_http_client.gd`), and all trust decisions live in the
tested static functions it delegates to.

This gap is why the accepted contract already requires **packaged-client runtime
evidence** before F-037 can be marked `Implemented`. No claim is made here that
the download path works end-to-end; only the verification and staging behaviour
is evidenced.

## Root-cause learning

No unexpected failure arose. The coverage gap above is recorded rather than
papered over: asserting a transport is correct because it resembles another
transport would be exactly the "claim runtime behaviour without runtime
evidence" this repository forbids.

## Follow-on

Next: the detached updater — quit, atomic swap retaining one `.bak`, relaunch,
post-patch readiness check, rollback, and the transaction marker that bounds
retries. Embedding the production public key lands with it.
