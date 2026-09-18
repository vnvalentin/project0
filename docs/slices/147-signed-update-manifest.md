# Slice 147 - Phase 16 (F-037): signed update-manifest verifier

GitHub issue: #100 (Goal: client-auto-update)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Manifest, patch, and trust"), [ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md)
decision 3. Consumes the version identity from
[Slice 144](144-client-build-version-stamp.md); the gate that hands out the
manifest URL is [Slice 146](146-version-gate-enforcement.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). **Fallback trigger:** Claude CLI
is interactive-only on this machine. The full delivery gate was applied.

## User outcome

The client can now prove an update actually came from the release operator
before it will consider installing it, and prove the downloaded pack is the exact
one that was signed. Nothing unverified can become code on a tester's machine.

## Scope and non-goals

In scope: verifying a detached RSA signature over a received manifest,
fail-closed parsing and validation of its fields, and verifying a downloaded
patch file against the signed size and digest.

Out of scope: fetching anything over the network, embedding the production
public key (a release/operator step; the verifier takes the key as a parameter
so no placeholder key ever ships pretending to be trusted), staging, the
detached updater, the atomic swap, rollback, launcher, and onboarding.

## Public seam

`shared/update_manifest.gd` (`UpdateManifest`):

- `verify_and_parse(raw_bytes, signature, public_key_pem) -> {outcome, detail, manifest}`
- `verify_patch_file(path, manifest) -> {outcome, detail, sha256}`

Outcomes: `ok`, `unverified`, `malformed`, `unsupported_version`,
`key_unusable`, `hash_mismatch`, `size_mismatch`, `unreadable`.

## Design notes

**The signature is verified over the raw bytes exactly as received, before any
parsing.** This is the load-bearing decision. Verifying a re-serialized copy is a
classic signature bypass: two different byte strings can parse to the same
object, so an attacker edits the bytes the program will actually read while the
signature still checks against a normalized form. Verify the bytes you were
given, then read them. It also removes canonicalization from the trust path
entirely — there is no canonical form to disagree about.

`manifest` is `null` on every non-`ok` outcome, so a caller cannot accidentally
read fields out of a document that was never verified.

`key_unusable` is distinct from `unverified` for the same reason Slice 145 has
`SERVER_MISCONFIGURED`: a broken trusted key is an operator fault, and reporting
it as a failed signature would send someone hunting for an attacker.

Patch verification checks **size first, then a streamed digest**: the size check
is cheap and bounds the work, and streaming means a multi-hundred-megabyte pack
is never held in memory. Size alone is explicitly not treated as proof — there is
a test for equal-length, wrong-content.

`pck_url` must be HTTPS and `pck_sha256` must be lowercase 64-hex; a signed
manifest that fails structural validation is still refused, because a valid
signature over nonsense is still nonsense.

## BDD

1. Given a correctly signed manifest, then it verifies and parses.
2. Given a tampered document with a valid signature for the original, then
   `unverified`.
3. Given a signature from a foreign key, then `unverified`.
4. Given an empty signature or empty document, then `unverified`.
5. Given an unusable trusted key, then `key_unusable`, never a pass.
6. Given a signed but structurally invalid manifest, then refused.
7. Given a patch matching the signed size and digest, then `ok`.
8. Given a patch of the right size but wrong contents, then `hash_mismatch`.
9. Given a patch of the wrong size, then `size_mismatch`.
10. Given a missing patch file, then `unreadable`.

## Validation

Full GUT suite on the Linux host (working-tree overlay): **762/762 tests passing
across 104/104 scripts, 2422 asserts, exit 0** (from 751/103: +1 script,
+11 tests).

New test: `tests/unit/test_update_manifest.gd` (11 tests). It generates **real
RSA-3072 keypairs in-test** and signs with them, so the production
`Crypto.verify` path is exercised rather than a double — including a genuine
tampered-document case and a genuine foreign-key case. Two engine `ERROR` lines
appear in the log from the deliberately bad inputs (an unparseable PEM and
non-JSON); both are the inputs under test and are handled, not failures.

`bash scripts/check_record_sync.sh` → 0 errors, exit 0.

## Root-cause learning

No unexpected failure arose. Worth recording for the slices that follow: the
verifier is deliberately **not** wired to a trusted key yet. Shipping a
placeholder key would create a verifier that appears functional while trusting
nothing real — the most dangerous possible state for a remote-code-delivery path.
The key is supplied by the caller until the release process that generates and
embeds it exists.

## Follow-on

Next in the contract: HTTPS retrieval and staging of the manifest, signature, and
patch (which consumes this verifier), then the detached updater with atomic swap
and rollback. Embedding the production public key is a release/operator step that
must land with the updater, not before it.
