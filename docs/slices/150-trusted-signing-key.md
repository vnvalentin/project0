# Slice 150 - Phase 16 (F-037): trusted release key and one-command signing

GitHub issue: #100 (Goal: client-auto-update)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Manifest, patch, and trust"),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md) decision 3.
Completes [Slice 147](147-signed-update-manifest.md), which deliberately shipped
the verifier without a key.

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). **Fallback trigger:** Claude CLI
is interactive-only on this machine. The full delivery gate was applied.

## User outcome

The client now has a real basis for trusting an update, and publishing one is a
single command. Slice 147 could verify a signature but had no key to verify
against; that hole is closed.

## Scope and non-goals

In scope: the trusted public key embedded in the pack, its fingerprint, a
configured check callers use before attempting an update at all, and
`scripts/sign_release.sh` for producing a signed release.

Out of scope: the updater's process orchestration, the enrollment host's
`/patches` static route, and publishing an actual release.

## Key custody (operator-facing)

- **Generated:** 2026-09-18, RSA-3072, on the operator workstation.
- **Private key:** `~/project0-signing/project0-release-private.pem`, mode
  `0600`, **offline**. Never in this repository, on the enrollment host, or in
  CI — the signature exists to survive those being compromised, so a key
  reachable from any of them would be worthless. It was deliberately generated
  on the workstation rather than on `okami` for exactly that reason.
- **Public key:** embedded here as `ClientSigningKey.TRUSTED_PUBLIC_KEY_PEM`.
- **Fingerprint:** `69db4c67c0202e617925d6c6e82d1b54949ade0a48419e3d4ded8a001677a232`
  (SHA-256 of the DER SubjectPublicKeyInfo).
- **No passphrase**, so release signing can be scripted. Adding one later with
  `openssl rsa -aes256` does not change the key material, so the public key and
  every existing signature stay valid — the decision is reversible.
- **Backup is an operator responsibility.** The key exists on one disk; losing it
  means every future update requires a fresh trusted re-release to every tester.
- **Rotation** is a full re-release through the trusted channel. There is
  deliberately no in-band key-update path, because an in-band path is the hole
  this design closes.

## Public seam

- `shared/client_signing_key.gd` (`ClientSigningKey`):
  `TRUSTED_PUBLIC_KEY_PEM`, `TRUSTED_KEY_FINGERPRINT`,
  `trusted_public_key_pem()`, `is_configured()`.
- `scripts/sign_release.sh <version> <pck> <base-url> [out-dir]` — emits
  `manifest.json` + detached `manifest.sig`; reads the key path from
  `PROJECT0_SIGNING_KEY` so it is never typed or echoed.

## Design notes

**Anti-swap property.** The updater verifies the *next* pack's manifest using the
key in the *currently installed* pack, which the tester obtained through the
trusted first-run channel. An attacker who can substitute a download therefore
cannot substitute the key that judges it.

**`is_configured()` exists so a keyless build fails closed.** A build that cannot
load its trusted key must refuse to self-update rather than fall back to trusting
the download — the failure mode that would otherwise turn this whole feature into
an arbitrary-code-execution channel.

**The manifest is signed byte-for-byte as emitted.** The script writes it
compactly and signs exactly those bytes, because the client verifies the bytes it
received *before* parsing them (Slice 147). Reformatting or re-serializing a
signed manifest invalidates it — called out in the script's comments.

The script refuses a malformed version, a missing pack, a missing key, and a
non-HTTPS base URL. The version rule is kept identical to
`ClientBuildVersion.is_valid` so a release can never be published under a version
the client's own gate would refuse to parse.

## BDD

1. Given the shipped build, then its trusted key loads.
2. Given the shipped key, then it matches its recorded fingerprint.
3. Given the shipped key, then it contains no private material.
4. Given a manifest signed by any other key, then it is refused.
5. Given a valid version, pack, and HTTPS base, then signing emits a manifest and
   signature.
6. Given a malformed version, missing pack, missing key, or plaintext URL, then
   signing refuses.

## Validation

**Full trust chain, executed with the real offline key and the real script** —
sign on the workstation, verify with the shipped verifier and embedded key on the
Linux host:

```
embedded key configured: true
embedded fingerprint:    69db4c67…77a232
verify_and_parse:        ok
  required_client_version: 0.7.0
  pck_url:                 https://enroll.valentin.vip/patches/0.7.0/Project0.pck
  size_bytes:              5000
verify_patch_file:       ok
tampered pack:           hash_mismatch
```

`scripts/sign_release.sh` refusal paths, each exiting non-zero: malformed version
`1.2`, missing pack, plaintext `http://` base URL, and missing signing key.

Full GUT suite on the Linux host: **774/774 tests passing across 106/106
scripts, 2451 asserts, exit 0** (from 770/105: +1 script, +4 tests).

New test: `tests/unit/test_client_signing_key.gd` (4 tests).

`bash scripts/check_record_sync.sh` → 0 errors, exit 0.

Note: the fingerprint was verified two ways — recomputed inside the test suite
from the embedded PEM, and independently via `openssl` at generation time.

## Root-cause learning

**Defect caught by the new test, before merge.** The fingerprint test initially
stripped the PEM armour with `replace("\n", "")`, which leaves the `\r` of a CRLF
checkout in the base64. `Marshalls.base64_to_raw` then returned an empty array and
the test compared the SHA-256 of *nothing*
(`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`) against the
real fingerprint. The empty-input digest is the tell: seeing `e3b0c442…` in a hash
comparison means the hasher was fed nothing, not that the data is wrong.
Countermeasure: the PEM body is now assembled line-wise with `strip_edges()`, so
the digest is identical under LF and CRLF checkouts, plus an explicit
`assert_gt(der.size(), 0)` so an empty decode fails as an empty decode rather than
as a mismatched fingerprint. This is the second CRLF-induced defect in this phase
(Slice 144's stamp guard was the first) — on this repository, any byte-level text
handling must be assumed to meet CRLF.

Also worth recording: OpenSSL/Godot signature compatibility was **verified with a
throwaway key before** the real key was generated, rather than assumed. Godot's
`Crypto.verify` uses mbedTLS and `openssl dgst -sha256 -sign` uses PKCS#1 v1.5;
they agree, but discovering otherwise *after* generating and distributing a
production key would have been expensive. The throwaway key was destroyed after
the check.

## Follow-on

The updater's process orchestration and the `/patches` static route on the
enrollment host are next. Publishing a real release and proving self-update
end-to-end still requires packaged-Windows runtime evidence.
